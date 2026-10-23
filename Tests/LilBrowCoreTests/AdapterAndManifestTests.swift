import CryptoKit
import Foundation
import Testing
@testable import LilBrowCore

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

@Test func manifestJSONHasRequiredFields() throws {
    let json = try JSONSerialization.jsonObject(with: NativeHostManifest.json(hostExecutablePath: "/x/lilbrow-host")) as! [String: Any]
    #expect(json["name"] as? String == "com.lilbrowwow.bridge")
    #expect(json["path"] as? String == "/x/lilbrow-host")
    #expect(json["type"] as? String == "stdio")
    #expect(json["allowed_origins"] as? [String] == ["chrome-extension://\(ExtensionIdentity.chromiumID)/"])
}

@Test func installWritesBothDiaLocations() throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: support) }
    let written = try NativeHostManifest.install(hostExecutablePath: "/x/lilbrow-host", adapter: .dia, applicationSupport: support)
    #expect(written.count == 2)
    #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("Dia/NativeMessagingHosts/com.lilbrowwow.bridge.json").path))
    #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("Dia/User Data/NativeMessagingHosts/com.lilbrowwow.bridge.json").path))
}

@Test func detectsDesktopAssignment() {
    #expect(DesktopAssignment.isAssigned(bundleID: "company.thebrowser.dia", appBindings: ["company.thebrowser.dia": "SPACE-UUID"]))
    #expect(!DesktopAssignment.isAssigned(bundleID: "company.thebrowser.dia", appBindings: [:]))
}

@Test func adapterLookup() {
    #expect(BrowserAdapter.forBundleID("com.google.Chrome") == .chrome)
    #expect(BrowserAdapter.forBundleID("company.thebrowser.dia") == .dia)
}
