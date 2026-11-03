import Darwin
import Foundation
import LittleDiaCore
import os
import Security

/// The real-process side of `PeerCheck`: executable paths from the kernel, parents from the process tree, and code
/// signatures from the Security framework. The returned closure runs on the bridge's I/O queue.
enum PeerVerifier {
    private static let logger = Logger(subsystem: "com.austindick.littledia", category: "bridge")

    /// - Parameter onModifiedBrowser: called (on the I/O queue) when the helper's parent is signed as the browser but
    ///   fails its requirement: a copy of the browser re-signed by someone else, for example after a patch.
    static func make(helperPath: String, browserRequirement: String?, browserBundleID: String,
                     onModifiedBrowser: @escaping @Sendable () -> Void) -> @Sendable (pid_t) -> Bool {
        // The connecting helper must meet the bundled helper's own designated requirement: same identifier, same
        // signing certificate. The app's signature seals the helper, so check the bundle first.
        let helperRequirement = designatedRequirement(ofHelperAt: helperPath)
        let helper = SendableRequirement(helperRequirement)
        let browser = SendableRequirement(browserRequirement.flatMap(requirement(from:)))
        return { pid in
            let verdict = PeerCheck.evaluate(
                peer: pid, helperPath: helperPath,
                executablePath: executablePath(of:),
                parent: ProcessTree.parentPID(of:),
                hasValidSignature: { satisfies($0, helper.value, what: "helper") },
                isBrowser: { pid in
                    let trusted = satisfies(pid, browser.value, what: "browser")
                    if !trusted, signing(of: guest(pid)).identifier == browserBundleID { onModifiedBrowser() }
                    return trusted
                })
            if verdict != .trusted {
                logger.notice("rejected pid \(pid): \(verdict.reason(helperPath: helperPath), privacy: .public)")
            }
            return verdict == .trusted
        }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// True when the running process `pid` has an intact signature that meets `requirement`. A nil requirement never
    /// matches, so a browser without one (or a helper whose requirement couldn't be read) is never trusted.
    private static func satisfies(_ pid: pid_t, _ requirement: SecRequirement?, what: String) -> Bool {
        guard let requirement else {
            logger.notice("no code requirement for the \(what, privacy: .public); pid \(pid) can't be checked")
            return false
        }
        let code = guest(pid)
        var status = code == nil ? errSecCSNoSuchCode : errSecSuccess
        if let code { status = SecCodeCheckValidity(code, [], requirement) }
        if status != errSecSuccess {
            let signer = signing(of: code)
            let description = "\(executablePath(of: pid) ?? "executable unknown"), identifier \(signer.identifier ?? "none"), team \(signer.team ?? "none")"
            logger.notice("pid \(pid) fails the \(what, privacy: .public) signature check (OSStatus \(status)): \(description, privacy: .public)")
        }
        return status == errSecSuccess
    }

    /// The running process's code, for signature checks.
    private static func guest(_ pid: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else { return nil }
        return code
    }

    /// The identifier and team a process's code is signed with (nil when unsigned, ad-hoc, or unreadable).
    private static func signing(of code: SecCode?) -> (identifier: String?, team: String?) {
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard let code, SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return (nil, nil) }
        return (info[kSecCodeInfoIdentifier as String] as? String, info[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    private static func requirement(from text: String) -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            logger.error("invalid code requirement: \(text, privacy: .public)")
            return nil
        }
        return requirement
    }

    private static func designatedRequirement(ofHelperAt path: String) -> SecRequirement? {
        var app: SecStaticCode?
        if SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &app) == errSecSuccess, let app {
            let status = SecStaticCodeCheckValidity(app, SecCSFlags(rawValue: kSecCSCheckNestedCode), nil)
            if status != errSecSuccess { logger.error("app bundle signature check failed (\(status)); the helper may have been altered") }
        }
        var helper: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &helper) == errSecSuccess, let helper,
              SecCodeCopyDesignatedRequirement(helper, [], &requirement) == errSecSuccess else {
            logger.error("could not read the helper's signing requirement at \(path, privacy: .public)")
            return nil
        }
        return requirement
    }
}

/// `SecRequirement` is immutable once created; this lets the verifier closure carry one across queues.
private final class SendableRequirement: @unchecked Sendable {
    let value: SecRequirement?
    init(_ value: SecRequirement?) { self.value = value }
}
