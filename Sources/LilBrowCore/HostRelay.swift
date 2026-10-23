import Foundation

/// The heart of `lilbrow-host`: relays whole native-messaging frames between the browser (stdin/stdout) and the
/// menu-bar app (Unix socket), reconnecting to the app whenever it goes away.
public final class HostRelay {
    private let input: FileHandle
    private let output: FileHandle
    private let socketPath: String
    private let hello: InboundMessage
    private let retryInterval: TimeInterval

    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var stopped = false

    public init(input: FileHandle, output: FileHandle, socketPath: String, hello: InboundMessage, retryInterval: TimeInterval = 1.0) {
        self.input = input
        self.output = output
        self.socketPath = socketPath
        self.hello = hello
        self.retryInterval = retryInterval
    }

    /// Blocks until `input` reaches end of file (the browser closed the port).
    public func run() {
        Thread { [self] in socketLoop() }.start()

        var decoder = FrameDecoder()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            guard let payloads = try? decoder.append(chunk) else {
                log("dropping oversize frame from browser")
                decoder = FrameDecoder()
                continue
            }
            for payload in payloads {
                // Frames that arrive while the app isn't connected are dropped.
                lock.withLock {
                    if socketFD >= 0 { UnixSocket.writeAll(socketFD, NativeMessageFraming.encode(payload)) }
                }
            }
        }

        lock.withLock {
            stopped = true
            if socketFD >= 0 { shutdown(socketFD, SHUT_RDWR) }
        }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func socketLoop() {
        while !isStopped {
            guard let fd = try? UnixSocket.connect(path: socketPath) else {
                Thread.sleep(forTimeInterval: retryInterval)
                continue
            }
            let helloFrame = (try? MessageCoding.encode(hello)).map(NativeMessageFraming.encode) ?? Data()
            let connected: Bool = lock.withLock {
                guard !stopped else { return false }
                socketFD = fd
                return UnixSocket.writeAll(fd, helloFrame)
            }
            if connected { pumpSocketToOutput(fd) }
            lock.withLock {
                socketFD = -1
                close(fd)
            }
            if !isStopped { Thread.sleep(forTimeInterval: retryInterval) }
        }
    }

    private func pumpSocketToOutput(_ fd: Int32) {
        var decoder = FrameDecoder()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { return }
            guard let payloads = try? decoder.append(Data(buffer[0..<n])) else { return }
            for payload in payloads {
                do {
                    try output.write(contentsOf: NativeMessageFraming.encode(payload))
                } catch {
                    return
                }
            }
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("lilbrow-host: \(message)\n".utf8))
    }
}
