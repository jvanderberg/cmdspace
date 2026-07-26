import CoreServices
import Darwin
import Foundation

actor DriveIndexer {
    typealias ProgressHandler = @Sendable (IndexProgress) -> Void

    private static let dataVolume = "/System/Volumes/Data"
    private let database: SearchDatabase
    private var running = false
    private var monitor: FileSystemMonitor?
    private var monitoringProgress: ProgressHandler?

    init(database: SearchDatabase) {
        self.database = database
    }

    func startMonitoring(progress: @escaping ProgressHandler) async {
        monitoringProgress = progress
        if monitor == nil {
            let lastEventID = try? await database.lastFileSystemEventID()
            monitor = FileSystemMonitor(
                sinceWhen: lastEventID ?? FSEventStreamEventId(
                    kFSEventStreamEventIdSinceNow
                )
            ) { [weak self] changes in
                Task {
                    await self?.applyIncrementalChanges(changes)
                }
            }
        }
        monitor?.start()
    }

    func stopMonitoring() {
        monitor?.stop()
        monitor = nil
        monitoringProgress = nil
    }

    /// Index the sealed system volume and writable Data volume separately.
    /// FTS_XDEV keeps the root scan from following APFS firmlinks into Data;
    /// Data paths are stored in their familiar `/Users`, `/Applications`, …
    /// spelling so results open naturally and are never duplicated.
    func refresh(progress: @escaping ProgressHandler) async {
        guard !running else { return }
        running = true
        let shouldRestartMonitoring = monitor != nil
        monitor?.stop()
        defer {
            running = false
            if shouldRestartMonitoring {
                monitor?.start()
            }
        }

        let generation = Int64(Date().timeIntervalSince1970 * 1_000)
        var itemCount = 0
        var skippedCount = 0
        var batch: [IndexedItem] = []

        do {
            try await database.beginIndex(generation: generation)
            progress(IndexProgress(
                phase: .scanning,
                itemCount: 0,
                skippedCount: 0,
                message: "Indexing this Mac…"
            ))

            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            let physicalHome = Self.dataVolume + homePath
            let applications = discoverApplications()
            try await database.upsert(applications, generation: generation)
            itemCount += applications.count
            progress(IndexProgress(
                phase: .scanning,
                itemCount: itemCount,
                skippedCount: 0,
                message: "Applications ready · indexing files…"
            ))

            // Make the user's own files searchable next, then fill in the
            // remainder of Data and the lower-value sealed system tree.
            let roots = [
                physicalHome,
                Self.dataVolume,
                "/"
            ].filter { FileManager.default.fileExists(atPath: $0) }

            for rootPath in roots {
                var pathArguments: [UnsafeMutablePointer<CChar>?] = [strdup(rootPath), nil]
                defer { free(pathArguments[0]) }
                guard let stream = fts_open(
                    &pathArguments,
                    FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV,
                    nil
                ) else {
                    skippedCount += 1
                    continue
                }

                while let entry = fts_read(stream) {
                    if Task.isCancelled {
                        fts_close(stream)
                        await database.cancelIndex()
                        return
                    }

                    let info = Int32(entry.pointee.fts_info)
                    let level = Int(entry.pointee.fts_level)
                    let physicalPath = String(cString: entry.pointee.fts_path)
                    let name = entryName(entry)

                    switch info {
                    case FTS_D:
                        if level == 0 { continue }
                        if shouldSkipDirectory(
                            physicalPath: physicalPath,
                            name: name,
                            level: level,
                            scanRoot: rootPath,
                            priorityHome: physicalHome
                        ) {
                            _ = fts_set(stream, entry, FTS_SKIP)
                            skippedCount += 1
                            continue
                        }

                        let canonicalPath = canonicalPath(for: physicalPath)
                        let isApplication = name.lowercased().hasSuffix(".app")
                        let displayName = isApplication
                            ? String(name.dropLast(4))
                            : name
                        batch.append(IndexedItem(
                            path: canonicalPath,
                            name: displayName,
                            normalizedName: SearchDatabase.normalize(displayName),
                            kind: isApplication ? .application : .folder,
                            bundleIdentifier: isApplication
                                ? Bundle(url: URL(fileURLWithPath: physicalPath))?.bundleIdentifier
                                : nil,
                            modifiedAt: modificationDate(entry),
                            fileSize: nil
                        ))
                        itemCount += 1

                        if isApplication || isKnownPackage(name) {
                            _ = fts_set(stream, entry, FTS_SKIP)
                        }

                    case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                        guard level > 0 else { continue }
                        let canonicalPath = canonicalPath(for: physicalPath)
                        batch.append(IndexedItem(
                            path: canonicalPath,
                            name: name,
                            normalizedName: SearchDatabase.normalize(name),
                            kind: .file,
                            bundleIdentifier: nil,
                            modifiedAt: modificationDate(entry),
                            fileSize: logicalSize(entry)
                        ))
                        itemCount += 1

                    case FTS_DNR, FTS_ERR, FTS_NS:
                        skippedCount += 1

                    default:
                        break
                    }

                    if batch.count >= 1_000 {
                        try await database.upsert(batch, generation: generation)
                        batch.removeAll(keepingCapacity: true)
                    }
                    if itemCount > 0, itemCount.isMultiple(of: 5_000) {
                        progress(IndexProgress(
                            phase: .scanning,
                            itemCount: itemCount,
                            skippedCount: skippedCount,
                            message: "Indexed \(itemCount.formatted()) items…"
                        ))
                        await Task.yield()
                    }
                }
                fts_close(stream)
            }

            try await database.upsert(batch, generation: generation)
            try await database.finishIndex(generation: generation)
            progress(IndexProgress(
                phase: .complete,
                itemCount: itemCount,
                skippedCount: skippedCount,
                message: "Ready · \(itemCount.formatted()) items"
            ))
        } catch {
            await database.cancelIndex()
            progress(IndexProgress(
                phase: .failed,
                itemCount: itemCount,
                skippedCount: skippedCount,
                message: "Index failed — \(error.localizedDescription)"
            ))
        }
    }

    private func applyIncrementalChanges(_ changes: [FileSystemChange]) async {
        guard !running, !changes.isEmpty else { return }
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
        )
        if changes.contains(where: { $0.flags & rescanFlags != 0 }) {
            await refresh(progress: monitoringProgress ?? { _ in })
            if let latestEventID = changes.map(\.eventID).max() {
                try? await database.setLastFileSystemEventID(latestEventID)
            }
            return
        }

        do {
            let latestEventID = changes.map(\.eventID).max()
            let generation = try await database.currentGeneration()
            var removedPaths = Set<String>()
            var upsertsByPath: [String: IndexedItem] = [:]

            for change in changes {
                guard let path = incrementalRoot(for: change.path),
                      path != "/",
                      !shouldIgnoreIncrementalPath(path) else {
                    continue
                }

                if FileManager.default.fileExists(atPath: path) {
                    let includeDescendants = change.flags
                        & FSEventStreamEventFlags(
                            kFSEventStreamEventFlagItemCreated
                                | kFSEventStreamEventFlagItemRenamed
                        ) != 0
                    for item in incrementalItems(
                        at: path,
                        includeDescendants: includeDescendants
                    ) {
                        upsertsByPath[item.path] = item
                    }
                } else {
                    removedPaths.insert(canonicalPath(for: path))
                }
            }

            try await database.remove(paths: Array(removedPaths))
            try await database.upsert(Array(upsertsByPath.values), generation: generation)
            if let latestEventID {
                try await database.setLastFileSystemEventID(latestEventID)
            }

            guard !removedPaths.isEmpty || !upsertsByPath.isEmpty else { return }
            let count = try await database.indexedItemCount()
            monitoringProgress?(IndexProgress(
                phase: .complete,
                itemCount: count,
                skippedCount: 0,
                message: "Ready · \(count.formatted()) items"
            ))
        } catch {
            monitoringProgress?(IndexProgress(
                phase: .failed,
                itemCount: 0,
                skippedCount: 0,
                message: "Live update failed — \(error.localizedDescription)"
            ))
        }
    }

    private func incrementalRoot(for rawPath: String) -> String? {
        var path = rawPath
        if path.hasPrefix(Self.dataVolume + "/") {
            path = String(path.dropFirst(Self.dataVolume.count))
        }
        let components = URL(fileURLWithPath: path).pathComponents
        var current = ""
        for component in components {
            if component == "/" {
                current = "/"
                continue
            }
            current = (current as NSString).appendingPathComponent(component)
            if isKnownPackage(component) {
                return current
            }
        }
        return path
    }

    private func incrementalItems(
        at path: String,
        includeDescendants: Bool
    ) -> [IndexedItem] {
        let url = URL(fileURLWithPath: path)
        guard let rootItem = indexedItem(for: url) else { return [] }
        var items = [rootItem]
        guard includeDescendants,
              rootItem.kind == .folder,
              !isKnownPackage(url.lastPathComponent) else {
            return items
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return items
        }

        while let child = enumerator.nextObject() as? URL {
            if shouldIgnoreIncrementalPath(child.path) {
                enumerator.skipDescendants()
                continue
            }
            guard let item = indexedItem(for: child) else { continue }
            items.append(item)
            if item.kind == .application || isKnownPackage(child.lastPathComponent) {
                enumerator.skipDescendants()
            }
        }
        return items
    }

    private func indexedItem(for url: URL) -> IndexedItem? {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]) else {
            return nil
        }
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        let isApplication = values.isDirectory == true
            && name.lowercased().hasSuffix(".app")
        let displayName = isApplication ? String(name.dropLast(4)) : name
        return IndexedItem(
            path: canonicalPath(for: url.path),
            name: displayName,
            normalizedName: SearchDatabase.normalize(displayName),
            kind: isApplication ? .application : values.isDirectory == true ? .folder : .file,
            bundleIdentifier: isApplication ? Bundle(url: url)?.bundleIdentifier : nil,
            modifiedAt: values.contentModificationDate?.timeIntervalSince1970,
            fileSize: values.isDirectory == true ? nil : values.fileSize.map(Int64.init)
        )
    }

    private func shouldIgnoreIncrementalPath(_ path: String) -> Bool {
        let canonical = canonicalPath(for: path)
        if canonical == "/Volumes" || canonical.hasPrefix("/Volumes/")
            || canonical == "/home" || canonical.hasPrefix("/home/")
            || canonical == "/net" || canonical.hasPrefix("/net/") {
            return true
        }

        let components = URL(fileURLWithPath: canonical).pathComponents
        let noisyNames: Set<String> = [
            ".git", ".svn", ".hg", ".Trash", "node_modules",
            "__pycache__", "DerivedData", ".build"
        ]
        if components.contains(where: {
            noisyNames.contains($0) || ($0.hasPrefix(".") && $0 != "." && $0 != "..")
        }) {
            return true
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let ignoredRoots = [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Application Support/CmdSpace"
        ]
        return ignoredRoots.contains {
            canonical == $0 || canonical.hasPrefix($0 + "/")
        }
    }

    private func canonicalPath(for physicalPath: String) -> String {
        if physicalPath == Self.dataVolume { return "/" }
        if physicalPath.hasPrefix(Self.dataVolume + "/") {
            return String(physicalPath.dropFirst(Self.dataVolume.count))
        }
        return physicalPath
    }

    /// Find app bundles with a deliberately shallow walk, commit them before
    /// the full scan, and never descend into vendor payload directories.
    private func discoverApplications() -> [IndexedItem] {
        let roots = [
            Self.dataVolume + "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications"
        ]
        var pending = roots.map { (url: URL(fileURLWithPath: $0), depth: 0) }
        var applications: [IndexedItem] = []
        var seenPaths = Set<String>()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .contentModificationDateKey
        ]

        while let candidate = pending.popLast() {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: candidate.url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                guard let values = try? child.resourceValues(forKeys: keys),
                      values.isDirectory == true else { continue }
                if child.pathExtension.lowercased() == "app" {
                    let path = canonicalPath(for: child.path)
                    guard seenPaths.insert(path).inserted else { continue }
                    let displayName = String(child.lastPathComponent.dropLast(4))
                    applications.append(IndexedItem(
                        path: path,
                        name: displayName,
                        normalizedName: SearchDatabase.normalize(displayName),
                        kind: .application,
                        bundleIdentifier: Bundle(url: child)?.bundleIdentifier,
                        modifiedAt: values.contentModificationDate?.timeIntervalSince1970,
                        fileSize: nil
                    ))
                } else if candidate.depth < 2 {
                    pending.append((url: child, depth: candidate.depth + 1))
                }
            }
        }
        return applications
    }

    /// Avoid known enumeration hazards plus high-volume generated data that
    /// is actively harmful in a filename launcher.
    private func shouldSkipDirectory(
        physicalPath: String,
        name: String,
        level: Int,
        scanRoot: String,
        priorityHome: String
    ) -> Bool {
        // These high-value subtrees were scanned first. Avoid doing the work
        // twice when the broader Data-volume pass reaches them.
        if scanRoot == Self.dataVolume,
           physicalPath == Self.dataVolume + "/Applications"
            || physicalPath == priorityHome {
            return true
        }

        if name == "CloudStorage", physicalPath.hasSuffix("/Library/CloudStorage") {
            return true
        }

        let canonical = canonicalPath(for: physicalPath)
        if ["/Volumes", "/home", "/net"].contains(canonical) {
            return true
        }

        let noisyNames: Set<String> = [
            ".git", ".svn", ".hg", ".Trash", "node_modules",
            "__pycache__", "DerivedData"
        ]
        if noisyNames.contains(name) || name.hasPrefix(".") {
            return true
        }

        let userHome = FileManager.default.homeDirectoryForCurrentUser.path
        let noisyUserPaths = [
            "\(userHome)/Library/Caches",
            "\(userHome)/Library/Logs",
            "\(userHome)/Library/Containers",
            "\(userHome)/Library/Group Containers"
        ]
        if noisyUserPaths.contains(canonical) {
            return true
        }

        // The root scan handles the sealed system volume. Its Data child is
        // scanned separately so FTS_XDEV and canonical path mapping stay
        // explicit even on unusual APFS configurations.
        if physicalPath == Self.dataVolume, level > 0 {
            return true
        }
        return false
    }

    private func isKnownPackage(_ name: String) -> Bool {
        let packageExtensions: Set<String> = [
            "app", "bundle", "framework", "plugin", "appex",
            "xcodeproj", "xcworkspace", "playground",
            "photoslibrary", "musiclibrary", "imovielibrary"
        ]
        guard let ext = name.split(separator: ".").last else { return false }
        return packageExtensions.contains(ext.lowercased())
    }

    private func modificationDate(_ entry: UnsafeMutablePointer<FTSENT>) -> TimeInterval? {
        guard let stat = entry.pointee.fts_statp else { return nil }
        return TimeInterval(stat.pointee.st_mtimespec.tv_sec)
    }

    private func logicalSize(_ entry: UnsafeMutablePointer<FTSENT>) -> Int64? {
        guard let stat = entry.pointee.fts_statp else { return nil }
        return Int64(stat.pointee.st_size)
    }

    private func entryName(_ entry: UnsafeMutablePointer<FTSENT>) -> String {
        withUnsafePointer(to: &entry.pointee.fts_name) {
            $0.withMemoryRebound(
                to: CChar.self,
                capacity: Int(entry.pointee.fts_namelen) + 1
            ) {
                String(cString: $0)
            }
        }
    }
}
