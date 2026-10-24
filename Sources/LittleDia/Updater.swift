import AppKit
import LittleDiaCore
import os
import Security

/// Checks GitHub for a newer release and installs it in place. Never installs without a click; never replaces this app
/// with one that isn't signed the same way (same identifier, same certificate), so the Accessibility permission carries
/// over.
@MainActor
final class Updater {
    enum State: Equatable {
        case idle, checking, installing, upToDate
        case available(UpdateOffer)
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?

    private let settings: UserDefaultsSettings
    private var timer: Timer?
    private let logger = Logger(subsystem: "com.austindick.littledia", category: "updater")

    init(settings: UserDefaultsSettings) {
        self.settings = settings
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var offer: UpdateOffer? {
        if case let .available(offer) = state { return offer }
        return nil
    }

    /// Checks shortly after launch and then hourly, but asks GitHub at most once a day.
    func startAutomaticChecks() {
        Task {
            try? await Task.sleep(for: .seconds(10))
            await checkIfDue()
        }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfDue() async {
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        if case .available = state { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        state = .checking
        do {
            var request = URLRequest(url: ReleaseSource.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError("GitHub answered \(status)") }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            settings.lastUpdateCheck = Date()
            if let offer = UpdateOffer.decide(currentVersion: currentVersion, release: release) {
                state = .available(offer)
                logger.notice("update available: \(offer.version, privacy: .public)")
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(Self.describe(error))
            logger.error("update check failed: \(Self.describe(error), privacy: .public)")
        }
        guard userInitiated else { return }
        switch state {
        case .upToDate:
            alert("Little Dia \(currentVersion) is up to date.")
        case let .available(offer):
            if alert("Little Dia \(offer.version) is available.", info: "You have \(currentVersion).", buttons: ["Update", "Later"]) {
                await install(offer)
            }
        case let .failed(reason):
            alert("Couldn't check for updates: \(reason)")
        default:
            break
        }
    }

    func install(_ offer: UpdateOffer) async {
        let bundleURL = Bundle.main.bundleURL
        guard UpdateInstall.canReplace(appAt: bundleURL) else {
            fail("Little Dia isn't in a folder it can update (\(bundleURL.deletingLastPathComponent().path)).")
            return
        }
        state = .installing
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("little-dia-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let (download, response) = try await URLSession.shared.download(from: offer.downloadURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError("the download failed (\(status))") }
            let zip = work.appendingPathComponent(ReleaseSource.assetName)
            try FileManager.default.moveItem(at: download, to: zip)
            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent(bundleURL.lastPathComponent)
            guard FileManager.default.fileExists(atPath: newApp.path) else { throw UpdateError("the download didn't contain \(bundleURL.lastPathComponent)") }
            try Self.verifySignedLikeThisApp(newApp)
            try Self.replace(bundleURL, with: newApp)
            logger.notice("installed \(offer.version, privacy: .public); relaunching")
            // Relaunch from a shell that outlives this process.
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", #"sleep 1; open "$0""#, bundleURL.path]
            try relaunch.run()
            NSApp.terminate(nil)
        } catch {
            fail("Couldn't update: \(Self.describe(error))")
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        logger.error("\(message, privacy: .public)")
        alert(message)
    }

    /// The new app must meet this app's own designated requirement: same identifier, same signing certificate.
    private static func verifySignedLikeThisApp(_ app: URL) throws {
        var me: SecCode?
        var meOnDisk: SecStaticCode?
        var requirement: SecRequirement?
        var newCode: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meOnDisk) == errSecSuccess, let meOnDisk,
              SecCodeCopyDesignatedRequirement(meOnDisk, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw UpdateError("couldn't read the signatures")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(newCode, flags, requirement)
        guard status == errSecSuccess else { throw UpdateError("the new version isn't signed like this one (\(status))") }
    }

    /// Moves the running app to the Trash and the new one into its place, putting the old one back if that fails.
    private static func replace(_ installed: URL, with newApp: URL) throws {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: installed, resultingItemURL: &trashed)
        do {
            try FileManager.default.moveItem(at: newApp, to: installed)
        } catch {
            if let trashed = trashed as URL? { try? FileManager.default.moveItem(at: trashed, to: installed) }
            throw error
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError("\(tool) failed (\(finished.terminationStatus))"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Shows an alert; with buttons, returns whether the first was chosen.
    @discardableResult
    private func alert(_ message: String, info: String? = nil, buttons: [String] = []) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        if let info { alert.informativeText = info }
        buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func describe(_ error: Error) -> String {
        (error as? UpdateError)?.message ?? error.localizedDescription
    }
}

private struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
