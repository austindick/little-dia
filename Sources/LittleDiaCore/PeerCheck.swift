import Foundation

/// Process-tree lookups shared by the helper (to find the browser that launched it) and the app (to vet it).
public enum ProcessTree {
    public static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 1 ? ppid : nil
    }
}

/// Decides whether a bridge connection comes from the real extension: the app's own bundled helper, intact, launched
/// directly by the browser. Without this, any process running as the user could connect last, become the newest
/// ready connection and receive every clicked link.
public enum PeerCheck {
    /// The outcome of vetting a connecting process; rejections say which check failed.
    public enum Verdict: Equatable, Sendable {
        case trusted
        /// The process isn't the bundled helper (its executable path, if it could be read).
        case wrongExecutable(String?)
        case invalidSignature
        case noParent
        /// The process that launched the helper isn't the browser.
        case parentNotBrowser(pid_t)

        public func reason(helperPath: String) -> String {
            switch self {
            case .trusted: return "trusted"
            case let .wrongExecutable(path?): return "its executable is \(path), not \(helperPath)"
            case .wrongExecutable(nil): return "its executable path couldn't be read"
            case .invalidSignature: return "its code signature isn't the helper's"
            case .noParent: return "it has no parent process"
            case let .parentNotBrowser(pid): return "its parent (pid \(pid)) isn't the browser"
            }
        }
    }

    public static func evaluate(peer: pid_t, helperPath: String,
                                executablePath: (pid_t) -> String?,
                                parent: (pid_t) -> pid_t?,
                                hasValidSignature: (pid_t) -> Bool,
                                isBrowser: (pid_t) -> Bool) -> Verdict {
        let path = executablePath(peer)
        guard let path, canonical(path) == canonical(helperPath) else { return .wrongExecutable(path) }
        guard hasValidSignature(peer) else { return .invalidSignature }
        guard let parentPID = parent(peer) else { return .noParent }
        return isBrowser(parentPID) ? .trusted : .parentNotBrowser(parentPID)
    }

    public static func isTrusted(peer: pid_t, helperPath: String,
                                 executablePath: (pid_t) -> String?,
                                 parent: (pid_t) -> pid_t?,
                                 hasValidSignature: (pid_t) -> Bool,
                                 isBrowser: (pid_t) -> Bool) -> Bool {
        evaluate(peer: peer, helperPath: helperPath, executablePath: executablePath, parent: parent,
                 hasValidSignature: hasValidSignature, isBrowser: isBrowser) == .trusted
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// Identifies the file at a path (device, inode, size, modification time), to notice when an install or update has
/// replaced it.
public struct FileIdentity: Equatable, Sendable {
    let device: Int64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int

    public init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        device = Int64(info.st_dev)
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        modifiedSeconds = info.st_mtimespec.tv_sec
        modifiedNanoseconds = info.st_mtimespec.tv_nsec
    }
}
