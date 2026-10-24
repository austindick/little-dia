import Foundation

/// A release version, "1.2.3" or "v1.2.3": three numbers, compared numerically. Anything else isn't a version.
public struct Version: Comparable, Sendable, CustomStringConvertible {
    let parts: [Int]

    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { Int($0) }
        guard pieces.count == 3, numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        parts = numbers
    }

    public static func < (lhs: Version, rhs: Version) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}

/// The parts of GitHub's "latest release" answer the updater uses.
public struct ReleaseInfo: Decodable, Sendable {
    public let tagName: String
    public let assets: [Asset]

    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

/// Where releases come from.
public enum ReleaseSource {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/austindick/little-dia/releases/latest")!
    public static let assetName = "Little-Dia.zip"
}

/// A newer release the app can install.
public struct UpdateOffer: Equatable, Sendable {
    public let version: String
    public let downloadURL: URL

    /// An offer only for a release that is newer than `currentVersion` and carries the app's zip.
    public static func decide(currentVersion: String, release: ReleaseInfo, assetName: String = ReleaseSource.assetName) -> UpdateOffer? {
        guard let latest = Version(release.tagName), let current = Version(currentVersion), latest > current,
              let asset = release.assets.first(where: { $0.name == assetName }) else { return nil }
        return UpdateOffer(version: latest.description, downloadURL: asset.browserDownloadURL)
    }
}

public enum UpdateInstall {
    /// Whether an update may replace the app at `bundleURL`: it must be an installed .app whose folder we can write
    /// to. A build run from elsewhere, or a read-only location, is left alone.
    public static func canReplace(appAt bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        guard bundleURL.pathExtension == "app", fileManager.fileExists(atPath: bundleURL.path) else { return false }
        return fileManager.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)
    }
}
