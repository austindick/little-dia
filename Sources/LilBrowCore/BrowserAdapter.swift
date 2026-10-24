import CoreGraphics
import Foundation

/// Everything browser-specific lives here, so supporting another Chromium browser means adding one adapter.
public struct BrowserAdapter: Equatable, Sendable {
    public let name: String
    public let bundleID: String
    /// Native-messaging manifest folders, relative to ~/Library/Application Support.
    public let nativeHostDirectories: [String]
    /// Height the browser adds above a popup's page area (title bar and address row).
    public let chromeHeight: CGFloat
    /// The browser's user-data folder (profiles), relative to ~/Library/Application Support.
    public let userDataDirectory: String?

    public init(name: String, bundleID: String, nativeHostDirectories: [String], chromeHeight: CGFloat = 0,
                userDataDirectory: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.nativeHostDirectories = nativeHostDirectories
        self.chromeHeight = chromeHeight
        self.userDataDirectory = userDataDirectory
    }

    /// Dia's folder is reported as both of these; installing to both settles which one it reads.
    public static let dia = BrowserAdapter(name: "Dia", bundleID: "company.thebrowser.dia",
                                           nativeHostDirectories: ["Dia/NativeMessagingHosts", "Dia/User Data/NativeMessagingHosts"],
                                           chromeHeight: 72,   // measured 2026-10-23
                                           userDataDirectory: "Dia/User Data")
    public static let chrome = BrowserAdapter(name: "Chrome", bundleID: "com.google.Chrome",
                                              nativeHostDirectories: ["Google/Chrome/NativeMessagingHosts"])
    public static let all: [BrowserAdapter] = [.dia, .chrome]

    public static func forBundleID(_ bundleID: String) -> BrowserAdapter? {
        all.first { $0.bundleID == bundleID }
    }
}

/// Whether macOS pins an app to one desktop (Dock › Options › Assign To). If it does, every new window of that app
/// opens on that desktop, which defeats little windows.
public enum DesktopAssignment {
    /// `appBindings` is the `app-bindings` dictionary from the `com.apple.spaces` preferences; keys are lowercased bundle IDs.
    public static func isAssigned(bundleID: String, appBindings: [String: Any]) -> Bool {
        appBindings[bundleID.lowercased()] != nil
    }
}
