import Foundation

public struct OpenRequest: Equatable, Sendable {
    public var requestId: String
    public var url: URL
    public var bounds: Bounds
    public var focused: Bool
    public var chromeHeight: Int

    public init(requestId: String, url: URL, bounds: Bounds, focused: Bool, chromeHeight: Int) {
        self.requestId = requestId
        self.url = url
        self.bounds = bounds
        self.focused = focused
        self.chromeHeight = chromeHeight
    }
}

public enum OpenResult: Equatable, Sendable {
    case opened(windowId: Int)
    case failed(String)
    case timedOut
}

/// What the router needs from the extension side.
@MainActor
public protocol ExtensionLink: AnyObject {
    func isReady(browser: String) -> Bool
    func waitUntilReady(browser: String, timeout: Duration) async -> Bool
    func open(_ request: OpenRequest, browser: String, timeout: Duration) async -> OpenResult
    func close(windowId: Int, browser: String)
}

/// `ExtensionLink` over the bridge socket: sends `open`, then waits for the matching `opened` / `openFailed`.
@MainActor
public final class BridgeExtensionLink: ExtensionLink, BridgeServerDelegate {
    /// Every message from the extension, after pending requests have been resolved, with the connection it came on.
    public var onEvent: ((InboundMessage, String, Int) -> Void)?
    /// Picks which of the ready connections (oldest first) opens a little window; nil, or a nil answer, means the newest.
    public var chooseConnection: (([Int]) -> Int?)?
    public var onConnectionsChanged: (() -> Void)?

    private let server: BridgeServer
    /// Opens awaiting the extension's answer, with the connection each was sent on.
    private var pendingOpens: [String: (continuation: CheckedContinuation<OpenResult, Never>, connection: Int)] = [:]
    private var readyWaiters: [UUID: (browser: String, continuation: CheckedContinuation<Bool, Never>)] = [:]

    public init(server: BridgeServer) {
        self.server = server
        server.delegate = self
    }

    public func isReady(browser: String) -> Bool {
        server.isReady(browser: browser)
    }

    public func waitUntilReady(browser: String, timeout: Duration) async -> Bool {
        if isReady(browser: browser) { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            readyWaiters[id] = (browser, continuation)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.readyWaiters.removeValue(forKey: id)?.continuation.resume(returning: false)
            }
        }
    }

    public func open(_ request: OpenRequest, browser: String, timeout: Duration) async -> OpenResult {
        let message = OutboundMessage.open(requestId: request.requestId, url: request.url, bounds: request.bounds,
                                           focused: request.focused, chromeHeight: request.chromeHeight)
        let connection: Int
        if let chosen = chooseConnection?(server.readyConnections(for: browser)), server.send(message, toConnection: chosen) {
            connection = chosen
        } else if let newest = server.send(message, to: browser) {
            connection = newest
        } else {
            return .failed("extension not connected")
        }
        return await withCheckedContinuation { continuation in
            pendingOpens[request.requestId] = (continuation, connection)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.pendingOpens.removeValue(forKey: request.requestId)?.continuation.resume(returning: .timedOut)
            }
        }
    }

    public func close(windowId: Int, browser: String) {
        server.send(.close(windowId: windowId), to: browser)
    }

    public func bridge(_ server: BridgeServer, didReceive message: InboundMessage, fromBrowser bundleID: String, connection: Int) {
        switch message {
        case let .opened(requestId?, windowId, _, _):
            pendingOpens.removeValue(forKey: requestId)?.continuation.resume(returning: .opened(windowId: windowId))
        case let .openFailed(requestId, error):
            pendingOpens.removeValue(forKey: requestId)?.continuation.resume(returning: .failed(error))
        default:
            break
        }
        onEvent?(message, bundleID, connection)
    }

    public func bridge(_ server: BridgeServer, connectionClosed id: Int) {
        for (requestId, pending) in pendingOpens where pending.connection == id {
            pendingOpens.removeValue(forKey: requestId)
            pending.continuation.resume(returning: .failed("connection lost"))
        }
    }

    public func bridgeConnectionsChanged(_ server: BridgeServer) {
        for (id, waiter) in readyWaiters where server.isReady(browser: waiter.browser) {
            readyWaiters.removeValue(forKey: id)?.continuation.resume(returning: true)
        }
        onConnectionsChanged?()
    }
}
