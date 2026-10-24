import CoreGraphics
import Foundation

/// The text Copy Diagnostics puts on the clipboard: versions, setup status and recent log lines, ready to paste into a
/// message when something goes wrong on someone's Mac. URLs are scrubbed, since people browse private things.
public enum Diagnostics {
    public static let maxLogLines = 300

    public static func report(appVersion: String, extensionVersion: String?, macOSVersion: String, browserVersion: String?,
                              status: SetupStatus, profiles: BrowserProfiles?, chromeHeight: CGFloat, logLines: [String]) -> String {
        let profileLine = profiles.map { "\($0.all.joined(separator: ", ")) (extension in \($0.current))" } ?? "none found"
        let facts = [
            "Little Dia diagnostics",
            "App: \(appVersion)",
            "Extension: \(extensionVersion ?? "not connected")",
            "macOS: \(macOSVersion)",
            "Dia: \(browserVersion ?? "not found")",
            "Status: \(status.menuLine.text)",
            "Default browser: \(status.isDefaultBrowser ? "yes" : "no")",
            "Extension state: \(status.extensionState)",
            "Accessibility: \(status.accessibilityGranted ? "granted" : "not granted")",
            "Dia pinned to a desktop: \(status.browserPinnedToDesktop ? "yes" : "no")",
            "Profiles: \(profileLine)",
            "Title bar: \(Int(chromeHeight.rounded()))pt",
            "",
            "Recent log:",
        ]
        return (facts + logLines.suffix(maxLogLines).map(scrubURLs)).joined(separator: "\n")
    }

    static func scrubURLs(_ line: String) -> String {
        line.replacingOccurrences(of: #"https?://\S+"#, with: "<url>", options: .regularExpression)
    }
}
