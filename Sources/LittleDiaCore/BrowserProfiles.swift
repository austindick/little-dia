import Foundation

/// The browser's profiles as the title-bar button needs them: the ones with the extension installed (little windows
/// open in one of these) and the others a page can be sent to. Read from the browser's own files, so no permission is
/// needed.
public struct BrowserProfiles: Equatable, Sendable {
    /// The first profile with the extension, used when nothing says which one a little window is in.
    public var current: String
    public var others: [String]
    /// Every profile with the extension, alphabetically.
    public var withExtension: [String]

    public init(current: String, others: [String], withExtension: [String]? = nil) {
        self.current = current
        self.others = others
        self.withExtension = withExtension ?? [current]
    }

    /// Every profile, alphabetically, for the profile menu.
    public var all: [String] { (others + [current]).sorted() }

    /// The profile "Open in" sends a page to: the one the browser's main window is showing, when that's known and is
    /// one of these, else the little window's own. Only the little window's own profile takes the page live; any
    /// other reopens it.
    public func destination(showing active: String?, littleWindowIn own: String?) -> String {
        if let active, all.contains(active) { return active }
        return own ?? current
    }

    /// Reads profile names from Chromium's `Local State`, and finds the extension's profiles by its ID in each
    /// profile's preferences.
    public static func load(userDataDirectory: URL, extensionID: String = ExtensionIdentity.chromiumID) -> BrowserProfiles? {
        guard let names = names(userDataDirectory: userDataDirectory) else { return nil }
        let needle = Data(extensionID.utf8)
        let hasExtension: (String) -> Bool = { folder in
            ["Preferences", "Secure Preferences"].contains { file in
                (try? Data(contentsOf: userDataDirectory.appendingPathComponent(folder).appendingPathComponent(file)))?.range(of: needle) != nil
            }
        }
        let folders = names.keys.sorted().filter(hasExtension)
        guard let folder = folders.first, let current = names[folder] else { return nil }
        return BrowserProfiles(current: current, others: names.filter { $0.key != folder }.map(\.value).sorted(),
                               withExtension: folders.compactMap { names[$0] }.sorted())
    }

    /// The name of the profile whose extension storage holds `token` (the extension writes it there with
    /// `chrome.storage.local`, which Chromium keeps as plain text in the profile's folder).
    public static func profile(holdingToken token: String, userDataDirectory: URL,
                               extensionID: String = ExtensionIdentity.chromiumID) -> String? {
        guard let names = names(userDataDirectory: userDataDirectory), !token.isEmpty else { return nil }
        let needle = Data(token.utf8)
        let files = FileManager.default
        for (folder, name) in names {
            let storage = userDataDirectory.appendingPathComponent(folder).appendingPathComponent("Local Extension Settings")
                .appendingPathComponent(extensionID)
            let contents = (try? files.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)) ?? []
            if contents.contains(where: { (try? Data(contentsOf: $0))?.range(of: needle) != nil }) { return name }
        }
        return nil
    }

    /// Profile names by folder, from Chromium's `Local State`.
    private static func names(userDataDirectory: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: userDataDirectory.appendingPathComponent("Local State")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return nil }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }
}

/// Which profile's extension opens a little window: the one in the profile the browser's main window is showing.
public enum ProfileRouting {
    /// The ready connection running in `profile`, or nil if there's none (or the profile isn't known), in which case
    /// the newest connection is used.
    public static func connection(for profile: String?, ready: [Int], profileOf: [Int: String]) -> Int? {
        guard let profile else { return nil }
        return ready.last { profileOf[$0] == profile }
    }
}

/// AppleScript for Dia. Its dictionary can move tabs between profiles, which the extension API can't.
public enum DiaScript {
    /// Opens `url` as a new tab in `profile`, switches the front window to it and brings Dia forward.
    public static func openInProfile(url: String, profile: String) -> String {
        """
        tell application id "company.thebrowser.dia"
            set w to window 1
            set t to make new tab at end of tabs of (profile \(literal(profile)) of w) with properties {URL:\(literal(url))}
            focus t
            activate
        end tell
        """
    }

    /// The name of the profile Dia's main window is showing. Little windows report the main window's profile too
    /// (seen 2026-10-30), so it doesn't matter which window is in front.
    public static let activeProfileName = """
        tell application id "company.thebrowser.dia" to return name of active profile of window 1
        """

    /// Opens `url` in a new tab of Dia's front window and brings Dia forward (Dia shows chrome:// pages as dia://).
    public static func openTab(url: String) -> String {
        """
        tell application id "company.thebrowser.dia"
            make new tab at end of tabs of window 1 with properties {URL:\(literal(url))}
            activate
        end tell
        """
    }

    static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
