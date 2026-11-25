import Foundation

/// The site icons shown in the Recent list: one PNG per site (host), from Dia's own icon store via the extension,
/// cached in a folder on this Mac. Each site is asked for at most once per launch, so a site with no icon isn't asked
/// about every time the box opens.
@MainActor
public final class SiteIcons {
    /// Larger than any real 32px icon; anything bigger isn't one.
    static let maxBytes = 256 * 1024
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private let directory: URL
    private var askedFileNames: Set<String> = []

    public init(directory: URL) {
        self.directory = directory
    }

    /// The cached icon for the page's site, if there is one.
    public func pngData(forPage url: String) -> Data? {
        guard let name = Self.iconFileName(forPage: url) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// The pages to ask the extension about: one per site with no cached icon that hasn't been asked about since
    /// launch (or since `clear`). Call `markAsked` once the request has actually gone out.
    public func toAsk(for entries: [RecentPages.Entry]) -> [String] {
        var pages: [String] = [], names: Set<String> = []
        for entry in entries {
            guard let name = Self.iconFileName(forPage: entry.url), !askedFileNames.contains(name), names.insert(name).inserted,
                  !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) else { continue }
            pages.append(entry.url)
        }
        return pages
    }

    /// These pages' sites have been asked about: they aren't asked again this launch, and their icons are accepted.
    public func markAsked(_ pages: [String]) {
        askedFileNames.formUnion(pages.compactMap(Self.iconFileName(forPage:)))
    }

    /// Saves the icons that are real PNGs of a sensible size, for sites that were asked about (and not cleared since).
    /// True if any was written.
    public func store(_ icons: [String: String]) -> Bool {
        var wrote = false
        for (page, base64) in icons {
            guard let name = Self.iconFileName(forPage: page), askedFileNames.contains(name), let data = Data(base64Encoded: base64),
                  data.count <= Self.maxBytes, data.starts(with: Self.pngSignature) else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if (try? data.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil { wrote = true }
        }
        return wrote
    }

    /// Deletes every cached icon, and asks about every site again.
    public func clear() {
        askedFileNames.removeAll()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" { try? FileManager.default.removeItem(at: file) }
    }

    /// The file a page's site icon lives in: the host, lowercased, with `_port` if it has one. Nil for a page with no
    /// host, or one with characters that don't belong in a host name.
    public nonisolated static func iconFileName(forPage url: String) -> String? {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased(), !host.isEmpty,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              host.contains(where: { $0 != "." }) else { return nil }
        let port = components.port.map { "_\($0)" } ?? ""
        return host + port + ".png"
    }
}
