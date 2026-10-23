import Foundation
import os

/// The browser app itself, as seen from the router.
@MainActor
public protocol BrowserControl: AnyObject {
    func isRunning(bundleID: String) -> Bool
    func launchInBackground(bundleID: String) async -> Bool
    /// Opens the URL in the browser app directly (never through the default-browser handler, which is us).
    func openNormally(_ url: URL, bundleID: String)
    /// Brings the browser to the front. Once its new popup exists, this keeps you on the current desktop
    /// (see docs/superpowers/spikes/2026-10-23-same-desktop.md, method M3).
    func activate(bundleID: String)
}

public struct RouterTimeouts: Sendable {
    public var launchToReady: Duration
    public var runningToReady: Duration
    public var openAck: Duration
    /// Pause between the extension confirming the popup and activating the browser, so the window is on screen first.
    public var activationDelay: Duration

    public init(launchToReady: Duration = .seconds(10), runningToReady: Duration = .seconds(2),
                openAck: Duration = .seconds(4), activationDelay: Duration = .milliseconds(150)) {
        self.launchToReady = launchToReady
        self.runningToReady = runningToReady
        self.openAck = openAck
        self.activationDelay = activationDelay
    }
}

public enum FallbackReason: Equatable, Sendable {
    case disabled, notWebURL, launchFailed, notReady, openFailed, timedOut
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

        if !browser.isRunning(bundleID: bundleID) {
            guard await browser.launchInBackground(bundleID: bundleID) else { return fallback(.launchFailed) }
            guard await link.waitUntilReady(browser: bundleID, timeout: timeouts.launchToReady) else { return fallback(.notReady) }
        } else if !link.isReady(browser: bundleID) {
            guard await link.waitUntilReady(browser: bundleID, timeout: timeouts.runningToReady) else { return fallback(.notReady) }
        }

        let bounds = ScreenGeometry.littleWindowBounds(size: settings.littleWindowSize, on: screen())
        let request = OpenRequest(requestId: makeRequestID(), url: url, bounds: bounds, focused: true)
        switch await link.open(request, browser: bundleID, timeout: timeouts.openAck) {
        case let .opened(windowId):
            if timeouts.activationDelay > .zero {
                try? await Task.sleep(for: timeouts.activationDelay)
            }
            browser.activate(bundleID: bundleID)
            return .little(windowId: windowId)
        case .failed:
            return fallback(.openFailed)
        case .timedOut:
            return fallback(.timedOut)
        }
    }
}
