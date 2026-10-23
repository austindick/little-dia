import Foundation
import os

@MainActor
public protocol BridgeServerDelegate: AnyObject {
    func bridge(_ server: BridgeServer, didReceive message: InboundMessage, fromBrowser bundleID: String)
    func bridgeConnectionsChanged(_ server: BridgeServer)
}

/// The Unix-socket server inside the app. Each `lilbrow-host` helper (one per browser profile running the extension)
/// connects, introduces itself with `hostHello`, and becomes **ready** once the extension's `hello` arrives.
/// Socket reads happen on a private queue; all state and delegate callbacks are on the main actor.
@MainActor
public final class BridgeServer {
    public weak var delegate: BridgeServerDelegate?

    private let socketPath: String
    private let ioQueue = DispatchQueue(label: "com.lilbrowwow.bridge.io")
    private var listenSource: DispatchSourceRead?
    private var connections: [Int: Connection] = [:]
    private var nextConnectionID = 0
    private var readySequence = 0
    private let logger = Logger(subsystem: "com.lilbrowwow", category: "bridge")

    private final class Connection {
        let fd: Int32
        var source: DispatchSourceRead?
        var browserBundleID: String?
        var browserPID: pid_t?
        /// Order in which connections became ready; the most recent one receives messages.
        var readyOrder: Int?

        init(fd: Int32) { self.fd = fd }
    }

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func start() throws {
        let fd = try UnixSocket.listen(path: socketPath)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        source.setEventHandler { [weak self] in
            guard let client = try? UnixSocket.accept(fd) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.add(client) } }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        listenSource = source
        logger.info("listening on \(self.socketPath, privacy: .public)")
    }

    public func stop() {
        listenSource?.cancel()
        listenSource = nil
        for id in Array(connections.keys) { remove(id, notify: false) }
        unlink(socketPath)
    }

    public func isReady(browser bundleID: String) -> Bool {
        newestReady(for: bundleID) != nil
    }

    public func browserPID(for bundleID: String) -> pid_t? {
        newestReady(for: bundleID)?.browserPID
    }

    /// Sends to the most recently readied connection for that browser. Returns false if there is none.
    @discardableResult
    public func send(_ message: OutboundMessage, to bundleID: String) -> Bool {
        guard let connection = newestReady(for: bundleID), let payload = try? MessageCoding.encode(message) else { return false }
        return UnixSocket.writeAll(connection.fd, NativeMessageFraming.encode(payload))
    }

    private func newestReady(for bundleID: String) -> Connection? {
        connections.values
            .filter { $0.browserBundleID == bundleID && $0.readyOrder != nil }
            .max { $0.readyOrder! < $1.readyOrder! }
    }

    private func add(_ fd: Int32) {
        let id = nextConnectionID
        nextConnectionID += 1
        let connection = Connection(fd: fd)
        connections[id] = connection

        var decoder = FrameDecoder()
        var reportedEOF = false
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        source.setEventHandler { [weak self] in
            // After EOF the source keeps firing until the main actor cancels it; report the close only once.
            if reportedEOF { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buffer, buffer.count)
            let payloads: [Data]?
            if n > 0 {
                payloads = try? decoder.append(Data(buffer[0..<n]))
            } else {
                payloads = nil
                reportedEOF = true
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let payloads else {
                        self.remove(id, notify: true)
                        return
                    }
                    for payload in payloads { self.handle(payload, from: id) }
                }
            }
        }
        source.setCancelHandler { close(fd) }
        connection.source = source
        source.resume()
    }

    private func remove(_ id: Int, notify: Bool) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.source?.cancel()
        logger.info("connection closed (\(connection.browserBundleID ?? "unknown", privacy: .public))")
        if notify { delegate?.bridgeConnectionsChanged(self) }
    }

    private func handle(_ payload: Data, from id: Int) {
        guard let connection = connections[id] else { return }
        let message: InboundMessage
        do {
            message = try MessageCoding.decodeInbound(payload)
        } catch {
            logger.error("skipping undecodable frame: \(String(decoding: payload, as: UTF8.self), privacy: .public)")
            return
        }
        switch message {
        case let .hostHello(bundleID, pid):
            connection.browserBundleID = bundleID
            connection.browserPID = pid
            return
        case .hello:
            if connection.browserBundleID != nil, connection.readyOrder == nil {
                readySequence += 1
                connection.readyOrder = readySequence
                logger.info("extension ready in \(connection.browserBundleID!, privacy: .public)")
                delegate?.bridgeConnectionsChanged(self)
            }
        default:
            break
        }
        delegate?.bridge(self, didReceive: message, fromBrowser: connection.browserBundleID ?? "unknown")
    }
}
