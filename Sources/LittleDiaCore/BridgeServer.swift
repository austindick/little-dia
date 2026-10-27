import Foundation
import os

@MainActor
public protocol BridgeServerDelegate: AnyObject {
    func bridge(_ server: BridgeServer, didReceive message: InboundMessage, fromBrowser bundleID: String)
    func bridgeConnectionsChanged(_ server: BridgeServer)
    /// A connection ended; anything sent on it will never be answered.
    func bridge(_ server: BridgeServer, connectionClosed id: Int)
}

public extension BridgeServerDelegate {
    func bridge(_ server: BridgeServer, connectionClosed id: Int) {}
}

/// The Unix-socket server inside the app. Each `littledia-host` helper (one per browser profile running the extension)
/// connects and introduces itself with `hostHello`, which makes it **ready**.
/// Socket reads happen on a private queue; all state and delegate callbacks are on the main actor.
@MainActor
public final class BridgeServer {
    public weak var delegate: BridgeServerDelegate?

    private let socketPath: String
    /// Vets each connecting process by PID before anything it sends is read (see `PeerCheck`).
    private let acceptPeer: @Sendable (pid_t) -> Bool
    private let ioQueue = DispatchQueue(label: "com.austindick.littledia.bridge.io")
    private var listenSource: DispatchSourceRead?
    private var connections: [Int: Connection] = [:]
    private var nextConnectionID = 0
    private var readySequence = 0
    private let logger = Logger(subsystem: "com.austindick.littledia", category: "bridge")

    private final class Connection {
        let fd: Int32
        var source: DispatchSourceRead?
        var browserBundleID: String?
        var browserPID: pid_t?
        /// Order in which connections became ready; the most recent one receives messages.
        var readyOrder: Int?

        init(fd: Int32) { self.fd = fd }
    }

    public init(socketPath: String, acceptPeer: @escaping @Sendable (pid_t) -> Bool = { _ in true }) {
        self.socketPath = socketPath
        self.acceptPeer = acceptPeer
    }

    public func start() throws {
        let fd = try UnixSocket.listen(path: socketPath)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        let acceptPeer = self.acceptPeer, logger = self.logger
        source.setEventHandler { [weak self] in
            guard let client = try? UnixSocket.accept(fd) else { return }
            let pid = UnixSocket.peerPID(client)
            guard let pid, acceptPeer(pid) else {
                logger.notice("rejected connection from pid \(pid ?? -1)")
                close(client)
                return
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.add(client) } }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        listenSource = source
        logger.notice("listening on \(self.socketPath, privacy: .public)")
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
        newestReady(for: bundleID)?.connection.browserPID
    }

    /// Sends to the most recently readied connection for that browser. Returns that connection's ID, or nil if there
    /// is none or the write failed.
    @discardableResult
    public func send(_ message: OutboundMessage, to bundleID: String) -> Int? {
        guard let (id, connection) = newestReady(for: bundleID), let payload = try? MessageCoding.encode(message),
              UnixSocket.writeAll(connection.fd, NativeMessageFraming.encode(payload)) else { return nil }
        return id
    }

    private func newestReady(for bundleID: String) -> (id: Int, connection: Connection)? {
        connections
            .filter { $0.value.browserBundleID == bundleID && $0.value.readyOrder != nil }
            .max { $0.value.readyOrder! < $1.value.readyOrder! }
            .map { (id: $0.key, connection: $0.value) }
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
        logger.notice("connection closed (\(connection.browserBundleID ?? "unknown", privacy: .public))")
        delegate?.bridge(self, connectionClosed: id)
        if notify { delegate?.bridgeConnectionsChanged(self) }
    }

    private func handle(_ payload: Data, from id: Int) {
        guard let connection = connections[id] else { return }
        let message: InboundMessage
        do {
            message = try MessageCoding.decodeInbound(payload)
        } catch {
            // The payload may hold a page's URL, so only its size is public.
            logger.error("skipping undecodable frame (\(payload.count) bytes): \(String(decoding: payload, as: UTF8.self), privacy: .private)")
            return
        }
        if case let .hostHello(bundleID, pid) = message {
            // The helper only runs while the extension's native port is open, so its hello means the extension
            // is reachable. (The extension's own `hello` may arrive before the helper connects and be dropped.)
            connection.browserBundleID = bundleID
            connection.browserPID = pid
            readySequence += 1
            connection.readyOrder = readySequence
            logger.notice("extension ready in \(bundleID, privacy: .public) (pid \(pid))")
            delegate?.bridgeConnectionsChanged(self)
            return
        }
        delegate?.bridge(self, didReceive: message, fromBrowser: connection.browserBundleID ?? "unknown")
    }
}
