import Darwin
import Foundation

actor DriveIndexer {
    typealias ProgressHandler = @Sendable (IndexProgress) -> Void

    private static let dataVolume = "/System/Volumes/Data"
    private let database: SearchDatabase
    private var running = false

    init(database: SearchDatabase) {
        self.database = database
    }

    /// Index the sealed system volume and writable Data volume separately.
    /// FTS_XDEV keeps the root scan from following APFS firmlinks into Data;
    /// Data paths are stored in their familiar `/Users`, `/Applications`, …
    /// spelling so results open naturally and are never duplicated.
    func refresh(progress: @escaping ProgressHandler) async {
        guard !running else { return }
        running = true
        defer { running = false }

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
