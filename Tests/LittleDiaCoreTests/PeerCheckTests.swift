import Foundation
import Testing
@testable import LittleDiaCore

private let helper = "/Users/x/Applications/Little Dia.app/Contents/Helpers/littledia-host"

/// The bundled helper (pid 20) launched by the browser (pid 10), unless a test changes one of the facts.
private func check(peerPath: String = helper, validSignature: Bool = true, parent: pid_t? = 10,
                   browserPIDs: Set<pid_t> = [10]) -> Bool {
    PeerCheck.isTrusted(peer: 20, helperPath: helper,
                        executablePath: { $0 == 20 ? peerPath : nil },
                        parent: { $0 == 20 ? parent : nil },
                        hasValidSignature: { $0 == 20 && validSignature },
                        isBrowser: { browserPIDs.contains($0) })
}

@Test func acceptsTheBundledHelperLaunchedByTheBrowser() {
    #expect(check())
}

@Test func rejectsAnotherExecutable() {
    #expect(!check(peerPath: "/tmp/evil"))
}

@Test func rejectsAnInvalidSignature() {
    #expect(!check(validSignature: false))
}

@Test func rejectsAHelperNotLaunchedByTheBrowser() {
    #expect(!check(browserPIDs: []))
}

@Test func rejectsAPeerWithoutParent() {
    #expect(!check(parent: nil))
}

@Test func acceptsEquivalentHelperPaths() {   // Review Focus 3: the real helper must never be locked out
    #expect(check(peerPath: "/Users/x/Applications/Little Dia.app/Contents/Helpers/../Helpers/littledia-host"))
}

@Test func diaRequirementPinsDiasTeam() {
    #expect(BrowserAdapter.dia.codeRequirement?.contains("S6N382Y83G") == true)
}

/// Review finding 2: a rejection must say which check failed, so a coworker's Copy Diagnostics explains it.
private func verdict(peerPath: String? = helper, validSignature: Bool = true, parent: pid_t? = 10,
                     browserPIDs: Set<pid_t> = [10]) -> PeerCheck.Verdict {
    PeerCheck.evaluate(peer: 20, helperPath: helper,
                       executablePath: { $0 == 20 ? peerPath : nil },
                       parent: { $0 == 20 ? parent : nil },
                       hasValidSignature: { $0 == 20 && validSignature },
                       isBrowser: { browserPIDs.contains($0) })
}

@Test func explainsWhyAPeerIsRejected() {
    #expect(verdict() == .trusted)
    #expect(verdict(peerPath: "/tmp/evil") == .wrongExecutable("/tmp/evil"))
    #expect(verdict(peerPath: nil) == .wrongExecutable(nil))
    #expect(verdict(validSignature: false) == .invalidSignature)
    #expect(verdict(parent: nil) == .noParent)
    #expect(verdict(browserPIDs: []) == .parentNotBrowser(10))
    #expect(verdict(peerPath: "/tmp/evil").reason(helperPath: helper).contains("/tmp/evil"))
    #expect(verdict(peerPath: "/tmp/evil").reason(helperPath: helper).contains(helper))
}
