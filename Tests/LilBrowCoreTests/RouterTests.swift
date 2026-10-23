import CoreGraphics
import Foundation
import Testing
@testable import LilBrowCore

private let github = URL(string: "https://github.com/pulls")!
private let primary = ScreenContext(visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 976), primaryScreenHeight: 1000)
private let fast = RouterTimeouts(launchToReady: .milliseconds(200), runningToReady: .milliseconds(100),
                                  openAck: .milliseconds(100), activationDelay: .zero)

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

    func isReady(browser: String) -> Bool { ready }
    func waitUntilReady(browser: String, timeout: Duration) async -> Bool {
        if ready { return true }
        try? await Task.sleep(for: .milliseconds(20))
        if becomesReadyDuringWait { ready = true }
        return ready
    }
    func open(_ request: OpenRequest, browser: String, timeout: Duration) async -> OpenResult {
        openCalls.append(request)
        return result
    }
}

@MainActor private final class FakeBrowser: BrowserControl {
    var running = true
    var launchSucceeds = true
    var launchCalls = 0
    var openNormallyCalls: [URL] = []
    var activateCalls: [String] = []

    func isRunning(bundleID: String) -> Bool { running }
    func launchInBackground(bundleID: String) async -> Bool { launchCalls += 1; return launchSucceeds }
    func openNormally(_ url: URL, bundleID: String) { openNormallyCalls.append(url) }
    func activate(bundleID: String) { activateCalls.append(bundleID) }
}

@MainActor private func makeRouter() -> (LinkRouter, FakeSettings, FakeLink, FakeBrowser) {
    let settings = FakeSettings(), link = FakeLink(), browser = FakeBrowser()
    let router = LinkRouter(settings: settings, link: link, browser: browser, screen: { primary },
                            timeouts: fast, makeRequestID: { "r1" })
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
    #expect(link.openCalls == [OpenRequest(requestId: "r1", url: github, bounds: Bounds(left: 300, top: 137, width: 1000, height: 750), focused: true)])
    #expect(browser.activateCalls == ["company.thebrowser.dia"])
    #expect(browser.openNormallyCalls.isEmpty)
}

@MainActor @Test func notRunningLaunchesThenOpens() async {
    let (router, _, link, browser) = makeRouter()
    browser.running = false
    link.ready = false
    link.becomesReadyDuringWait = true
    #expect(await router.route(github) == .little(windowId: 42))
    #expect(browser.launchCalls == 1)
}

@MainActor @Test func launchFailureFallsBack() async {
    let (router, _, link, browser) = makeRouter()
    browser.running = false
    browser.launchSucceeds = false
    link.ready = false
    #expect(await router.route(github) == .openedNormally(.launchFailed))
    #expect(browser.openNormallyCalls == [github])
}

@MainActor @Test func neverReadyFallsBack() async {
    let (router, _, link, browser) = makeRouter()
    browser.running = false
    link.ready = false
    #expect(await router.route(github) == .openedNormally(.notReady))
    #expect(browser.openNormallyCalls == [github])
    #expect(browser.activateCalls.isEmpty)
}

@MainActor @Test func runningNotReadyBecomesReadyDuringWait() async {   // Review Focus 1
    let (router, _, link, browser) = makeRouter()
    link.ready = false
    link.becomesReadyDuringWait = true
    #expect(await router.route(github) == .little(windowId: 42))
    #expect(browser.launchCalls == 0)
}

@MainActor @Test func ackTimeoutFallsBack() async {
    let (router, _, link, browser) = makeRouter()
    link.result = .timedOut
    #expect(await router.route(github) == .openedNormally(.timedOut))
    #expect(browser.openNormallyCalls == [github])
    #expect(browser.activateCalls.isEmpty)
}

@MainActor @Test func openFailedFallsBack() async {
    let (router, _, link, browser) = makeRouter()
    link.result = .failed("boom")
    #expect(await router.route(github) == .openedNormally(.openFailed))
    #expect(browser.openNormallyCalls == [github])
}
