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
    public static func isTrusted(peer: pid_t, helperPath: String,
                                 executablePath: (pid_t) -> String?,
                                 parent: (pid_t) -> pid_t?,
                                 hasValidSignature: (pid_t) -> Bool,
                                 isBrowser: (pid_t) -> Bool) -> Bool {
        guard let path = executablePath(peer), canonical(path) == canonical(helperPath),
              hasValidSignature(peer),
              let parentPID = parent(peer) else { return false }
        return isBrowser(parentPID)
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
