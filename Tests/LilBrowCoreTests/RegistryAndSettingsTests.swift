import CoreGraphics
import Foundation
import Testing
@testable import LilBrowCore

@Test func registryTracksURLChanges() {
    let registry = LittleWindowRegistry()
    let first = URL(string: "https://github.com/")!, second = URL(string: "https://github.com/pulls")!
    let bounds = Bounds(left: 300, top: 137, width: 1000, height: 750)
    registry.apply(.opened(requestId: "r1", windowId: 42, url: first, bounds: bounds), from: "company.thebrowser.dia")
    #expect(registry.info(for: 42) == LittleWindowInfo(windowId: 42, browserBundleID: "company.thebrowser.dia", url: first, bounds: bounds))
    registry.apply(.littleURL(windowId: 42, url: second), from: "company.thebrowser.dia")
    #expect(registry.info(for: 42)?.url == second)
    registry.apply(.littleClosed(windowId: 42), from: "company.thebrowser.dia")
    #expect(registry.info(for: 42) == nil)
}

@MainActor @Test func settingsDefaultsAndRememberSize() {
    let suite = "lbw-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = UserDefaultsSettings(defaults: defaults)
    #expect(settings.isEnabled)
    #expect(settings.littleWindowSize == CGSize(width: 1000, height: 750))
    #expect(settings.browser == .dia)
    settings.rememberSize(Bounds(left: 0, top: 0, width: 900, height: 700))
    #expect(settings.littleWindowSize == CGSize(width: 900, height: 700))
    settings.isEnabled = false
    #expect(!UserDefaultsSettings(defaults: defaults).isEnabled)
}
