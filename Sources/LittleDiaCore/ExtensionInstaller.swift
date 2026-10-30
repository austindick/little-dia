import Foundation

/// The extension ships inside the app. Dia loads it unpacked from a stable folder outside the app (so it survives app
/// updates); this keeps that folder in step with the bundled copy.
public enum ExtensionInstaller {
    public enum InstallError: Error, Equatable {
        case unreadable(String)
    }

    /// The `version` from the extension's manifest.json, or nil if there is no readable manifest.
    public static func version(ofExtensionAt folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    /// Copies `bundled` over `installed` when it's missing or a different version. The copy is staged next to
    /// `installed` and swapped in, so a failure leaves the old copy untouched. Returns whether it copied.
    @discardableResult
    public static func installIfNeeded(bundled: URL, installed: URL, fileManager: FileManager = .default) throws -> Bool {
        guard let bundledVersion = version(ofExtensionAt: bundled) else { throw InstallError.unreadable(bundled.path) }
        if version(ofExtensionAt: installed) == bundledVersion { return false }
        let parent = installed.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".\(installed.lastPathComponent)-\(UUID().uuidString)")
        try fileManager.copyItem(at: bundled, to: staging)
        do {
            if fileManager.fileExists(atPath: installed.path) {
                _ = try fileManager.replaceItemAt(installed, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: installed)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        return true
    }

    public static func needsReload(connectedVersion: String, bundledVersion: String) -> Bool {
        connectedVersion != bundledVersion
    }
}

/// Asks the running extension to reload at most once per bundled version. If Dia loaded the extension from some
/// other folder, a reload can't change its version, and asking again would reload it forever.
public struct ExtensionReloadPolicy: Sendable {
    private var asked: [String: Int] = [:]

    public init() {}

    /// At most `copies` times per version: once for each browser profile the extension is in. A copy that Dia loads
    /// from another folder comes back with its old version, and isn't asked again and again.
    public mutating func shouldReload(connectedVersion: String, bundledVersion: String, copies: Int = 1) -> Bool {
        guard ExtensionInstaller.needsReload(connectedVersion: connectedVersion, bundledVersion: bundledVersion),
              asked[bundledVersion, default: 0] < max(copies, 1) else { return false }
        asked[bundledVersion, default: 0] += 1
        return true
    }
}
