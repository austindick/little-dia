import CryptoKit
import Foundation
import Testing
@testable import LittleDiaCore

@Test func chromiumIDMatchesManifestKey() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent("Extension/manifest.json"))) as! [String: Any]
    let key = Data(base64Encoded: manifest["key"] as! String)!
    let hex = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined().prefix(32)
    let id = String(hex.map { c -> Character in
        let v = Int(String(c), radix: 16)!
        return Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(v)))
    })
    #expect(id == ExtensionIdentity.chromiumID)
}

@Test func infoPlistUsesTheNewName() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: repo.appendingPathComponent("Resources/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    #expect(plist["CFBundleIdentifier"] as? String == "com.austindick.littledia")
    #expect(plist["CFBundleName"] as? String == "Little Dia")
    #expect(plist["CFBundleExecutable"] as? String == "LittleDia")
}

/// The buttons' backdrop is drawn in this colour; anything else shows as a box behind them (owner's report, 2026-10-24).
@Test func diaTitleBarIsWhiteInLightMode() {   // measured from a screenshot of a little window
    #expect(BrowserAdapter.dia.titleBarColor?.light == RGBColor(red: 255, green: 255, blue: 255))
}

@Test func manifestJSONHasRequiredFields() throws {
    let json = try JSONSerialization.jsonObject(with: NativeHostManifest.json(hostExecutablePath: "/x/littledia-host")) as! [String: Any]
    #expect(json["name"] as? String == "com.austindick.littledia.bridge")
    #expect(json["description"] as? String == "Little Dia bridge")
    #expect(json["path"] as? String == "/x/littledia-host")
    #expect(json["type"] as? String == "stdio")
    #expect(json["allowed_origins"] as? [String] == ["chrome-extension://\(ExtensionIdentity.chromiumID)/"])
}

@Test func installWritesBothDiaLocations() throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: support) }
    let written = try NativeHostManifest.install(hostExecutablePath: "/x/littledia-host", adapter: .dia, applicationSupport: support)
    #expect(written.count == 2)
    #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("Dia/NativeMessagingHosts/com.austindick.littledia.bridge.json").path))
    #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("Dia/User Data/NativeMessagingHosts/com.austindick.littledia.bridge.json").path))
}

@Test func detectsDesktopAssignment() {
    #expect(DesktopAssignment.isAssigned(bundleID: "company.thebrowser.dia", appBindings: ["company.thebrowser.dia": "SPACE-UUID"]))
    #expect(!DesktopAssignment.isAssigned(bundleID: "company.thebrowser.dia", appBindings: [:]))
}

@Test func adapterLookup() {
    #expect(BrowserAdapter.forBundleID("com.google.Chrome") == .chrome)
    #expect(BrowserAdapter.forBundleID("company.thebrowser.dia") == .dia)
}

/// The updater and the extension reload both compare versions; the app and its bundled extension must ship together.
@Test func appAndExtensionVersionsMatch() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: repo.appendingPathComponent("Resources/Info.plist")), format: nil) as! [String: Any]
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent("Extension/manifest.json"))) as! [String: Any]
    #expect(plist["CFBundleShortVersionString"] as? String == manifest["version"] as? String)
    #expect(manifest["version"] as? String == "1.0.0")
}
