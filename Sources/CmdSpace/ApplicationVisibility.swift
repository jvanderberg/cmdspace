import Foundation

enum ApplicationVisibility {
    enum Reason: String {
        case embeddedComponent
        case managedPayload
        case incompleteBundle
        case backgroundComponent
        case unknownMetadata
        case launchable

        var isHidden: Bool {
            switch self {
            case .embeddedComponent, .managedPayload, .incompleteBundle, .backgroundComponent: true
            case .unknownMetadata, .launchable: false
            }
        }
    }

    static let ruleVersion = 1

    static func pathReason(_ path: String) -> Reason? {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let components = URL(fileURLWithPath: normalized).pathComponents
        if components.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }) {
            return .embeddedComponent
        }
        let updateRoot = "/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate"
        if normalized.hasPrefix(updateRoot + "/") { return .managedPayload }
        // Match the actual placeholder hierarchy, not arbitrary directory names.
        if let index = components.indices.first(where: { index in
            index + 6 < components.count
                && components[index] == "Library"
                && components[index + 1] == "Daemon Containers"
                && components[index + 3] == "Data"
                && components[index + 4] == "Library"
                && components[index + 5] == "Caches"
                && components[index + 6] == "Placeholders-v2.noindex"
        }), index + 7 < components.count { return .managedPayload }
        return nil
    }

    static func boolean(_ value: Any?) -> Bool {
        if let value = value as? String {
            return ["yes", "true", "1"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return (value as? NSNumber)?.boolValue ?? false
    }

    static func classify(path: String) -> Reason {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if let reason = pathReason(url.path) { return reason }
        let resolved = url.resolvingSymlinksInPath()
        if let reason = pathReason(resolved.path) { return reason }
        let manager = FileManager.default
        // macOS bundles use Contents; flat bundles also exist, including iOS apps.
        let contents = resolved.appendingPathComponent("Contents")
        let root = manager.fileExists(atPath: contents.path) ? contents : resolved
        let plist: [String: Any]
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("Info.plist"))
            guard let dictionary = try PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any] else { return .unknownMetadata }
            plist = dictionary
        } catch { return .unknownMetadata }
        guard let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"),
              executable != ".", executable != ".." else { return .incompleteBundle }
        let binary = (root == contents ? root.appendingPathComponent("MacOS") : root)
            .appendingPathComponent(executable)
        do {
            let attributes = try manager.attributesOfItem(atPath: binary.resolvingSymlinksInPath().path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { return .incompleteBundle }
            if let permissions = attributes[.posixPermissions] as? NSNumber,
               permissions.intValue & 0o111 == 0 { return .incompleteBundle }
        } catch {
            let error = error as NSError
            // Permission and I/O failures are not evidence of an invalid app.
            return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
                ? .incompleteBundle : .unknownMetadata
        }
        let components = resolved.pathComponents
        let inSupport = components.indices.contains { index in
            index + 1 < components.count && components[index] == "Library"
                && components[index + 1] == "Application Support"
        }
        if inSupport && boolean(plist["LSBackgroundOnly"]) { return .backgroundComponent }
        return .launchable
    }
}
