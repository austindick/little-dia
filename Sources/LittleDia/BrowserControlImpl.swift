import AppKit
import LittleDiaCore
import os

/// The real browser app, driven through NSWorkspace and NSRunningApplication.
@MainActor
final class BrowserControlImpl: BrowserControl {
    private let logger = Logger(subsystem: "com.austindick.littledia", category: "browser")

    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func openNormally(_ url: URL, bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.error("\(bundleID, privacy: .public) is not installed; cannot open link")
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { [logger] _, error in
            if let error { logger.error("opening link normally failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func activate(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }

    /// Takes you to the browser's main window, switching desktops if needed. Opening the app through LaunchServices
    /// does this even when the browser is already active (spike method M2), unlike `activate`.
    func showMainWindow(bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [logger] _, error in
            if let error { logger.error("showing main window failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func onScreenWindows(bundleID: String) -> [WindowCandidate<Int>] {
        windows(of: bundleID, options: [.optionOnScreenOnly, .excludeDesktopElements]).map { WindowCandidate(id: $0.number, frame: $0.frame) }
    }

    /// The browser's normal-level windows from the window server (top-left coordinates).
    private func windows(of bundleID: String, options: CGWindowListOption) -> [(number: Int, frame: CGRect)] {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else { return [] }
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
            return (number, frame)
        }
    }
}
