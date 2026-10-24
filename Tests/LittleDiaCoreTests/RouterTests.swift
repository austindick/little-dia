import CoreGraphics
import Foundation
import Testing
@testable import LittleDiaCore

private let github = URL(string: "https://github.com/pulls")!
private let primary = ScreenContext(visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 976), primaryScreenHeight: 1000)
private let fast = RouterTimeouts(runningToReady: .milliseconds(100), openAck: .milliseconds(300), visibility: .milliseconds(200),
                                  pollInterval: .milliseconds(5))

@MainActor private final class FakeSettings: LittleSettings {
    var isEnabled = true
    var littleWindowSize = CGSize(width: 1000, height: 750)
    var browser = BrowserAdapter.dia
}

@MainActor private final class FakeLink: ExtensionLink {
    var ready = true
    var becomesReadyDuringWait = false
    var result = OpenResult.opened(windowId: 42)
    var openCalls: [OpenRequest] = []
    var closeCalls: [Int] = []
    /// Dia at cold start: the extension reports success but no window ever reaches the screen.
    var opensPhantomWindow = false
    /// Width of the window as it first appears (Dia animates it open slightly narrower).
    var appearingWidthDelta = 0
    /// How long the extension takes to confirm after the window is on screen.
    var ackDelay: Duration = .zero
    /// The window reaches the screen this long after the request (nil: right away).
    var windowDelay: Duration?
    weak var screen: FakeBrowser?

    func isReady(browser: String) -> Bool { ready }
    func waitUntilReady(browser: String, timeout: Duration) async -> Bool {
        if ready { return true }
        try? await Task.sleep(for: .milliseconds(20))
        if becomesReadyDuringWait { ready = true }
        return ready
    }
    func open(_ request: OpenRequest, browser: String, timeout: Duration) async -> OpenResult {
        openCalls.append(request)
        screen?.calls.append("open")
        if !opensPhantomWindow {
            let window = WindowCandidate(id: 500 + openCalls.count, frame: CGRect(x: CGFloat(request.bounds.left), y: CGFloat(request.bounds.top - 72), width: CGFloat(request.bounds.width - appearingWidthDelta), height: CGFloat(request.bounds.height + 72)))
            if let windowDelay {
                Task { @MainActor [weak screen] in
                    try? await Task.sleep(for: windowDelay)
                    screen?.onScreen.append(window)
                }
            } else {
                screen?.onScreen.append(window)
            }
        }
        if ackDelay > .zero { try? await Task.sleep(for: ackDelay) }
        screen?.calls.append("ack")
        return result
    }
    func close(windowId: Int, browser: String) { closeCalls.append(windowId) }
}

@MainActor private final class FakeBrowser: BrowserControl {
    var running = true
    var openNormallyCalls: [URL] = []
    var activateCalls: [String] = []
    var calls: [String] = []
    /// On-screen windows on the current desktop; starts with the user's own main window.
    var onScreen = [WindowCandidate(id: 1, frame: CGRect(x: 0, y: 33, width: 1728, height: 1028))]

    func isRunning(bundleID: String) -> Bool { running }
    func openNormally(_ url: URL, bundleID: String) { openNormallyCalls.append(url) }
    func activate(bundleID: String) { activateCalls.append(bundleID); calls.append("activate") }
    func onScreenWindows(bundleID: String) -> [WindowCandidate<Int>] { onScreen }
}

private var abandoned: [Int] = []

@MainActor private func makeRouter() -> (LinkRouter, FakeSettings, FakeLink, FakeBrowser) {
    let settings = FakeSettings(), link = FakeLink(), browser = FakeBrowser()
    link.screen = browser
    let router = LinkRouter(settings: settings, link: link, browser: browser, screen: { primary },
                            timeouts: fast, makeRequestID: { "r1" })
    router.onAbandon = { abandoned.append($0) }
    return (router, settings, link, browser)
}

@MainActor @Test func disabledOpensNormally() async {
    let (router, settings, link, browser) = makeRouter()
    settings.isEnabled = false
    #expect(await router.route(github) == .openedNormally(.disabled))
    #expect(link.openCalls.isEmpty)
    #expect(browser.openNormallyCalls == [github])
}

@MainActor @Test func fileURLOpensNormally() async {
    let (router, _, _, browser) = makeRouter()
    #expect(await router.route(URL(fileURLWithPath: "/tmp/page.html")) == .openedNormally(.notWebURL))
    #expect(browser.openNormallyCalls.count == 1)
}

@MainActor @Test func readyBrowserOpensLittleAndActivatesIt() async {
    let (router, _, link, browser) = makeRouter()
    #expect(await router.route(github) == .little(windowId: 42))
    #expect(link.openCalls == [OpenRequest(requestId: "r1", url: github, bounds: Bounds(left: 300, top: 173, width: 1000, height: 750), focused: true)])
    #expect(browser.activateCalls == ["company.thebrowser.dia"])
    #expect(browser.openNormallyCalls.isEmpty)
}

@MainActor @Test func notRunningOpensNormallyInMainWindow() async {   // owner decision 2026-10-23
    let (router, _, link, browser) = makeRouter()
    browser.running = false
    #expect(await router.route(github) == .openedNormally(.notRunning))
    #expect(link.openCalls.isEmpty)
    #expect(browser.openNormallyCalls == [github])
}

@MainActor @Test func neverReadyFallsBack() async {
    let (router, _, link, browser) = makeRouter()
    link.ready = false
    #expect(await router.route(github) == .openedNormally(.notReady))
    #expect(browser.openNormallyCalls == [github])
    #expect(browser.activateCalls.isEmpty)
}

@MainActor @Test func runningNotReadyBecomesReadyDuringWait() async {   // Review Focus 1
    let (router, _, link, _) = makeRouter()
    link.ready = false
    link.becomesReadyDuringWait = true
    #expect(await router.route(github) == .little(windowId: 42))
}

@MainActor @Test func ackTimeoutFallsBack() async {
    let (router, _, link, browser) = makeRouter()
    link.result = .timedOut
    link.opensPhantomWindow = true   // nothing reached the screen either
    #expect(await router.route(github) == .openedNormally(.timedOut))
    #expect(browser.openNormallyCalls == [github])
    #expect(browser.activateCalls.isEmpty)
}

@MainActor @Test func openFailedFallsBack() async {
    let (router, _, link, browser) = makeRouter()
    link.result = .failed("boom")
    link.opensPhantomWindow = true   // nothing reached the screen either
    #expect(await router.route(github) == .openedNormally(.openFailed))
    #expect(browser.openNormallyCalls == [github])
}

@MainActor @Test func phantomWindowFallsBackAndClosesIt() async {   // Dia cold start: "opened" but never on screen
    let (router, _, link, browser) = makeRouter()
    link.opensPhantomWindow = true
    abandoned = []
    #expect(await router.route(github) == .openedNormally(.notVisible))
    #expect(link.closeCalls == [42])
    #expect(abandoned == [42])
    #expect(browser.openNormallyCalls == [github])
    #expect(browser.activateCalls.isEmpty)
}

@MainActor @Test func activatesAsSoonAsTheWindowAppearsWithoutWaitingForTheAck() async {
    let (router, _, link, browser) = makeRouter()
    link.ackDelay = .milliseconds(100)
    #expect(await router.route(github) == .little(windowId: 42))
    #expect(browser.calls == ["open", "activate", "ack"])
}

@MainActor @Test func countsAWindowStillAnimatingOpen() async {   // Dia's popup starts ~16pt narrower
    let (router, _, link, browser) = makeRouter()
    link.appearingWidthDelta = 16
    #expect(await router.route(github) == .little(windowId: 42))
    #expect(browser.activateCalls == ["company.thebrowser.dia"])
}

@MainActor @Test func theVisibilityClockStartsWhenTheExtensionConfirms() async {   // review #4
    let (router, _, link, _) = makeRouter()
    link.ackDelay = .milliseconds(250)
    link.windowDelay = .milliseconds(300)   // 50ms after the confirmation; visibility allows 200ms from then
    #expect(await router.route(github) == .little(windowId: 42))
}

@MainActor @Test func aPopupThatAppearsWithoutConfirmationIsNotOpenedTwice() async {   // review #4
    let (router, _, link, browser) = makeRouter()
    link.result = .timedOut
    #expect(await router.route(github) == .littleUnconfirmed)
    #expect(browser.openNormallyCalls.isEmpty)
    #expect(browser.activateCalls == ["company.thebrowser.dia"])
}

@MainActor @Test func cascadesWhenALittleWindowAlreadySitsThere() async {   // review #3
    let (router, _, link, browser) = makeRouter()
    browser.onScreen.append(WindowCandidate(id: 7, frame: CGRect(x: 300, y: 101, width: 1000, height: 822)))
    _ = await router.route(github)
    #expect(link.openCalls.first?.bounds == Bounds(left: 330, top: 203, width: 1000, height: 750))
}
