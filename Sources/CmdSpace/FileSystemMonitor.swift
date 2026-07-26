import CoreServices
import Foundation

struct FileSystemChange: Sendable {
    let path: String
    let flags: FSEventStreamEventFlags
    let eventID: FSEventStreamEventId
}

private func fileSystemEventCallback(
    _ stream: ConstFSEventStreamRef,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ eventCount: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIDs: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let monitor = Unmanaged<FileSystemMonitor>.fromOpaque(clientInfo).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    let changes = paths.prefix(eventCount).enumerated().map { index, path in
        FileSystemChange(
            path: path,
            flags: eventFlags[index],
            eventID: eventIDs[index]
        )
    }
    monitor.receive(changes)
}

final class FileSystemMonitor: @unchecked Sendable {
    typealias Handler = @Sendable ([FileSystemChange]) -> Void

    private let handler: Handler
    private let sinceWhen: FSEventStreamEventId
    private let paths: [String]
    private let queue = DispatchQueue(label: "com.jvanderberg.CmdSpace.filesystem-events")
    private var stream: FSEventStreamRef?
    private var pending: [
        String: (flags: FSEventStreamEventFlags, eventID: FSEventStreamEventId)
    ] = [:]
    private var flushWorkItem: DispatchWorkItem?

    init(
        paths: [String] = ["/"],
        sinceWhen: FSEventStreamEventId = FSEventStreamEventId(
            kFSEventStreamEventIdSinceNow
        ),
        handler: @escaping Handler
    ) {
        self.paths = paths
        self.sinceWhen = sinceWhen
        self.handler = handler
    }

    func start() {
        queue.sync {
            guard stream == nil else { return }
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagWatchRoot
                    | kFSEventStreamCreateFlagNoDefer
            )
            guard let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                fileSystemEventCallback,
                &context,
                paths as CFArray,
                sinceWhen,
                0.35,
                flags
            ) else {
                return
            }
            FSEventStreamSetDispatchQueue(created, queue)
            guard FSEventStreamStart(created) else {
                FSEventStreamInvalidate(created)
                FSEventStreamRelease(created)
                return
            }
            stream = created
        }
    }

    func stop() {
        queue.sync {
            flushWorkItem?.cancel()
            flushWorkItem = nil
            pending.removeAll()
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    fileprivate func receive(_ changes: [FileSystemChange]) {
        for change in changes {
            let existing = pending[change.path]
            pending[change.path] = (
                flags: (existing?.flags ?? 0) | change.flags,
                eventID: max(existing?.eventID ?? 0, change.eventID)
            )
        }
        flushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changes = self.pending.map {
                FileSystemChange(
                    path: $0.key,
                    flags: $0.value.flags,
                    eventID: $0.value.eventID
                )
            }
            self.pending.removeAll()
            self.handler(changes)
        }
        flushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.55, execute: workItem)
    }

    deinit {
        stop()
    }
}
