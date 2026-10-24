import Foundation
import Testing
@testable import LittleDiaCore

private let allSet = SetupStatus(isDefaultBrowser: true, extensionState: .connected, accessibilityGranted: true,
                                 browserPinnedToDesktop: false, profile: "Work")

private func report(extensionVersion: String? = "0.2.0", profiles: BrowserProfiles? = BrowserProfiles(current: "Work", others: ["Personal"]),
                    logLines: [String] = []) -> String {
    Diagnostics.report(appVersion: "1.0.0", extensionVersion: extensionVersion, macOSVersion: "26.7", browserVersion: "1.54.2",
                       status: allSet, profiles: profiles, chromeHeight: 72, logLines: logLines)
}

@Test func reportListsVersionsAndStatus() {
    let text = report()
    for line in ["App: 1.0.0", "Extension: 0.2.0", "Dia: 1.54.2", "Status: All set · Work",
                 "Profiles: Personal, Work (extension in Work)", "Title bar: 72pt"] {
        #expect(text.contains(line), "missing \(line)")
    }
}

@Test func reportScrubsURLs() {   // diagnostics get pasted into Slack; never leak what people browse
    let text = report(logLines: ["01:02:03 [router] opened https://secret.example/a?b=c now"])
    #expect(text.contains("01:02:03 [router] opened <url> now"))
    #expect(!text.contains("secret.example"))
}

@Test func reportKeepsOnlyTheLast300LogLines() {
    let text = report(logLines: (1...400).map { "line \($0)" })
    #expect(!text.contains("line 100\n"))
    #expect(text.contains("line 101\n"))
    #expect(text.hasSuffix("line 400"))
}

@Test func reportHandlesMissingValues() {
    let text = report(extensionVersion: nil, profiles: nil)
    #expect(text.contains("Extension: not connected"))
    #expect(text.contains("Profiles: none found"))
}
