import Foundation
import Testing
@testable import LittleDiaCore

private func freshFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ld-icons-\(UUID().uuidString)")
}

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4])
private let png = pngBytes.base64EncodedString()

private func entries(_ urls: String...) -> [RecentPages.Entry] {
    urls.map { RecentPages.Entry(url: $0, title: nil, date: Date(timeIntervalSince1970: 0)) }
}

@MainActor @Test func iconsAreKeptPerSite() {
    let folder = freshFolder()
    let icons = SiteIcons(directory: folder)
    icons.markAsked(icons.toAsk(for: entries("https://Docs.Example.com/a")))
    #expect(icons.store(["https://Docs.Example.com/a": png]))
    #expect(icons.pngData(forPage: "https://docs.example.com/b") == pngBytes)
    #expect(SiteIcons(directory: folder).pngData(forPage: "https://docs.example.com/c") == pngBytes)
}

@Test func fileNamesAreSafe() {
    #expect(SiteIcons.iconFileName(forPage: "https://Docs.Example.com:8443/x") == "docs.example.com_8443.png")
    #expect(SiteIcons.iconFileName(forPage: "http://127.0.0.1/") == "127.0.0.1.png")
    #expect(SiteIcons.iconFileName(forPage: "http://localhost:3000/") == "localhost_3000.png")
    #expect(SiteIcons.iconFileName(forPage: "about:blank") == nil)
    #expect(SiteIcons.iconFileName(forPage: "https://a/../../x") == "a.png")
    for page in ["https://a/../../x", "https://x%2F..%2Fy/", "file:///etc/passwd", "https://ex ample.com/"] {
        #expect(!(SiteIcons.iconFileName(forPage: page) ?? "").contains("/"))
    }
}

@MainActor @Test func badDataIsNotKept() {
    let icons = SiteIcons(directory: freshFolder())
    icons.markAsked(icons.toAsk(for: entries("https://a.example/")))
    let big = (pngBytes + Data(count: 256 * 1024)).base64EncodedString()
    for bad in ["not base64!", Data("hello".utf8).base64EncodedString(), big] {
        #expect(!icons.store(["https://a.example/": bad]))
    }
    #expect(icons.pngData(forPage: "https://a.example/") == nil)
}

@MainActor @Test func eachSiteIsAskedOncePerLaunch() {
    let folder = freshFolder()
    let icons = SiteIcons(directory: folder)
    let pages = entries("https://a.example/1", "https://a.example/2", "https://b.example/1")
    icons.markAsked(icons.toAsk(for: pages))
    #expect(icons.toAsk(for: pages) == [])
    #expect(icons.store(["https://a.example/1": png]))
    #expect(SiteIcons(directory: folder).toAsk(for: pages) == ["https://b.example/1"])
}

@MainActor @Test func clearForgetsIconsAndAsksAgain() throws {
    let folder = freshFolder()
    let icons = SiteIcons(directory: folder)
    let pages = entries("https://a.example/1", "https://b.example/1")
    icons.markAsked(icons.toAsk(for: pages))
    #expect(icons.store(["https://a.example/1": png]))
    icons.clear()
    #expect(icons.pngData(forPage: "https://a.example/1") == nil)
    let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    #expect(!left.contains { $0.hasSuffix(".png") })
    #expect(icons.toAsk(for: pages).count == 2)
}

@MainActor @Test func aSiteIsAskedAgainUntilARequestGoesOut() {
    // Little Dia can open the box before Dia connects: nothing is sent, so nothing counts as asked.
    let icons = SiteIcons(directory: freshFolder())
    let pages = entries("https://a.example/1", "https://b.example/1")
    #expect(icons.toAsk(for: pages).count == 2)
    #expect(icons.toAsk(for: pages).count == 2)
    icons.markAsked(icons.toAsk(for: pages))
    #expect(icons.toAsk(for: pages) == [])
}

@MainActor @Test func onlyAskedSitesAreStoredSoClearIsFinal() {
    let folder = freshFolder()
    let icons = SiteIcons(directory: folder)
    #expect(!icons.store(["https://never-asked.example/": png]))
    icons.markAsked(icons.toAsk(for: entries("https://a.example/1")))
    icons.clear()
    // A reply to the request made before Clear Recent Pages arrives afterwards: it isn't written back.
    #expect(!icons.store(["https://a.example/1": png]))
    #expect(icons.pngData(forPage: "https://a.example/1") == nil)
}
