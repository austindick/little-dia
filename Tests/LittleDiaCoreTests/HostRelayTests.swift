import Foundation
import Testing
@testable import LittleDiaCore

private let hostHello = InboundMessage.hostHello(browserBundleID: "test.browser", browserPID: 1)

/// Starts a listener and a relay on a background thread; `finished` is signalled when `run()` returns.
private func startRelay() throws -> (listenFD: Int32, input: Pipe, output: Pipe, finished: DispatchSemaphore) {
    let path = makeSocketPath()
    let listenFD = try UnixSocket.listen(path: path)
    let input = Pipe(), output = Pipe()
    let relay = HostRelay(input: input.fileHandleForReading, output: output.fileHandleForWriting,
                          socketPath: path, hello: hostHello, retryInterval: 0.1)
    let finished = DispatchSemaphore(value: 0)
    Thread { relay.run(); finished.signal() }.start()
    return (listenFD, input, output, finished)
}

@Test func sendsHostHelloFirst() throws {
    let r = try startRelay()
    let conn = try acceptConnection(r.listenFD)
    #expect(try FrameReader(fd: conn).next() == MessageCoding.encode(hostHello))
}

@Test func relaysInputFramesToSocket() throws {
    let r = try startRelay()
    let conn = try acceptConnection(r.listenFD)
    let reader = FrameReader(fd: conn)
    _ = try reader.next()   // hostHello
    let hello = Data(#"{"type":"hello","extensionVersion":"0.1.0"}"#.utf8)
    writeFrame(r.input.fileHandleForWriting.fileDescriptor, hello)
    #expect(try reader.next() == hello)
}

@Test func relaysSocketFramesToOutput() throws {
    let r = try startRelay()
    let conn = try acceptConnection(r.listenFD)
    _ = try FrameReader(fd: conn).next()   // hostHello
    let move = try MessageCoding.encode(OutboundMessage.move(windowId: 42))
    writeFrame(conn, move)
    #expect(try FrameReader(fd: r.output.fileHandleForReading.fileDescriptor).next() == move)
}

@Test func reconnectsAfterServerDrops() throws {
    let r = try startRelay()
    let first = try acceptConnection(r.listenFD)
    _ = try FrameReader(fd: first).next()
    close(first)
    let second = try acceptConnection(r.listenFD, timeout: 2)
    #expect(try FrameReader(fd: second).next() == MessageCoding.encode(hostHello))
}

@Test func returnsOnInputEOF() throws {
    let r = try startRelay()
    _ = try acceptConnection(r.listenFD)
    try r.input.fileHandleForWriting.close()
    #expect(r.finished.wait(timeout: .now() + 1) == .success)
}
