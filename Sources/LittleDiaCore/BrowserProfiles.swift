import Foundation

/// The browser's profiles as the title-bar button needs them: the one little windows open in (where the extension is
/// installed) and the others a page can be sent to. Read from the browser's own files, so no permission is needed.
public struct BrowserProfiles: Equatable, Sendable {
    public var current: String
    public var others: [String]

    public init(current: String, others: [String]) {
        self.current = current
        self.others = others
    }

    /// Every profile, alphabetically, for the profile menu.
    public var all: [String] { (others + [current]).sorted() }

    /// The profile "Open in" sends a page to: the one the browser's main window is showing, when that's known and is
    /// one of these, else the extension's. Only the extension's takes the page live; any other reopens it.
    public func destination(showing active: String?) -> String {
        guard let active, all.contains(active) else { return current }
        return active
    }

    /// Reads profile names from Chromium's `Local State`, and finds the extension's profile by its ID in each
    /// profile's preferences.
    public static func load(userDataDirectory: URL, extensionID: String = ExtensionIdentity.chromiumID) -> BrowserProfiles? {
        guard let data = try? Data(contentsOf: userDataDirectory.appendingPathComponent("Local State")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return nil }
        let names = cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
        let needle = Data(extensionID.utf8)
        let hasExtension: (String) -> Bool = { folder in
            ["Preferences", "Secure Preferences"].contains { file in
                (try? Data(contentsOf: userDataDirectory.appendingPathComponent(folder).appendingPathComponent(file)))?.range(of: needle) != nil
            }
        }
        guard let folder = names.keys.sorted().first(where: hasExtension), let current = names[folder] else { return nil }
        return BrowserProfiles(current: current, others: names.filter { $0.key != folder }.map(\.value).sorted())
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
