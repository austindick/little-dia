import AppKit
import LilBrowCore
import os

/// The real browser app, driven through NSWorkspace and NSRunningApplication.
@MainActor
final class BrowserControlImpl: BrowserControl {
    private let logger = Logger(subsystem: "com.lilbrowwow", category: "browser")

    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func launchInBackground(bundleID: String) async -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return true
        } catch {
            logger.error("launching \(bundleID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
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
}
