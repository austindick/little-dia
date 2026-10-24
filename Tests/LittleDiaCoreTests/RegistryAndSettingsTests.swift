import CoreGraphics
import Foundation
import Testing
@testable import LittleDiaCore

@Test func registryTracksURLChanges() {
    let registry = LittleWindowRegistry()
    let first = "https://github.com/", second = "https://github.com/pulls"
    let bounds = Bounds(left: 300, top: 137, width: 1000, height: 750)
    registry.apply(.opened(requestId: "r1", windowId: 42, url: first, bounds: bounds), from: "company.thebrowser.dia")
    #expect(registry.info(for: 42) == LittleWindowInfo(windowId: 42, browserBundleID: "company.thebrowser.dia", url: first, bounds: bounds))
    registry.apply(.littleURL(windowId: 42, url: second), from: "company.thebrowser.dia")
    #expect(registry.info(for: 42)?.url == second)
    registry.apply(.littleClosed(windowId: 42), from: "company.thebrowser.dia")
    #expect(registry.info(for: 42) == nil)
}

@MainActor @Test func settingsDefaultsAndRememberSize() {
    let suite = "ld-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = UserDefaultsSettings(defaults: defaults)
    #expect(settings.isEnabled)
    #expect(settings.littleWindowSize == CGSize(width: 1200, height: 750))
    #expect(settings.browser == .dia)
    settings.rememberSize(Bounds(left: 0, top: 0, width: 900, height: 700))
    #expect(settings.littleWindowSize == CGSize(width: 900, height: 700))
    settings.isEnabled = false
    #expect(!UserDefaultsSettings(defaults: defaults).isEnabled)
}

/// Owner's report, 2026-10-24: a click in Mission Control saved the window's thumbnail, 103 by -4, so the next little
/// window opened at the minimum size.
@MainActor @Test func settingsIgnoresASizeBelowTheMinimum() {
    let suite = "ld-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = UserDefaultsSettings(defaults: defaults)
    settings.rememberSize(Bounds(left: 0, top: 0, width: 1364, height: 797))
    settings.rememberSize(Bounds(left: 0, top: 0, width: 103, height: -4))
    #expect(settings.littleWindowSize == CGSize(width: 1364, height: 797))
    settings.rememberSize(Bounds(left: 0, top: 0, width: 900, height: 300))
    #expect(settings.littleWindowSize == CGSize(width: 1364, height: 797))
    settings.rememberSize(Bounds(left: 0, top: 0, width: 480, height: 360))   // the minimum itself is fine
    #expect(settings.littleWindowSize == CGSize(width: 480, height: 360))
}

@MainActor @Test func settingsRemembersAPlausibleChromeHeight() {
    let suite = "ld-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = UserDefaultsSettings(defaults: defaults)
    #expect(settings.chromeHeight == 72)
    settings.rememberChromeHeight(80)
    #expect(settings.chromeHeight == 80)
    settings.rememberChromeHeight(500)   // a mismeasurement (e.g. the window was mid-animation) is ignored
    #expect(settings.chromeHeight == 80)
    settings.rememberChromeHeight(5)
    #expect(settings.chromeHeight == 80)
}
