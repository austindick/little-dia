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
        static let remembersResizedSize = "remembersResizedSize"
        static let browser = "browserBundleID"
        static let chromeHeight = "chromeHeight"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let closesInactive = "closeInactiveLittleWindows"
        static let inactiveCloseSecondsOverride = "inactiveCloseSecondsOverride"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.width: 1200.0,
            Key.height: 750.0,
            Key.remembersResizedSize: false,
            Key.closesInactive: false,
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

    /// Whether resizing a little window sets the size the next ones open at. Off by default: some people want every
    /// little window at the same size, and set it from the menu instead.
    public var remembersResizedSize: Bool {
        get { defaults.bool(forKey: Key.remembersResizedSize) }
        set { defaults.set(newValue, forKey: Key.remembersResizedSize) }
    }

    /// Whether little windows nobody has looked at for Dia's tab-cleanup interval are closed. Off by default, so
    /// updating never starts closing anyone's windows.
    public var closesInactiveLittleWindows: Bool {
        get { defaults.bool(forKey: Key.closesInactive) }
        set { defaults.set(newValue, forKey: Key.closesInactive) }
    }

    /// For trying the closing out without waiting hours: seconds to use in place of Dia's interval. Set only by hand
    /// (`defaults write`).
    public var inactiveCloseSecondsOverride: TimeInterval? {
        (defaults.object(forKey: Key.inactiveCloseSecondsOverride) as? Double).flatMap { $0 > 0 ? $0 : nil }
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

    /// Sets the size little windows open at (page area, without the browser's title bar). A size below the minimum
    /// isn't one a person chose (a window's thumbnail in Mission Control, say) and is ignored.
    public func rememberSize(_ bounds: Bounds) {
        guard CGFloat(bounds.width) >= ScreenGeometry.minimumSize.width,
              CGFloat(bounds.height) >= ScreenGeometry.minimumSize.height else { return }
        defaults.set(Double(bounds.width), forKey: Key.width)
        defaults.set(Double(bounds.height), forKey: Key.height)
    }
}
