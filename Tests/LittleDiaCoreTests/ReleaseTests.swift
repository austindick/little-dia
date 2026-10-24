import Foundation
import Testing
@testable import LittleDiaCore

private func release(tag: String, assets: [String] = ["Little-Dia.zip"]) throws -> ReleaseInfo {
    let assetJSON = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/austindick/little-dia/releases/download/\#(tag)/\#($0)"}"# }
    let json = #"{"tag_name":"\#(tag)","name":"Little Dia","assets":[\#(assetJSON.joined(separator: ","))]}"#
    return try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
}

@Test func parsesVersionsWithOrWithoutV() {
    #expect(Version("v1.2.0") == Version("1.2.0"))
    #expect(Version("1.2.0") != nil)
}

@Test func comparesNumericallyNotLexically() {   // Review Focus 5
    #expect(Version("1.0.10")! > Version("1.0.9")!)
    #expect(Version("2.0.0")! > Version("1.9.9")!)
}

@Test func ignoresUnparseableTags() throws {   // Review Focus 5
    #expect(Version("latest") == nil)
    #expect(Version("1.2") == nil)
    #expect(UpdateOffer.decide(currentVersion: "1.0.0", release: try release(tag: "latest")) == nil)
}

@Test func decodesGitHubRelease() throws {
    let r = try release(tag: "v1.0.1")
    #expect(r.tagName == "v1.0.1")
    #expect(r.assets.map(\.name) == ["Little-Dia.zip"])
    #expect(r.assets.first?.browserDownloadURL.absoluteString == "https://github.com/austindick/little-dia/releases/download/v1.0.1/Little-Dia.zip")
}

@Test func offersANewerReleaseWithTheZip() throws {
    let offer = UpdateOffer.decide(currentVersion: "1.0.0", release: try release(tag: "v1.0.1"))
    #expect(offer?.version == "1.0.1")
    #expect(offer?.downloadURL.lastPathComponent == "Little-Dia.zip")
}

@Test func noOfferForTheSameVersion() throws {
    #expect(UpdateOffer.decide(currentVersion: "1.0.1", release: try release(tag: "v1.0.1")) == nil)
    #expect(UpdateOffer.decide(currentVersion: "1.1.0", release: try release(tag: "v1.0.1")) == nil)
}

@Test func noOfferWithoutTheZipAsset() throws {
    #expect(UpdateOffer.decide(currentVersion: "1.0.0", release: try release(tag: "v1.0.1", assets: ["notes.txt"])) == nil)
}

@Test func refusesToReplaceOutsideAWritableFolder() throws {   // Review Focus 1
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ld-upd-\(UUID().uuidString)")
    let app = folder.appendingPathComponent("X.app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    defer {
        chmod(folder.path, 0o755)
        try? FileManager.default.removeItem(at: folder)
    }
    #expect(UpdateInstall.canReplace(appAt: app))
    #expect(!UpdateInstall.canReplace(appAt: folder))                                  // not an .app
    #expect(!UpdateInstall.canReplace(appAt: folder.appendingPathComponent("Y.app")))  // missing
    chmod(folder.path, 0o555)
    #expect(!UpdateInstall.canReplace(appAt: app))                                     // read-only parent
}
