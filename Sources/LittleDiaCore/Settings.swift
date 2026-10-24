import CoreGraphics
import Foundation

@MainActor
public protocol LittleSettings: AnyObject {
    var isEnabled: Bool { get }
    var littleWindowSize: CGSize { get }
    var browser: BrowserAdapter { get }
    /// Height the browser adds above a little window's page area, as last measured (the adapter's value until then).
    var chromeHeight: CGFloat { get }
}

@MainActor
public final class UserDefaultsSettings: LittleSettings {
    private enum Key {
        static let enabled = "enabled"
        static let width = "littleWindowWidth"
        static let height = "littleWindowHeight"
        static let browser = "browserBundleID"
        static let chromeHeight = "chromeHeight"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let lastUpdateCheck = "lastUpdateCheck"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.width: 1200.0,
            Key.height: 750.0,
            Key.browser: BrowserAdapter.dia.bundleID,   // chosen by the 2026-10-23 same-desktop spike
        ])
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    public var littleWindowSize: CGSize {
        CGSize(width: defaults.double(forKey: Key.width), height: defaults.double(forKey: Key.height))
    }

    public var browser: BrowserAdapter {
        BrowserAdapter.forBundleID(defaults.string(forKey: Key.browser) ?? "") ?? .dia
    }

    /// False until the first launch has set up what a first launch sets up (open at login).
    public var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }

    /// When GitHub was last asked for a newer release.
    public var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    public var chromeHeight: CGFloat {
        (defaults.object(forKey: Key.chromeHeight) as? Double).map { CGFloat($0) } ?? browser.chromeHeight
    }

    /// Stores a measured title-bar height; implausible values (a window caught mid-animation) are ignored.
    public func rememberChromeHeight(_ height: CGFloat) {
        guard (20...200).contains(height) else { return }
        defaults.set(Double(height), forKey: Key.chromeHeight)
    }

        /// Little windows open at the size the user last resized one to (page area, without the browser's title bar).
    public func rememberSize(_ bounds: Bounds) {
        defaults.set(Double(bounds.width), forKey: Key.width)
        defaults.set(Double(bounds.height), forKey: Key.height)
    }
}
