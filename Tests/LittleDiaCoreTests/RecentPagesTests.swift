import Foundation
import Testing
@testable import LittleDiaCore

@MainActor private func freshDefaults() -> UserDefaults {
    let suite = "ld-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor @Test func aWindowKeepsOnlyTheLastPageItShowed() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://t.co/abc", title: nil, now: t0)
    recent.note(windowId: 1, url: "https://linear.app/team/issue/ABC-12", title: "", now: t0 + 1)
    recent.note(windowId: 1, url: "https://linear.app/team/issue/ABC-12", title: "ABC-12 Fix login", now: t0 + 2)
    #expect(recent.entries == [RecentPages.Entry(url: "https://linear.app/team/issue/ABC-12", title: "ABC-12 Fix login", date: t0 + 2)])
}

@MainActor @Test func eachWindowHasItsOwnEntryNewestFirst() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://a.example/", title: "A", now: t0)
    recent.note(windowId: 2, url: "https://b.example/", title: "B", now: t0 + 1)
    recent.note(windowId: 1, url: "https://a.example/2", title: "A2", now: t0 + 2)
    #expect(recent.entries.map(\.url) == ["https://a.example/2", "https://b.example/"])
}

@MainActor @Test func aClosedWindowsPageStaysAndALaterWindowAddsItsOwn() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://a.example/", title: "A", now: t0)
    recent.windowClosed(1)
    // Dia can reuse a window id after a restart; it's a new window, not the old one navigating.
    recent.note(windowId: 1, url: "https://b.example/", title: "B", now: t0 + 1)
    #expect(recent.entries.map(\.url) == ["https://b.example/", "https://a.example/"])
}

@MainActor @Test func theSamePageOpenedAgainMovesToTheTop() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://a.example/", title: "A", now: t0)
    recent.windowClosed(1)
    recent.note(windowId: 2, url: "https://b.example/", title: "B", now: t0 + 1)
    recent.windowClosed(2)
    recent.note(windowId: 3, url: "https://a.example/", title: "A", now: t0 + 2)
    #expect(recent.entries.map(\.url) == ["https://a.example/", "https://b.example/"])
}

@MainActor @Test func leavingAPageAnotherOpenWindowShowsKeepsIt() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://a.example/", title: "A", now: t0)
    recent.note(windowId: 2, url: "https://a.example/", title: "A", now: t0 + 1)
    recent.note(windowId: 1, url: "https://b.example/", title: "B", now: t0 + 2)
    #expect(recent.entries.map(\.url) == ["https://b.example/", "https://a.example/"])
}

@MainActor @Test func onlyWebPagesAreKept() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://a.example/", title: "A", now: t0)
    for url in ["about:blank", "chrome://extensions", "file:///etc/hosts", "javascript:void(0)"] {
        recent.note(windowId: 1, url: url, title: nil, now: t0 + 1)
    }
    #expect(recent.entries.map(\.url) == ["https://a.example/"])
}

@MainActor @Test func aTitleThatIsJustTheAddressIsNoTitle() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://a.example/x", title: "https://a.example/x", now: t0)
    #expect(recent.entries.first?.title == nil)
    #expect(recent.entries.first?.displayTitle == "a.example")
    // A later update without a title (an older extension) keeps the one it had.
    recent.note(windowId: 1, url: "https://a.example/x", title: "Page X", now: t0 + 1)
    recent.note(windowId: 1, url: "https://a.example/x", title: nil, now: t0 + 2)
    #expect(recent.entries.first?.title == "Page X")
}

@MainActor @Test func keepsAtMostFiftyPages() {
    let recent = RecentPages(defaults: freshDefaults())
    for i in 0..<60 { recent.note(windowId: i, url: "https://a.example/\(i)", title: nil, now: t0 + Double(i)) }
    #expect(recent.entries.count == RecentPages.limit)
    #expect(recent.entries.first?.url == "https://a.example/59")
    #expect(recent.entries.last?.url == "https://a.example/10")
}

@MainActor @Test func pagesAreRememberedAcrossLaunchesUntilCleared() {
    let defaults = freshDefaults()
    RecentPages(defaults: defaults).note(windowId: 1, url: "https://a.example/", title: "A", now: t0)
    let later = RecentPages(defaults: defaults)
    #expect(later.entries == [RecentPages.Entry(url: "https://a.example/", title: "A", date: t0)])
    later.clear()
    #expect(later.entries.isEmpty)
    #expect(RecentPages(defaults: defaults).entries.isEmpty)
}

@MainActor @Test func filtersByTitleOrAddressIgnoringCase() {
    let recent = RecentPages(defaults: freshDefaults())
    recent.note(windowId: 1, url: "https://docs.google.com/document/d/1", title: "Q3 Roadmap", now: t0)
    recent.note(windowId: 2, url: "https://linear.app/team/issue/ABC-12", title: "Fix login", now: t0 + 1)
    #expect(recent.matching("roadmap").map(\.title) == ["Q3 Roadmap"])
    #expect(recent.matching("LINEAR").map(\.title) == ["Fix login"])
    #expect(recent.matching("  ").count == 2)
    #expect(recent.matching("nothing here").isEmpty)
}
