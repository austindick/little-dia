import Foundation

public enum UnixSocketError: Error, Equatable {
    case pathTooLong
    case sys(Int32)
}

/// Minimal POSIX Unix-domain stream sockets. Every socket returned has SIGPIPE disabled.
public enum UnixSocket {
    /// Removes any stale socket file at `path`, then binds and listens.
    public static func listen(path: String) throws -> Int32 {
        unlink(path)
        let fd = try makeSocket()
        do {
            try withAddress(path) { addr, len in
                guard Darwin.bind(fd, addr, len) == 0 else { throw UnixSocketError.sys(errno) }
            }
            guard Darwin.listen(fd, 8) == 0 else { throw UnixSocketError.sys(errno) }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    public static func connect(path: String) throws -> Int32 {
        let fd = try makeSocket()
        do {
            try withAddress(path) { addr, len in
                guard Darwin.connect(fd, addr, len) == 0 else { throw UnixSocketError.sys(errno) }
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    public static func accept(_ listenFD: Int32) throws -> Int32 {
        let fd = Darwin.accept(listenFD, nil, nil)
        guard fd >= 0 else { throw UnixSocketError.sys(errno) }
        disableSigPipe(fd)
        return fd
    }

    /// Writes all of `data`, retrying partial writes. Returns false if the peer is gone.
    @discardableResult
    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var p = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let n = write(fd, p, remaining)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                remaining -= n
                p += n
            }
            return true
        }
    }

    private static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.sys(errno) }
        disableSigPipe(fd)
        return fd
    }

    private static func disableSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Void) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { throw UnixSocketError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        try withUnsafePointer(to: &addr) { p in
            try p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                try body(sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}
