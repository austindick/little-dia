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

    public init(runningToReady: Duration = .seconds(2), openAck: Duration = .seconds(4), visibility: Duration = .seconds(2)) {
        self.runningToReady = runningToReady
        self.openAck = openAck
        self.visibility = visibility
    }
}

public enum FallbackReason: Equatable, Sendable {
    /// The browser wasn't open: links open in its main window until it is (owner decision, 2026-10-23).
    case notRunning
    case disabled, notWebURL, notReady, openFailed, timedOut, notVisible
}

public enum RouteOutcome: Equatable, Sendable {
    case little(windowId: Int)
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
    private let logger = Logger(subsystem: "com.lilbrowwow", category: "router")

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

        let bounds = ScreenGeometry.littleWindowBounds(size: settings.littleWindowSize, on: screen())
        let windowsBefore = Set(browser.onScreenWindows(bundleID: bundleID).map(\.id))
        let request = OpenRequest(requestId: makeRequestID(), url: url, bounds: bounds, focused: true)
        switch await link.open(request, browser: bundleID, timeout: timeouts.openAck) {
        case let .opened(windowId):
            let onScreen = await poll(for: timeouts.visibility) {
                browser.onScreenWindows(bundleID: bundleID).contains {
                    !windowsBefore.contains($0.id) && abs($0.frame.width - CGFloat(bounds.width)) <= 6
                }
            }
            guard onScreen else {
                link.close(windowId: windowId, browser: bundleID)
                return fallback(.notVisible)
            }
            browser.activate(bundleID: bundleID)
            return .little(windowId: windowId)
        case .failed:
            return fallback(.openFailed)
        case .timedOut:
            return fallback(.timedOut)
        }
    }

    /// Checks `condition` every 100ms until it holds or `timeout` passes.
    private func poll(for timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if condition() { return true }
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: min(.milliseconds(100), deadline - clock.now))
        }
    }
}
