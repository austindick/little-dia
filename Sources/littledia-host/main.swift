// littledia-host: the native-messaging helper a Chromium browser launches for the Little Dia extension.
// It relays frames between the browser (stdin/stdout) and the menu-bar app's Unix socket.
// stdout is the protocol channel: log only to stderr.
import AppKit
import LittleDiaCore

signal(SIGPIPE, SIG_IGN)

func parentPID(of pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let ppid = info.kp_eproc.e_ppid
    return ppid > 1 ? ppid : nil
}

/// Walks up the process tree to the first ancestor that is an app with a bundle ID: the browser.
func launchingBrowser() -> (bundleID: String, pid: pid_t) {
    var pid = getppid()
    for _ in 0..<5 {
        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            return (bundleID, pid)
        }
        guard let next = parentPID(of: pid) else { break }
        pid = next
    }
    return ("unknown", getppid())
}

let environment = ProcessInfo.processInfo.environment
let socketPath = environment["LITTLEDIA_SOCKET"]
    ?? (NSHomeDirectory() + "/Library/Application Support/Little Dia/bridge.sock")
let browser = launchingBrowser()
FileHandle.standardError.write(Data("littledia-host: browser=\(browser.bundleID) pid=\(browser.pid) socket=\(socketPath)\n".utf8))

HostRelay(input: .standardInput, output: .standardOutput, socketPath: socketPath,
          hello: .hostHello(browserBundleID: browser.bundleID, browserPID: browser.pid)).run()
