import AppKit
import ApplicationServices
import LilBrowCore
import ServiceManagement

@MainActor
enum SystemIntegration {
    static func isDefaultBrowser() -> Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm the change.
    static func makeDefaultBrowser() async {
        for scheme in ["http", "https"] where !handles(scheme) {
            try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
        }
    }

    private static func handles(_ scheme: String) -> Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }

    /// True when the browser is pinned to one desktop (Dock › Options › Assign To), which sends every new window there.
    static func isBrowserAssignedToDesktop(_ bundleID: String) -> Bool {
        let bindings = CFPreferencesCopyAppValue("app-bindings" as CFString, "com.apple.spaces" as CFString) as? [String: Any] ?? [:]
        return DesktopAssignment.isAssigned(bundleID: bundleID, appBindings: bindings)
    }
}
