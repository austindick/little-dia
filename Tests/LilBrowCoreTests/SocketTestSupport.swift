import Foundation
@testable import LilBrowCore

func makeSocketPath() -> String {
    NSTemporaryDirectory() + "lbw-\(UUID().uuidString.prefix(8)).sock"
}

struct TimedOut: Error {}

/// Waits up to `timeout` for `fd` to become readable.
func waitReadable(_ fd: Int32, timeout: TimeInterval) -> Bool {
    var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    return poll(&p, 1, Int32(timeout * 1000)) > 0
}

/// Accepts one connection on a listening socket, or throws after `timeout`.
func acceptConnection(_ listenFD: Int32, timeout: TimeInterval = 2) throws -> Int32 {
    guard waitReadable(listenFD, timeout: timeout) else { throw TimedOut() }
    return try UnixSocket.accept(listenFD)
}

/// Reads frames from a file descriptor, keeping leftovers between calls.
final class FrameReader {
    let fd: Int32
    private var decoder = FrameDecoder()
    private var pending: [Data] = []

    init(fd: Int32) { self.fd = fd }

    /// Next frame payload, nil on EOF; throws TimedOut after `timeout`.
    func next(timeout: TimeInterval = 2) throws -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while pending.isEmpty {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, waitReadable(fd, timeout: remaining) else { throw TimedOut() }
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return nil }
            pending += try decoder.append(Data(buf[0..<n]))
        }
        return pending.removeFirst()
    }
}

func writeFrame(_ fd: Int32, _ payload: Data) {
    let frame = NativeMessageFraming.encode(payload)
    _ = frame.withUnsafeBytes { write(fd, $0.baseAddress, frame.count) }
}
