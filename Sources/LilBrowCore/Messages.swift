import Foundation

/// A window rectangle in Chromium screen coordinates (points, top-left origin of the primary display).
public struct Bounds: Codable, Equatable, Sendable {
    public var left: Int
    public var top: Int
    public var width: Int
    public var height: Int

    public init(left: Int, top: Int, width: Int, height: Int) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}

/// Messages the app sends to the extension.
public enum OutboundMessage: Equatable, Sendable {
    case open(requestId: String, url: URL, bounds: Bounds, focused: Bool)
    case move(windowId: Int)
    /// Closes a little window the app gave up on (it never reached the screen).
    case close(windowId: Int)
}

/// Messages the app receives on the bridge socket: the helper's `hostHello`, then everything the extension sends.
/// URLs are kept exactly as the browser wrote them (not parsed into `URL`, which re-encodes characters like `|` and
/// `[ ]`), so Copy puts the browser's own URL on the clipboard.
public enum InboundMessage: Equatable, Sendable {
    case hostHello(browserBundleID: String, browserPID: Int32)
    case hello(extensionVersion: String)
    case opened(requestId: String?, windowId: Int, url: String, bounds: Bounds)
    case openFailed(requestId: String, error: String)
    case littleURL(windowId: Int, url: String)
    case littleBounds(windowId: Int, bounds: Bounds)
    case littleClosed(windowId: Int)
    /// Sent just before a little window is closed because its page moved to the main window.
    case littleMoved(windowId: Int)
    case copy(url: String)
    /// A diagnostic line from the extension (its own console isn't reachable in Dia).
    case log(message: String)
}

/// JSON wire format: an object whose `"type"` is the case name and whose other keys are the case's labels.
public enum MessageCoding {
    public static func encode(_ message: OutboundMessage) throws -> Data { try encoder.encode(message) }
    public static func encode(_ message: InboundMessage) throws -> Data { try encoder.encode(message) }
    public static func decodeInbound(_ data: Data) throws -> InboundMessage { try JSONDecoder().decode(InboundMessage.self, from: data) }
    public static func decodeOutbound(_ data: Data) throws -> OutboundMessage { try JSONDecoder().decode(OutboundMessage.self, from: data) }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

private enum Key: String, CodingKey {
    case type, requestId, url, bounds, focused, windowId, browserBundleID, browserPID, extensionVersion, error, message
}

private extension KeyedDecodingContainer where Key == LilBrowCore.Key {
    func decodeURL(_ key: Key) throws -> URL {
        let string = try decode(String.self, forKey: key)
        guard let url = URL(string: string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid URL: \(string)")
        }
        return url
    }
}

extension OutboundMessage: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "open":
            self = .open(requestId: try c.decode(String.self, forKey: .requestId), url: try c.decodeURL(.url),
                         bounds: try c.decode(Bounds.self, forKey: .bounds), focused: try c.decode(Bool.self, forKey: .focused))
        case "move":
            self = .move(windowId: try c.decode(Int.self, forKey: .windowId))
        case "close":
            self = .close(windowId: try c.decode(Int.self, forKey: .windowId))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown outbound type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .open(requestId, url, bounds, focused):
            try c.encode("open", forKey: .type)
            try c.encode(requestId, forKey: .requestId)
            try c.encode(url.absoluteString, forKey: .url)
            try c.encode(bounds, forKey: .bounds)
            try c.encode(focused, forKey: .focused)
        case let .move(windowId):
            try c.encode("move", forKey: .type)
            try c.encode(windowId, forKey: .windowId)
        case let .close(windowId):
            try c.encode("close", forKey: .type)
            try c.encode(windowId, forKey: .windowId)
        }
    }
}

extension InboundMessage: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hostHello":
            self = .hostHello(browserBundleID: try c.decode(String.self, forKey: .browserBundleID),
                              browserPID: try c.decode(Int32.self, forKey: .browserPID))
        case "hello":
            self = .hello(extensionVersion: try c.decode(String.self, forKey: .extensionVersion))
        case "opened":
            self = .opened(requestId: try c.decodeIfPresent(String.self, forKey: .requestId),
                           windowId: try c.decode(Int.self, forKey: .windowId), url: try c.decode(String.self, forKey: .url),
                           bounds: try c.decode(Bounds.self, forKey: .bounds))
        case "openFailed":
            self = .openFailed(requestId: try c.decode(String.self, forKey: .requestId), error: try c.decode(String.self, forKey: .error))
        case "littleURL":
            self = .littleURL(windowId: try c.decode(Int.self, forKey: .windowId), url: try c.decode(String.self, forKey: .url))
        case "littleBounds":
            self = .littleBounds(windowId: try c.decode(Int.self, forKey: .windowId), bounds: try c.decode(Bounds.self, forKey: .bounds))
        case "littleClosed":
            self = .littleClosed(windowId: try c.decode(Int.self, forKey: .windowId))
        case "littleMoved":
            self = .littleMoved(windowId: try c.decode(Int.self, forKey: .windowId))
        case "copy":
            self = .copy(url: try c.decode(String.self, forKey: .url))
        case "log":
            self = .log(message: try c.decode(String.self, forKey: .message))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown inbound type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .hostHello(browserBundleID, browserPID):
            try c.encode("hostHello", forKey: .type)
            try c.encode(browserBundleID, forKey: .browserBundleID)
            try c.encode(browserPID, forKey: .browserPID)
        case let .hello(extensionVersion):
            try c.encode("hello", forKey: .type)
            try c.encode(extensionVersion, forKey: .extensionVersion)
        case let .opened(requestId, windowId, url, bounds):
            try c.encode("opened", forKey: .type)
            try c.encodeIfPresent(requestId, forKey: .requestId)
            try c.encode(windowId, forKey: .windowId)
            try c.encode(url, forKey: .url)
            try c.encode(bounds, forKey: .bounds)
        case let .openFailed(requestId, error):
            try c.encode("openFailed", forKey: .type)
            try c.encode(requestId, forKey: .requestId)
            try c.encode(error, forKey: .error)
        case let .littleURL(windowId, url):
            try c.encode("littleURL", forKey: .type)
            try c.encode(windowId, forKey: .windowId)
            try c.encode(url, forKey: .url)
        case let .littleBounds(windowId, bounds):
            try c.encode("littleBounds", forKey: .type)
            try c.encode(windowId, forKey: .windowId)
            try c.encode(bounds, forKey: .bounds)
        case let .littleClosed(windowId):
            try c.encode("littleClosed", forKey: .type)
            try c.encode(windowId, forKey: .windowId)
        case let .littleMoved(windowId):
            try c.encode("littleMoved", forKey: .type)
            try c.encode(windowId, forKey: .windowId)
        case let .copy(url):
            try c.encode("copy", forKey: .type)
            try c.encode(url, forKey: .url)
        case let .log(message):
            try c.encode("log", forKey: .type)
            try c.encode(message, forKey: .message)
        }
    }
}
