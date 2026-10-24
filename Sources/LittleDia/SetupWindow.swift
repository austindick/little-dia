import AppKit
import LittleDiaCore
import SwiftUI

/// The setup window's state. It re-reads everything once a second while the window is open, so each row ticks
/// itself off as the user finishes it.
@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var status: SetupStatus
    @Published private(set) var openAtLogin: Bool
    /// A one-line note under the extension row's buttons (e.g. "the path is on your clipboard").
    @Published private(set) var extensionNote: String?

    let extensionFolder: URL
    private let readStatus: () -> SetupStatus
    private let openExtensionsPageInBrowser: () async -> Bool
    private var timer: Timer?

    init(extensionFolder: URL, readStatus: @escaping () -> SetupStatus, openExtensionsPage: @escaping () async -> Bool) {
        self.extensionFolder = extensionFolder
        self.readStatus = readStatus
        self.openExtensionsPageInBrowser = openExtensionsPage
        status = readStatus()
        openAtLogin = SystemIntegration.launchAtLogin
    }

    func startRefreshing() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        status = readStatus()
        openAtLogin = SystemIntegration.launchAtLogin
    }

    func setAsDefault() {
        Task {
            await SystemIntegration.makeDefaultBrowser()
            refresh()
        }
    }

    func openExtensionsPage() {
        Task {
            if await openExtensionsPageInBrowser() {
                extensionNote = nil
            } else {
                copyToClipboard("chrome://extensions")
                extensionNote = "Couldn't open it for you. chrome://extensions is on your clipboard: paste it into Dia's address bar."
            }
        }
    }

    func showFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([extensionFolder])
        copyToClipboard(extensionFolder.path)
        extensionNote = "The folder's path is on your clipboard too, for the Load unpacked picker (⌘⇧G, then paste)."
    }

    func openAccessibilitySettings() {
        _ = SystemIntegration.isAccessibilityTrusted(prompt: true)
        SystemIntegration.openAccessibilitySettings()
    }

    func setOpenAtLogin(_ on: Bool) {
        SystemIntegration.launchAtLogin = on
        openAtLogin = SystemIntegration.launchAtLogin
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// "Set Up Little Dia": one row per step, each with a live status, as in the approved mockup.
struct SetupView: View {
    @ObservedObject var model: SetupModel
    let onDone: () -> Void

    private enum Mark { case done, current, pending, warning }

    var body: some View {
        let status = model.status
        let extensionDone = status.extensionState != .missing
        // The first unfinished step is highlighted.
        let current: Int? = !status.isDefaultBrowser ? 1 : !extensionDone ? 2 : !status.accessibilityGranted ? 3 : nil

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                row(mark: status.isDefaultBrowser ? .done : current == 1 ? .current : .pending, highlighted: current == 1,
                    title: "Make it your default browser") {
                    detail("Links from other apps come here first.")
                    if !status.isDefaultBrowser {
                        Button("Set as Default", action: model.setAsDefault).controlSize(.small)
                    }
                }
                Divider()
                row(mark: extensionDone ? .done : current == 2 ? .current : .pending, highlighted: current == 2,
                    title: "Add the extension to Dia") {
                    if extensionDone {
                        detail(extensionDoneText(status))
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1. Open Dia's Extensions page")
                            Text("2. Turn on **Developer mode** (top right)")
                            Text("3. Click **Show Folder**, then drag the highlighted **Extension** folder onto the page (or click **Load unpacked** and choose it)")
                        }
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Open Extensions Page", action: model.openExtensionsPage)
                                .keyboardShortcut(.defaultAction)
                            Button("Show Folder", action: model.showFolder)
                        }
                        .controlSize(.small)
                        .padding(.top, 2)
                        if let note = model.extensionNote { detail(note) }
                        detail("Add it in the Dia profile you want little windows to use.")
                        detail("◌ Waiting for the extension…")
                    }
                }
                Divider()
                row(mark: status.accessibilityGranted ? .done : current == 3 ? .current : .pending, highlighted: current == 3,
                    title: "Allow the title-bar buttons") {
                    detail("Turn on Little Dia under Accessibility so it can show Copy and Open in Dia.")
                    if !status.accessibilityGranted {
                        Button("Open Settings", action: model.openAccessibilitySettings).controlSize(.small)
                    }
                }
                if status.browserPinnedToDesktop {
                    Divider()
                    row(mark: .warning, highlighted: false, title: "Dia is pinned to one desktop") {
                        detail("Dock → right-click Dia → Options → Assign To → None")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()
            HStack {
                Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Done", action: onDone)
                    .disabled(!status.requiredDone)
                    .keyboardShortcut(status.requiredDone ? .defaultAction : .cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 480)
    }

    private func extensionDoneText(_ status: SetupStatus) -> String {
        let place = status.profile.map { " in \($0)" } ?? ""
        return status.extensionState == .connected ? "Connected\(place)." : "Added\(place). It connects when Dia is open."
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row<Content: View>(mark: Mark, highlighted: Bool, title: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            markView(mark)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, highlighted ? 10 : 0)
        .background(highlighted ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, highlighted ? -10 : 0)
    }

    @ViewBuilder private func markView(_ mark: Mark) -> some View {
        switch mark {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .font(.system(size: 20))
        case .current:
            Image(systemName: "circle").foregroundStyle(Color.accentColor)
                .font(.system(size: 20, weight: .semibold))
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
                .font(.system(size: 20))
        case .warning:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                .font(.system(size: 20))
        }
    }
}

/// The "Set Up Little Dia" window. Refreshes only while it's open.
@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let model: SetupModel

    init(model: SetupModel) {
        self.model = model
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Set Up Little Dia"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: SetupView(model: model) { [weak window] in window?.close() })
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        model.startRefreshing()
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRefreshing()
    }
}
