import Foundation

public struct LittleWindowInfo: Equatable, Sendable {
    public var windowId: Int
    public var browserBundleID: String
    /// The bridge connection (one per browser profile) that opened it, which its Back, Close and Move go to.
    public var connection: Int?
    /// Exactly as the browser reports it.
    public var url: String
    public var bounds: Bounds
    /// Whether its tab has a page to go back to.
    public var canGoBack: Bool

    public init(windowId: Int, browserBundleID: String, connection: Int? = nil, url: String, bounds: Bounds, canGoBack: Bool = false) {
        self.windowId = windowId
        self.browserBundleID = browserBundleID
        self.connection = connection
        self.url = url
        self.bounds = bounds
        self.canGoBack = canGoBack
    }
}

/// What the app knows about each open little window, kept current from the extension's events.
public final class LittleWindowRegistry {
    private var windows: [Int: LittleWindowInfo] = [:]

    public init() {}

    public func apply(_ message: InboundMessage, from bundleID: String, connection: Int? = nil) {
        switch message {
        case let .opened(_, windowId, url, bounds):
            windows[windowId] = LittleWindowInfo(windowId: windowId, browserBundleID: bundleID, connection: connection, url: url, bounds: bounds)
        case let .littleURL(windowId, url):
            windows[windowId]?.url = url
        case let .littleHistory(windowId, canGoBack):
            windows[windowId]?.canGoBack = canGoBack
        case let .littleBounds(windowId, bounds):
            windows[windowId]?.bounds = bounds
        case let .littleClosed(windowId):
            windows.removeValue(forKey: windowId)
        default:
            break
        }
    }

    public func info(for windowId: Int) -> LittleWindowInfo? {
        windows[windowId]
    }
}
