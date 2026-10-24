import Foundation
import Testing
@testable import LittleDiaCore

private let browser = "test.browser"
private let github = URL(string: "https://github.com/")!
private let someBounds = Bounds(left: 300, top: 137, width: 1000, height: 750)

/// A fake `littledia-host` connection.
private final class TestClient: @unchecked Sendable {
    let fd: Int32
    let reader: FrameReader
    init(path: String) throws {
        fd = try UnixSocket.connect(path: path)
        reader = FrameReader(fd: fd)
    }
    func send(_ m: InboundMessage) throws { writeFrame(fd, try MessageCoding.encode(m)) }
    func sendRaw(_ json: String) { writeFrame(fd, Data(json.utf8)) }
    func ready(pid: Int32 = 99) throws {
        try send(.hostHello(browserBundleID: browser, browserPID: pid))
        try send(.hello(extensionVersion: "0.1.0"))
    }
    /// Reads off the main actor so the server can keep working.
    func readOutbound(timeout: TimeInterval = 2) async throws -> OutboundMessage? {
        let reader = self.reader
        let data = try await Task.detached { try reader.next(timeout: timeout) }.value
        return try data.map(MessageCoding.decodeOutbound)
    }
    func close() { Darwin.close(fd) }
}

@MainActor private final class RecordingDelegate: BridgeServerDelegate {
    var messages: [InboundMessage] = []
    var connectionChanges = 0
    func bridge(_ server: BridgeServer, didReceive message: InboundMessage, fromBrowser bundleID: String) { messages.append(message) }
    func bridgeConnectionsChanged(_ server: BridgeServer) { connectionChanges += 1 }
}

@MainActor private func until(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor private func startServer() throws -> (BridgeServer, String) {
    let path = makeSocketPath()
    let server = BridgeServer(socketPath: path)
    try server.start()
    return (server, path)
}

/// The helper only runs while the extension's native port is open, so its hostHello alone means "ready".
/// (The extension's own hello can arrive before the helper reaches the app and be dropped.)
@MainActor @Test func becomesReadyOnHostHelloAlone() async throws {
    let (server, path) = try startServer(); defer { server.stop() }
    let client = try TestClient(path: path)
    try client.send(.hostHello(browserBundleID: browser, browserPID: 99))
    #expect(await until { server.isReady(browser: browser) })
    #expect(server.browserPID(for: browser) == 99)
}

@MainActor @Test func sendsToMostRecentReadyConnection() async throws {
    let (server, path) = try startServer(); defer { server.stop() }
    let first = try TestClient(path: path)
    try first.ready(pid: 1)
    #expect(await until { server.browserPID(for: browser) == 1 })
    let second = try TestClient(path: path)
    try second.ready(pid: 2)
    #expect(await until { server.browserPID(for: browser) == 2 })
    #expect(server.send(.move(windowId: 42), to: browser))
    #expect(try await second.readOutbound() == .move(windowId: 42))
    await #expect(throws: TimedOut.self) { _ = try await first.readOutbound(timeout: 0.3) }
}

@MainActor @Test func notReadyAfterClientDisconnects() async throws {   // Review Focus 4
    let (server, path) = try startServer(); defer { server.stop() }
    let recorder = RecordingDelegate()
    server.delegate = recorder
    let client = try TestClient(path: path)
    try client.ready()
    #expect(await until { server.isReady(browser: browser) })
    let changesBefore = recorder.connectionChanges
    client.close()
    #expect(await until { !server.isReady(browser: browser) })
    #expect(recorder.connectionChanges > changesBefore)
}

@MainActor @Test func skipsUndecodableFrames() async throws {
    let (server, path) = try startServer(); defer { server.stop() }
    let recorder = RecordingDelegate()
    server.delegate = recorder
    let client = try TestClient(path: path)
    try client.ready()
    client.sendRaw(#"{"type":"bogus"}"#)
    try client.send(.littleClosed(windowId: 5))
    #expect(await until { recorder.messages.contains(.littleClosed(windowId: 5)) })
}

@MainActor @Test func openResolvesOnMatchingAck() async throws {
    let (server, path) = try startServer(); defer { server.stop() }
    let link = BridgeExtensionLink(server: server)
    let client = try TestClient(path: path)
    try client.ready()
    #expect(await until { link.isReady(browser: browser) })
    async let result = link.open(OpenRequest(requestId: "r1", url: github, bounds: someBounds, focused: true), browser: browser, timeout: .seconds(2))
    let received = try await client.readOutbound()
    #expect(received == .open(requestId: "r1", url: github, bounds: someBounds, focused: true))
    try client.send(.opened(requestId: "r1", windowId: 42, url: github.absoluteString, bounds: someBounds))
    #expect(await result == .opened(windowId: 42))
}

@MainActor @Test func openTimesOut() async throws {
    let (server, path) = try startServer(); defer { server.stop() }
    let link = BridgeExtensionLink(server: server)
    let client = try TestClient(path: path)
    try client.ready()
    #expect(await until { link.isReady(browser: browser) })
    let result = await link.open(OpenRequest(requestId: "r1", url: github, bounds: someBounds, focused: true), browser: browser, timeout: .milliseconds(200))
    #expect(result == .timedOut)
}

@MainActor @Test func openFailedIsReported() async throws {
    let (server, path) = try startServer(); defer { server.stop() }
    let link = BridgeExtensionLink(server: server)
    let client = try TestClient(path: path)
    try client.ready()
    #expect(await until { link.isReady(browser: browser) })
    async let result = link.open(OpenRequest(requestId: "r1", url: github, bounds: someBounds, focused: true), browser: browser, timeout: .seconds(2))
    _ = try await client.readOutbound()
    try client.send(.openFailed(requestId: "r1", error: "boom"))
    #expect(await result == .failed("boom"))
}

@MainActor @Test func waitUntilReadyReturnsTrueWhenClientArrivesMidWait() async throws {   // Review Focus 1
    let (server, path) = try startServer(); defer { server.stop() }
    let link = BridgeExtensionLink(server: server)
    let connect = Task.detached {
        try await Task.sleep(for: .milliseconds(300))
        let client = try TestClient(path: path)
        try client.ready()
        return client
    }
    #expect(await link.waitUntilReady(browser: browser, timeout: .seconds(2)))
    _ = try await connect.value
}
