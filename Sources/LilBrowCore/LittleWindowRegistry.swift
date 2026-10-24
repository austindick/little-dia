import Foundation

public struct LittleWindowInfo: Equatable, Sendable {
    public var windowId: Int
    public var browserBundleID: String
    /// Exactly as the browser reports it.
    public var url: String
    public var bounds: Bounds

    public init(windowId: Int, browserBundleID: String, url: String, bounds: Bounds) {
        self.windowId = windowId
        self.browserBundleID = browserBundleID
        self.url = url
        self.bounds = bounds
    }
}

/// What the app knows about each open little window, kept current from the extension's events.
public final class LittleWindowRegistry {
    private var windows: [Int: LittleWindowInfo] = [:]

    public init() {}

    public func apply(_ message: InboundMessage, from bundleID: String) {
        switch message {
        case let .opened(_, windowId, url, bounds):
            windows[windowId] = LittleWindowInfo(windowId: windowId, browserBundleID: bundleID, url: url, bounds: bounds)
        case let .littleURL(windowId, url):
            windows[windowId]?.url = url
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
