// littledia-host: the native-messaging helper a Chromium browser launches for the Little Dia extension.
// It relays frames between the browser (stdin/stdout) and the menu-bar app's Unix socket.
// stdout is the protocol channel: log only to stderr.
import AppKit
import LittleDiaCore

signal(SIGPIPE, SIG_IGN)

/// Walks up the process tree to the first ancestor that is an app with a bundle ID: the browser.
func launchingBrowser() -> (bundleID: String, pid: pid_t) {
    var pid = getppid()
    for _ in 0..<5 {
        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            return (bundleID, pid)
        }
        guard let next = ProcessTree.parentPID(of: pid) else { break }
        pid = next
    }
    return ("unknown", getppid())
}

let environment = ProcessInfo.processInfo.environment
let socketPath = environment["LITTLEDIA_SOCKET"]
    ?? (NSHomeDirectory() + "/Library/Application Support/Little Dia/bridge.sock")
let browser = launchingBrowser()
FileHandle.standardError.write(Data("littledia-host: browser=\(browser.bundleID) pid=\(browser.pid) socket=\(socketPath)\n".utf8))

// An install or update replaces this file. The new app can't vouch for a process whose file has changed, so once the
// app drops the connection, exit: the extension reconnects and the browser starts the new helper.
let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
let launchedAs = FileIdentity(path: executablePath)
HostRelay(input: .standardInput, output: .standardOutput, socketPath: socketPath,
          hello: .hostHello(browserBundleID: browser.bundleID, browserPID: browser.pid),
          shouldGiveUp: { FileIdentity(path: executablePath) != launchedAs }).run()
