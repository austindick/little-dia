import Testing
@testable import LilBrowCore

@MainActor private final class World {
    var browserFrontmost = true
    var browserWindowsHere = 0
    var activated: [String] = []
    lazy var focus = FocusReturn<String>(browserIsFrontmost: { self.browserFrontmost },
                                         browserHasWindowOnThisDesktop: { self.browserWindowsHere > 0 },
                                         activate: { self.activated.append($0) })
}

@MainActor @Test func closingALittleWindowReturnsFocusToTheAppYouCameFrom() {
    let w = World()
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated == ["Slack"])
}

@MainActor @Test func movingToTheMainWindowKeepsTheBrowserFocused() {
    let w = World()
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    w.focus.handle(.littleMoved(windowId: 42))
    w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated.isEmpty)
}

@MainActor @Test func anotherBrowserWindowOnThisDesktopKeepsFocus() {
    let w = World()
    w.browserWindowsHere = 1
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated.isEmpty)
}

@MainActor @Test func doesNotStealFocusIfYouAlreadySwitchedApps() {
    let w = World()
    w.browserFrontmost = false
    w.focus.littleWindowOpened(42, cameFrom: "Slack")
    w.focus.handle(.littleClosed(windowId: 42))
    #expect(w.activated.isEmpty)
}

@MainActor @Test func unknownWindowsAreIgnored() {
    let w = World()
    w.focus.handle(.littleClosed(windowId: 7))
    #expect(w.activated.isEmpty)
}
