import CoreGraphics
import Foundation
import os

/// The browser app itself, as seen from the router.
@MainActor
public protocol BrowserControl: AnyObject {
    func isRunning(bundleID: String) -> Bool
    /// Opens the URL in the browser app directly (never through the default-browser handler, which is us).
    func openNormally(_ url: URL, bundleID: String)
    /// Brings the browser to the front. Once its new popup is on screen, this keeps you on the current desktop
    /// (see docs/superpowers/spikes/2026-10-23-same-desktop.md, method M3).
    func activate(bundleID: String)
    /// The browser's normal-level windows on the current desktop (top-left coordinates).
    func onScreenWindows(bundleID: String) -> [WindowCandidate<Int>]
}

public struct RouterTimeouts: Sendable {
    public var runningToReady: Duration
    public var openAck: Duration
    /// How long the popup has to reach the screen before the link is opened normally instead. (Dia accepts popups
    /// created while it is still starting up but never shows them.)
    public var visibility: Duration
    /// How often to look for the popup. The browser is brought forward the moment it appears, so this is most of
    /// the time the popup spends drawn behind the current app.
    public var pollInterval: Duration

    public init(runningToReady: Duration = .seconds(2), openAck: Duration = .seconds(4), visibility: Duration = .seconds(2),
                pollInterval: Duration = .milliseconds(15)) {
        self.runningToReady = runningToReady
        self.openAck = openAck
        self.visibility = visibility
        self.pollInterval = pollInterval
    }
}

public enum FallbackReason: Equatable, Sendable {
    /// The browser wasn't open: links open in its main window until it is (owner decision, 2026-10-23).
    case notRunning
    case disabled, notWebURL, notReady, openFailed, timedOut, notVisible
}

public enum RouteOutcome: Equatable, Sendable {
    case little(windowId: Int)
    /// The popup reached the screen but the extension never confirmed it; the link is not opened a second time.
    case littleUnconfirmed
    case openedNormally(FallbackReason)
}

/// Decides what happens to each incoming link. Every failure path opens the link in the browser normally,
/// so a link is never lost.
@MainActor
public final class LinkRouter {
    private let settings: LittleSettings
    private let link: ExtensionLink
    private let browser: BrowserControl
    private let screen: () -> ScreenContext
    private let timeouts: RouterTimeouts
    private let makeRequestID: () -> String
    /// Called with a popup the router gave up on (it never reached the screen in time), so it can be closed natively.
    public var onAbandon: ((Int) -> Void)?
    private let logger = Logger(subsystem: "com.austindick.littledia", category: "router")

    public init(settings: LittleSettings, link: ExtensionLink, browser: BrowserControl, screen: @escaping () -> ScreenContext,
                timeouts: RouterTimeouts = .init(), makeRequestID: @escaping () -> String = { UUID().uuidString }) {
        self.settings = settings
        self.link = link
        self.browser = browser
        self.screen = screen
        self.timeouts = timeouts
        self.makeRequestID = makeRequestID
    }

    public func route(_ url: URL) async -> RouteOutcome {
        let bundleID = settings.browser.bundleID

        func fallback(_ reason: FallbackReason) -> RouteOutcome {
            logger.notice("opening normally (\(String(describing: reason), privacy: .public))")
            browser.openNormally(url, bundleID: bundleID)
            return .openedNormally(reason)
        }

        guard settings.isEnabled else { return fallback(.disabled) }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return fallback(.notWebURL) }

        guard browser.isRunning(bundleID: bundleID) else { return fallback(.notRunning) }
        if !link.isReady(browser: bundleID) {
            guard await link.waitUntilReady(browser: bundleID, timeout: timeouts.runningToReady) else { return fallback(.notReady) }
        }

        let windowsBefore = browser.onScreenWindows(bundleID: bundleID)
        var bounds = ScreenGeometry.littleWindowBounds(size: settings.littleWindowSize, on: screen(),
                                                       chromeHeight: settings.browser.chromeHeight)
        // Don't stack exactly on top of an existing little window: it would hide it and confuse window matching.
        for _ in 0..<10 where matchLittleWindow(windowsBefore, bounds: bounds, excluding: []) != nil {
            bounds = Bounds(left: bounds.left + 30, top: bounds.top + 30, width: bounds.width, height: bounds.height)
        }
        let before = Set(windowsBefore.map(\.id))
        // Dia animates the popup open from slightly narrower than requested, so allow 5%.
        let isTheNewPopup: (WindowCandidate<Int>) -> Bool = {
            !before.contains($0.id) && abs($0.frame.width - CGFloat(bounds.width)) <= CGFloat(bounds.width) * 0.05
        }
        let request = OpenRequest(requestId: makeRequestID(), url: url, bounds: bounds, focused: true)

        // Watch for the popup while the extension is still answering, and bring the browser forward the instant it
        // appears: the popup is drawn behind the current app until then. Once the extension confirms, the popup has
        // `visibility` to reach the screen.
        let ack = AckBox()
        let link = self.link, timeouts = self.timeouts
        let ackTask = Task { @MainActor in
            let result = await link.open(request, browser: bundleID, timeout: timeouts.openAck)
            ack.result = result
            ack.at = ContinuousClock.now
            return result
        }
        var appeared = false
        while true {
            if browser.onScreenWindows(bundleID: bundleID).contains(where: isTheNewPopup) {
                appeared = true
                break
            }
            if let result = ack.result, let at = ack.at {
                guard case .opened = result else { break }                     // the extension said no
                if ContinuousClock.now - at >= timeouts.visibility { break }   // confirmed, but never shown
            }
            try? await Task.sleep(for: timeouts.pollInterval)
        }
        if appeared { browser.activate(bundleID: bundleID) }

        switch await ackTask.value {
        case let .opened(windowId):
            guard appeared else {
                onAbandon?(windowId)
                link.close(windowId: windowId, browser: bundleID)
                return fallback(.notVisible)
            }
            return .little(windowId: windowId)
        case .failed where appeared, .timedOut where appeared:
            return .littleUnconfirmed
        case .failed:
            return fallback(.openFailed)
        case .timedOut:
            return fallback(.timedOut)
        }
    }

    /// Checks `condition` every `interval` until it holds or `timeout` passes.
    private func poll(for timeout: Duration, every interval: Duration = .milliseconds(100), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if condition() { return true }
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: min(interval, deadline - clock.now))
        }
    }
}

@MainActor
private final class AckBox {
    var result: OpenResult?
    var at: ContinuousClock.Instant?
}
