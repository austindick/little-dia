import Foundation

/// The JSON file that tells a Chromium browser where the `lilbrow-host` helper lives and which extension may use it.
public enum NativeHostManifest {
    public static var fileName: String { "\(ExtensionIdentity.nativeHostName).json" }

    public static func json(hostExecutablePath: String) throws -> Data {
        let manifest: [String: Any] = [
            "name": ExtensionIdentity.nativeHostName,
            "description": "Lil Brow Wow bridge",
            "path": hostExecutablePath,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(ExtensionIdentity.chromiumID)/"],
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Writes the manifest into every native-messaging folder the adapter lists and returns the files written.
    @discardableResult
    public static func install(hostExecutablePath: String, adapter: BrowserAdapter, applicationSupport: URL) throws -> [URL] {
        let data = try json(hostExecutablePath: hostExecutablePath)
        return try adapter.nativeHostDirectories.map { relative in
            let folder = applicationSupport.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(fileName)
            try data.write(to: file, options: .atomic)
            return file
        }
    }
}
