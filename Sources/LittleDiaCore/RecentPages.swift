import Foundation

/// The pages recently opened in little windows, for the Recent list in the New Little Window box: one entry per little
/// window, for the last page it showed (so a link's redirects and sign-in hops don't crowd the list), newest first.
/// Kept in this app's preferences on this Mac only, until cleared.
@MainActor
public final class RecentPages {
    public struct Entry: Codable, Equatable, Sendable {
        public var url: String
        /// Nil until the page has a title of its own.
        public var title: String?
        /// When the window last showed it.
        public var date: Date

        public init(url: String, title: String?, date: Date) {
            self.url = url
            self.title = title
            self.date = date
        }

        /// The title, or the site when there's none.
        public var displayTitle: String {
            title ?? URL(string: url)?.host ?? url
        }
    }

    public static let limit = 50
    private static let key = "recentPages"

    private let defaults: UserDefaults
    public private(set) var entries: [Entry]
    /// The page each open little window is showing; when it moves on, its entry moves with it.
    private var openWindows: [Int: String] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    /// A little window is showing `url`. `title` is nil when it isn't known (the window has just opened), and "" when
    /// the page has none yet.
    public func note(windowId: Int, url: String, title: String?, now: Date = Date()) {
        guard let scheme = URL(string: url)?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let kept: String?
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) {
            // Dia shows the address as the title while a page loads.
            kept = title.isEmpty || title == url ? nil : title
        } else {
            // Unknown: keep the title this page already has.
            kept = entries.first(where: { $0.url == url })?.title
        }

        if let previous = openWindows[windowId], previous != url,
           !openWindows.contains(where: { $0.key != windowId && $0.value == previous }) {
            entries.removeAll { $0.url == previous }
        }
        entries.removeAll { $0.url == url }
        entries.insert(Entry(url: url, title: kept, date: now), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        openWindows[windowId] = url
        save()
    }

    /// The window's last page stays in the list.
    public func windowClosed(_ windowId: Int) {
        openWindows[windowId] = nil
    }

    /// Entries whose title or address contains `query`, ignoring case; all of them for an empty query.
    public func matching(_ query: String) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.url.localizedCaseInsensitiveContains(query) || ($0.title?.localizedCaseInsensitiveContains(query) ?? false) }
    }

    public func clear() {
        entries = []
        openWindows = [:]
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}
