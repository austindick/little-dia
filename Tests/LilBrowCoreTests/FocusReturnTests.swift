import Testing
@testable import LilBrowCore

@MainActor private final class World {
    var browserFrontmost = true
    /// How many more checks the closing window stays on screen (its close animation); nil: stays for good.
    var browserWindowChecksLeft: Int? = 0
    var activated: [String] = []
    lazy var focus = FocusReturn<String>(
        isOwnOrBrowser: { $0 == "Lil Brow Wow" || $0 == "Dia" },
        browserIsFrontmost: { self.browserFrontmost },
        browserHasWindowOnThisDesktop: {
            guard let left = self.browserWindowChecksLeft else { return true }
            self.browserWindowChecksLeft = max(0, left - 1)
            return left > 0
        },
        activate: { self.activated.append($0) },
        settle: .milliseconds(200), pollInterval: .milliseconds(5))
}

@MainActor @Test func closingALittleWindowReturnsFocusToTheAppYouCameFrom() async {
    let w = World()
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    await w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated == ["Slack"])
}

@MainActor @Test func waitsForTheCloseAnimationBeforeDeciding() async {
    let w = World()
    w.browserWindowChecksLeft = 3
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    await w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated == ["Slack"])
}

@MainActor @Test func movingToTheMainWindowKeepsTheBrowserFocused() async {
    let w = World()
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    await w.focus.handle(.littleMoved(windowId: 42))
    await w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated.isEmpty)
}

@MainActor @Test func anotherBrowserWindowOnThisDesktopKeepsFocus() async {
    let w = World()
    w.browserWindowChecksLeft = nil
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    await w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated.isEmpty)
}

@MainActor @Test func doesNotStealFocusIfYouAlreadySwitchedApps() async {
    let w = World()
    w.browserFrontmost = false
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    await w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated.isEmpty)
}

@MainActor @Test func unknownWindowsAreIgnored() async {
    let w = World()
    await w.focus.handle(.littleClosed(windowId: 7))
    #expect(w.activated.isEmpty)
}

@MainActor @Test func originIsTheLastOtherAppWhenThisAppIsFrontmost() {   // macOS activates us when the link arrives
    let w = World()
    w.focus.appActivated("Slack")
    w.focus.appActivated("Lil Brow Wow")
    #expect(w.focus.origin(frontmost: "Lil Brow Wow") == "Slack")
}

@MainActor @Test func originIsTheFrontmostAppWhenItIsSomeoneElse() {
    let w = World()
    w.focus.appActivated("Mail")
    #expect(w.focus.origin(frontmost: "Slack") == "Slack")
    #expect(w.focus.origin(frontmost: "Dia") == "Mail")
}

@MainActor @Test func forgettingAWindowKeepsTheBrowserFocused() async {   // review #6: Move to Dia clicked
    let w = World()
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    w.focus.forget(42)
    await w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated.isEmpty)
}
