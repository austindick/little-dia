import AppKit
import LittleDiaCore

/// New Little Window: a floating box for a web address or a search, since a little window's own address bar can't
/// be typed in. Return opens it; Esc, or clicking elsewhere, cancels. It's a non-activating panel, like Spotlight: it
/// takes typing while the app you were in stays frontmost, so cancelling leaves you where you were.
///
/// A link on the clipboard is offered as the placeholder, and Tab fills it in. macOS asks before an app reads the
/// clipboard from code, so unless Little Dia is set to Always Allow, the box only checks that a link is there (which
/// doesn't ask) and Tab pastes it.
///
/// Recent, under the box (or ↓), lists pages recently opened in little windows inside the box: typing filters
/// it, ↑/↓ choose, and Return or a click opens one.
@MainActor
final class AddressBox: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum Suggestion: Equatable {
        case none
        /// The copied link, read from the clipboard.
        case link(URL)
        /// A link is on the clipboard but wasn't read.
        case copiedLink
    }

    private enum Metrics {
        static let width: CGFloat = 560
        static let cornerRadius: CGFloat = 12
        /// Clear space around the box for its shadow, which the panel draws itself.
        static let margin: CGFloat = 40
        static let header: CGFloat = 52
        static let row: CGFloat = 30
        static let visibleRows = 8
        /// Space between the list's edges and its rows, the same on every side.
        static let listMargin: CGFloat = 6
        /// The list's bottom corners, like the box's; a chosen row's are smaller by the margin, so they're concentric.
        static let listCorner: CGFloat = cornerRadius
        /// The divider between the text field and the rows: just the line, where the box's bottom edge is when the
        /// list is closed. The rows' margin below it is the list's usual one.
        static let eyebrow: CGFloat = 1
        /// The Recent tab, counting the shoulders that curve into the edge above it.
        static let recent = NSSize(width: 154, height: 22)
        /// How far the list and tab reach up behind the box.
        static let recentTuck: CGFloat = 12
        /// Pulling the tab down to show the list, or back up.
        static let pull: CFTimeInterval = 0.26
    }

    private static let placeholder = "Enter a web address or search"
    private let panel: KeyablePanel
    private let box = NSVisualEffectView()
    /// Holds the box and casts its shadow: a soft one, with a crisp edge inside it like a window's.
    private let boxShadow = FlippedView()
    private let field = NSTextField()
    private let icon = DiaLogoView()
    private let keyCap = KeyCapView(label: "tab")
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let noMatches = NSTextField(labelWithString: "No matching pages")
    private let recentButton = RecentButton(tab: Metrics.recent, listWidth: Metrics.recent.width, listCorner: Metrics.listCorner,
                                            tuck: Metrics.recentTuck)
    /// Holds the Recent tab behind the box and casts its shadow.
    private let recentShadow = FlippedView()
    private var onSubmit: ((URL) -> Void)?
    private var suggestion = Suggestion.none { didSet { updateHint() } }
    /// Counts openings, so a clipboard check that finishes after the box has closed is ignored.
    private var opening = 0
    private var recent: RecentPages?
    private var isExpanded = false
    private var results: [RecentPages.Entry] = []
    private var listHeightConstraint: NSLayoutConstraint!
    private var fieldToKeyCap: NSLayoutConstraint!
    private var fieldToEdge: NSLayoutConstraint!
    private var keyCapWidth: NSLayoutConstraint!
    /// The text field's editor, with no padding before the text: the default's padding scrolls away with long text,
    /// which then runs up against the icon.
    private let fieldEditor: NSTextView = {
        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.textContainer?.lineFragmentPadding = 0
        return editor
    }()
    /// Where the rows start in the sheet; while it's pulled open or shut, they ride on its bottom edge.
    private var listTop: NSLayoutConstraint!
    /// The list's rows live in this, the part of the sheet below the box's edge, sized to what's pulled out.
    private let listClip = FlippedView()
    /// A rule across: the divider between the text field and the list.
    private let eyebrow = NSView()
    private var listClipHeight: NSLayoutConstraint!
    /// The list's full height, and whether the rows ride on the sheet's bottom edge as it moves (opening and closing)
    /// or stay put (the list changing length while open).
    private var listFull: CGFloat = 0
    private var rowsRide = false
    /// How far the tab is pulled down (the height of list showing above it), and the animation moving it, if any.
    private var pulled: CGFloat = 0
    private var tabAnimation: Timer?

    override init() {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.header),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The box draws its own shadow: a window shadow would also outline Recent's text under it and smear it.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        box.material = .popover
        box.state = .active
        // A mask image, not a layer corner radius: the window's shadow and backing follow it, so the corners stay clear.
        box.maskImage = Self.roundedMask(radius: Metrics.cornerRadius)

        field.placeholderAttributedString = Self.placeholderText(Self.placeholder)
        field.font = .systemFont(ofSize: 20)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        // Truncates (a long copied link in the placeholder ends in "…"); typing still scrolls sideways.
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        keyCap.isHidden = true
        keyCap.onClick = { [weak self] in self?.keyCapClicked() }

        let column = NSTableColumn(identifier: .init("page"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        // Plain, not inset: the margins around the rows are the list's own, the same on every side.
        table.style = .plain
        table.rowHeight = Metrics.row
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.refusesFirstResponder = true   // typing stays in the field
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: Metrics.listMargin, left: 0, bottom: Metrics.listMargin, right: 0)

        noMatches.font = .systemFont(ofSize: 13)
        noMatches.textColor = .secondaryLabelColor
        noMatches.isHidden = true

        for view in [icon, field, keyCap] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        // The list lives in the Recent tab, in the part that shows below the box and inside its shoulders.
        // Clipped to the part of the sheet below the box's edge, so rows riding the sheet never show above it.
        listClip.clipsToBounds = true
        listClip.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(listClip)
        for view in [eyebrow, scroll, noMatches] {
            view.translatesAutoresizingMaskIntoConstraints = false
            listClip.addSubview(view)
        }
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        eyebrow.addSubview(rule)
        // Lined up with the rows' text.
        let textInset = Metrics.listMargin + RecentCell.textInset
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: box.topAnchor, constant: Metrics.header / 2),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 18),
            // The field editor has no padding before the text (see `windowWillReturnFieldEditor`), so typed text starts
            // where the placeholder does, and long text that scrolls stops the same distance from the icon.
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            keyCap.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            keyCap.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            keyCap.heightAnchor.constraint(equalToConstant: 24),

            // A fixed width, so the rows don't reflow as the tab grows around them.
            // The list is part of the box, below the text field; the box grows down to show it.
            listClip.topAnchor.constraint(equalTo: box.topAnchor, constant: Metrics.header),
            listClip.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            listClip.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            eyebrow.leadingAnchor.constraint(equalTo: listClip.leadingAnchor),
            eyebrow.trailingAnchor.constraint(equalTo: listClip.trailingAnchor),
            eyebrow.heightAnchor.constraint(equalToConstant: Metrics.eyebrow),
            rule.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor, constant: textInset),
            rule.trailingAnchor.constraint(equalTo: eyebrow.trailingAnchor, constant: -textInset),
            rule.centerYAnchor.constraint(equalTo: eyebrow.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: eyebrow.bottomAnchor),
            scroll.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            scroll.widthAnchor.constraint(equalToConstant: Metrics.width - 2 * Metrics.listMargin),
            noMatches.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            // Centred between the divider and the box's bottom edge.
            noMatches.centerYAnchor.constraint(equalTo: rule.centerYAnchor,
                                               constant: (Metrics.eyebrow / 2 + Metrics.row + 2 * Metrics.listMargin) / 2),
        ])

        // The field runs to the tab key when it shows, and to the box's edge when it doesn't.
        fieldToKeyCap = field.trailingAnchor.constraint(equalTo: keyCap.leadingAnchor, constant: -10)
        fieldToEdge = field.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16)
        fieldToEdge.isActive = true
        keyCapWidth = keyCap.widthAnchor.constraint(equalToConstant: 40)
        keyCapWidth.isActive = true

        // The list's height is set as the tab grows; nothing ties it to the tab's bottom, so the closed tab clips it
        // without conflicting constraints.
        listHeightConstraint = scroll.heightAnchor.constraint(equalToConstant: 0)
        listHeightConstraint.isActive = true
        listTop = eyebrow.topAnchor.constraint(equalTo: listClip.topAnchor)
        listClipHeight = listClip.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([listTop, listClipHeight])

        recentButton.onClick = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
        }
        // Clicking the text field's part of the box goes back up from the list to the Recent tab.
        panel.onMouseDown = { [weak self] point in
            guard let self, self.isExpanded else { return }
            let inBox = self.boxShadow.convert(point, from: nil)
            guard self.boxShadow.bounds.contains(inBox), inBox.y < Metrics.header else { return }
            // The go key opens the chosen row, so it leaves the list open.
            if !self.keyCap.isHidden, self.keyCap.bounds.contains(self.keyCap.convert(point, from: nil)) { return }
            self.setExpanded(false)
        }

        let container = FlippedView()
        // The Recent tab sits behind the box, as if it slid out from under it: each has its own edge and shadow, and
        // the box's shadow falls on the tab.
        let shadows: [(NSView, NSView, blur: CGFloat, offset: CGFloat, opacity: CGFloat)] = [
            (recentButton, recentShadow, 8, -3, 0.15), (box, boxShadow, 18, -8, 0.3),
        ]
        for (view, shadow, blur, offset, opacity) in shadows {
            let edge = FlippedView()
            edge.shadow = Self.shadow(blur: 1, offset: 0, opacity: 0.25)
            edge.autoresizingMask = [.width, .height]
            view.autoresizingMask = [.width, .height]
            edge.addSubview(view)
            shadow.shadow = Self.shadow(blur: blur, offset: offset, opacity: opacity)
            shadow.addSubview(edge)
            container.addSubview(shadow)
        }
        panel.contentView = container
    }

    /// Shows the box on this desktop, on the screen the pointer is on. If it's already open, brings it forward as it is.
    func show(recent: RecentPages, onSubmit: @escaping (URL) -> Void) {
        self.onSubmit = onSubmit
        self.recent = recent
        if !panel.isVisible {
            field.stringValue = ""
            isExpanded = false
            lookForCopiedLink()
            layOut()
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
                let visible = screen.visibleFrame, size = panel.frame.size
                let top = visible.maxY - visible.height / 3 + Metrics.header + Metrics.margin
                panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: top - size.height))
            }
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            go()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        case #selector(NSResponder.moveDown(_:)):
            if !isExpanded {
                guard !(recent?.entries.isEmpty ?? true) else { return true }
                setExpanded(true)
            }
            select(min(table.selectedRow + 1, results.count - 1))
            return true
        case #selector(NSResponder.moveUp(_:)):
            // Up from the first page (or with none chosen) goes back to the box, closing the list into the tab.
            guard isExpanded else { return true }
            if table.selectedRow > 0 { select(table.selectedRow - 1) } else { setExpanded(false) }
            return true
        case #selector(NSResponder.insertTab(_:)):
            // Tab takes the copied link; otherwise it does nothing (there's nowhere else in the box to go).
            useCopiedLink(textView)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            return true
        default:
            return false
        }
    }

    /// Return, or the go key: opens the chosen page in the list, or what's typed. Empty text keeps the box open.
    private func go() {
        if isExpanded, results.indices.contains(table.selectedRow) {
            open(results[table.selectedRow])
            return
        }
        guard let url = AddressInput.url(from: field.stringValue) else { return }
        submit(url)
    }

    /// Tab, or the tab key: fills in the copied link when nothing's typed.
    private func useCopiedLink(_ editor: NSTextView) {
        guard field.stringValue.isEmpty else { return }
        switch suggestion {
        case let .link(url):
            editor.insertText(url.absoluteString, replacementRange: NSRange(location: 0, length: 0))
        case .copiedLink:
            editor.paste(nil)
        case .none:
            break
        }
    }

    /// The key at the field's right end, clicked: go with text in the field, tab without.
    private func keyCapClicked() {
        if !field.stringValue.isEmpty {
            go()
        } else {
            panel.makeFirstResponder(field)
            useCopiedLink(fieldEditor)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        updateHint()
        if isExpanded { refreshResults(animated: true) }
    }

    // MARK: Recent

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        refreshResults(animated: true)
    }

    /// Filters the list by what's typed, with nothing chosen (so Return still opens the typed text), and resizes the
    /// tab. Closing keeps the rows, so they're still there as the tab shrinks over them.
    private func refreshResults(animated: Bool = false) {
        if isExpanded {
            results = recent?.matching(field.stringValue) ?? []
            table.reloadData()
        }
        table.deselectAll(nil)
        updateHint()
        layOut(animated: animated)
    }

    private func select(_ row: Int) {
        if row >= 0 {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        updateHint()
    }

    @objc private func rowClicked() {
        guard results.indices.contains(table.clickedRow) else { return }
        open(results[table.clickedRow])
    }

    private func open(_ entry: RecentPages.Entry) {
        guard let url = URL(string: entry.url) else { return }
        submit(url)
    }

    private func submit(_ url: URL) {
        let submit = onSubmit
        dismiss()
        submit?(url)
    }

    /// Places the Recent tab under the box, pulled down to show the list or up against the box. It's shown once there's
    /// something in it. `animated` moves it smoothly. The box's top edge stays put.
    private func layOut(animated: Bool = false) {
        let rows = min(max(results.count, 1), Metrics.visibleRows)
        let listHeight = CGFloat(rows) * Metrics.row + 2 * Metrics.listMargin
        let showsTab = isExpanded || !(recent?.entries.isEmpty ?? true)
        let target = isExpanded ? Metrics.eyebrow + listHeight : 0

        tabAnimation?.invalidate()
        tabAnimation = nil
        listHeightConstraint.constant = listHeight
        listFull = Metrics.eyebrow + listHeight
        rowsRide = pulled == 0 || target == 0
        recentButton.setExpanded(isExpanded)

        let start = pulled
        guard animated, showsTab, !recentShadow.isHidden, start != target else {
            recentShadow.isHidden = !showsTab
            finishPull(at: target, showsTab: showsTab)
            return
        }
        // Room for the list at its longer while the tab moves. Opening, the rows come out from under the box on the
        // sheet's bottom edge; closing, they go back up with it (they're kept until it's shut).
        resizePanel(pulled: max(start, target), showsTab: true)
        scroll.isHidden = false
        noMatches.isHidden = !results.isEmpty
        let pull = AnimationStage(duration: Metrics.pull) { [unowned self] e in setPulled(start + (target - start) * e) }
        tabAnimation = AnimationStage.run([pull]) { [weak self] in
            self?.tabAnimation = nil
            self?.finishPull(at: target, showsTab: showsTab)
        }
    }

    private func finishPull(at height: CGFloat, showsTab: Bool) {
        setPulled(height)
        scroll.isHidden = !isExpanded
        noMatches.isHidden = !isExpanded || !results.isEmpty
        resizePanel(pulled: height, showsTab: showsTab)
    }

    private func setPulled(_ height: CGFloat) {
        pulled = height
        // The box's bottom edge comes down with the tab, which hangs from it.
        boxShadow.frame = NSRect(x: Metrics.margin, y: Metrics.margin, width: Metrics.width, height: Metrics.header + height)
        recentShadow.frame = NSRect(x: Metrics.margin + (Metrics.width - Metrics.recent.width) / 2,
                                    y: Metrics.margin + Metrics.header + height - Metrics.recentTuck,
                                    width: Metrics.recent.width, height: Metrics.recentTuck + Metrics.recent.height)
        listClipHeight.constant = height
        listTop.constant = rowsRide ? min(0, height - listFull) : 0
    }

    /// Sizes the panel for the box and, below it, the list `pulled` tall and the tab; keeps its top edge where it is.
    private func resizePanel(pulled: CGFloat, showsTab: Bool) {
        let below = showsTab ? pulled + Metrics.recent.height : 0
        let height = Metrics.header + below + 2 * Metrics.margin, width = Metrics.width + 2 * Metrics.margin
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height), display: true)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: RecentCell.identifier, owner: nil) as? RecentCell ?? RecentCell()
        cell.show(results[row], now: Date())
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        EmphasizedRowView(cornerRadius: Metrics.listCorner - Metrics.listMargin)
    }

    // MARK: Copied link

    /// Works out what to offer from the clipboard, without making macOS ask about reading it.
    private func lookForCopiedLink() {
        opening += 1
        suggestion = .none
        let pasteboard = NSPasteboard.general
        guard #available(macOS 15.4, *) else {
            // Earlier versions don't ask.
            suggestion = Self.link(on: pasteboard)
            return
        }
        switch pasteboard.accessBehavior {
        case .alwaysAllow:
            suggestion = Self.link(on: pasteboard)
        case .alwaysDeny:
            break
        default:
            let opening = self.opening
            Task { @MainActor [weak self] in
                guard let found = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]),
                      found.contains(\.probableWebURL),
                      let self, self.opening == opening, self.panel.isVisible, self.field.stringValue.isEmpty else { return }
                self.suggestion = .copiedLink
            }
        }
    }

    private static func link(on pasteboard: NSPasteboard) -> Suggestion {
        pasteboard.string(forType: .string).flatMap(AddressInput.address(from:)).map(Suggestion.link) ?? .none
    }

    private func updateHint() {
        let text: String
        switch suggestion {
        case let .link(url): text = url.absoluteString
        case .copiedLink: text = "Press Tab to paste the copied link"
        case .none: text = Self.placeholder
        }
        field.placeholderAttributedString = Self.placeholderText(text)
        // What Return does, as a button (like Dia's own: Go for an address, Google for a search, Go for a chosen page);
        // or, with nothing typed, the tab key for the copied link. Either can be clicked.
        let rowChosen = isExpanded && results.indices.contains(table.selectedRow)
        if rowChosen || !field.stringValue.isEmpty {
            let search = !rowChosen && AddressInput.address(from: field.stringValue) == nil
            keyCap.style = .button
            keyCap.label = search ? "Google" : "Go"
            keyCap.symbol = "↩"
            keyCap.fontSize = 12
        } else if suggestion != .none {
            keyCap.style = .keycap
            keyCap.label = "tab"
            keyCap.symbol = nil
            keyCap.fontSize = 11
        }
        keyCap.isHidden = !rowChosen && field.stringValue.isEmpty && suggestion == .none
        keyCapWidth.constant = max(40, keyCap.labelWidth + (keyCap.style == .button ? 20 : 18))
        fieldToKeyCap.isActive = !keyCap.isHidden
        fieldToEdge.isActive = keyCap.isHidden
    }

    /// Placeholder text in the field's font; a long link ends in "…".
    private static func placeholderText(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.placeholderTextColor, .paragraphStyle: style,
        ])
    }

    // MARK: Window

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as? NSTextField) === field ? fieldEditor : nil
    }

    /// Clicking anywhere else cancels, like Spotlight.
    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { dismiss() }
    }

    private static func shadow(blur: CGFloat, offset: CGFloat, opacity: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: offset)
        shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
        return shadow
    }

    /// A resizable rounded rectangle for a background's mask.
    fileprivate static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func dismiss() {
        onSubmit = nil
        opening += 1
        panel.orderOut(nil)
    }
}

/// One step of an animation: `step` gets the eased progress, 0 to 1, on each frame.
@MainActor
private struct AnimationStage {
    let duration: CFTimeInterval
    let step: (CGFloat) -> Void

    /// Runs the stages one after another, then `done`. Invalidate the returned timer to stop where it is.
    static func run(_ stages: [AnimationStage], done: @escaping () -> Void) -> Timer {
        var index = 0, began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            MainActor.assumeIsolated {
                while index < stages.count {
                    let stage = stages[index]
                    let t = min((CACurrentMediaTime() - began) / stage.duration, 1)
                    // Ease in and out, so the stages flow into each other.
                    let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                    stage.step(CGFloat(eased))
                    guard t >= 1 else { return }
                    index += 1
                    began = CACurrentMediaTime()
                }
                timer.invalidate()
                done()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

/// Lays out from the top, so the box stays at the top of the panel as it grows.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The Recent tab under the box, and the list it pulls down. One shape in the box's material: the list, as wide as
/// `listWidth`, with straight sides and rounded bottom corners, and the tab hanging from its middle, its shoulders
/// curving into the list's bottom edge (into the box's, with the list hidden). Both reach `tuck` points up behind the
/// box. The tab reads "Show recent ↓" and opens the list; with the list showing, "Hide recent ↑" closes it.
private final class RecentButton: NSVisualEffectView {
    var onClick: (() -> Void)?
    private let tab: NSSize
    private let listWidth: CGFloat
    private let listCorner: CGFloat
    private let tuck: CGFloat
    private let title = NSTextField(labelWithString: "Show recent")
    private let key = KeyCapView(label: "↓", fontSize: 9)
    private var labelPosition: NSLayoutConstraint!
    private var pulled: CGFloat = 0
    private var isExpanded = false

    init(tab: NSSize, listWidth: CGFloat, listCorner: CGFloat, tuck: CGFloat) {
        self.tab = tab
        self.listWidth = listWidth
        self.listCorner = listCorner
        self.tuck = tuck
        super.init(frame: .zero)
        material = .popover
        state = .active

        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor
        let label = NSStackView(views: [title, key])
        label.spacing = 4
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        labelPosition = label.centerYAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            labelPosition,
            key.widthAnchor.constraint(equalToConstant: 16),
            key.heightAnchor.constraint(equalToConstant: 15),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setExpanded(false)
        setPulled(0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        title.stringValue = expanded ? "Hide recent" : "Show recent"
        key.label = expanded ? "↑" : "↓"
        toolTip = expanded ? "Hide recent pages (↑)" : "Pages opened in little windows (↓)"
        setAccessibilityLabel(expanded ? "Hide recent pages" : "Recent pages")
    }

    /// Shows `height` of the list above the tab.
    func setPulled(_ height: CGFloat) {
        pulled = height
        labelPosition.constant = tuck + height + tab.height / 2
        maskImage = shape()
        window?.invalidateCursorRects(for: self)
    }

    /// The tab's area, in this view's coordinates.
    private var tabRect: NSRect {
        let top = tuck + pulled, y = isFlipped ? top : bounds.height - top - tab.height
        return NSRect(x: (listWidth - tab.width) / 2, y: y, width: tab.width, height: tab.height)
    }

    private func shape() -> NSImage {
        let tab = self.tab, listWidth = self.listWidth, pulled = self.pulled, edge = tuck + pulled, fullCorner = listCorner
        return NSImage(size: NSSize(width: listWidth, height: edge + tab.height), flipped: true) { _ in
            // Shoulders and bottom corners alike, each half the tab's height, so each shoulder flows straight into the
            // corner below it.
            let corner = tab.height / 2, shoulder = corner, k: CGFloat = 0.45
            // The list's bottom corners, no rounder than the list is tall.
            let listCorner = min(fullCorner, max(pulled, 0))
            let left = (listWidth - tab.width) / 2, right = left + tab.width, bottom = edge + tab.height
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: 0))
            path.line(to: NSPoint(x: listWidth, y: 0))
            path.line(to: NSPoint(x: listWidth, y: edge - listCorner))
            path.curve(to: NSPoint(x: listWidth - listCorner, y: edge), controlPoint1: NSPoint(x: listWidth, y: edge - listCorner * k),
                       controlPoint2: NSPoint(x: listWidth - listCorner * k, y: edge))
            path.line(to: NSPoint(x: right, y: edge))
            path.curve(to: NSPoint(x: right - shoulder, y: edge + shoulder), controlPoint1: NSPoint(x: right - shoulder * k, y: edge),
                       controlPoint2: NSPoint(x: right - shoulder, y: edge + shoulder * k))
            path.line(to: NSPoint(x: right - shoulder, y: bottom - corner))
            path.curve(to: NSPoint(x: right - shoulder - corner, y: bottom), controlPoint1: NSPoint(x: right - shoulder, y: bottom - corner * k),
                       controlPoint2: NSPoint(x: right - shoulder - corner * k, y: bottom))
            path.line(to: NSPoint(x: left + shoulder + corner, y: bottom))
            path.curve(to: NSPoint(x: left + shoulder, y: bottom - corner), controlPoint1: NSPoint(x: left + shoulder + corner * k, y: bottom),
                       controlPoint2: NSPoint(x: left + shoulder, y: bottom - corner * k))
            path.line(to: NSPoint(x: left + shoulder, y: edge + shoulder))
            path.curve(to: NSPoint(x: left, y: edge), controlPoint1: NSPoint(x: left + shoulder, y: edge + shoulder * k),
                       controlPoint2: NSPoint(x: left + shoulder * k, y: edge))
            path.line(to: NSPoint(x: listCorner, y: edge))
            path.curve(to: NSPoint(x: 0, y: edge - listCorner), controlPoint1: NSPoint(x: listCorner * k, y: edge),
                       controlPoint2: NSPoint(x: 0, y: edge - listCorner * k))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
    }

    /// A pointing hand over the tab, as over the box's other buttons.
    override func resetCursorRects() {
        addCursorRect(tabRect, cursor: .pointingHand)
    }

    /// The tab is the button; with the list showing, the rest goes to the rows.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, frame.contains(point) else { return nil }
        if tabRect.contains(convert(point, from: superview)) { return self }
        return isExpanded ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if tabRect.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// A row in the Recent list, on one line: the page's title (or its site), then its address, which gives way first when
/// space runs out, and how long ago it was open.
private final class RecentCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("recent")
    /// From the row's edge to its text.
    static let textInset: CGFloat = 8
    private let title = NSTextField(labelWithString: "")
    private let address = NSTextField(labelWithString: "")
    private let age = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        address.font = .systemFont(ofSize: 12)
        address.textColor = .secondaryLabelColor
        address.lineBreakMode = .byTruncatingTail
        age.font = .systemFont(ofSize: 11)
        age.textColor = .secondaryLabelColor
        // The age always shows; the address shrinks before the title does.
        let priorities: [(NSTextField, NSLayoutConstraint.Priority)] = [(age, .required), (title, .defaultHigh), (address, .defaultLow)]
        for (field, priority) in priorities {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentCompressionResistancePriority(priority, for: .horizontal)
            field.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(field)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.textInset),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            // A long title still leaves room for some of the address.
            title.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.6),
            address.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            address.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            address.trailingAnchor.constraint(lessThanOrEqualTo: age.leadingAnchor, constant: -10),
            age.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.textInset),
            age.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ entry: RecentPages.Entry, now: Date) {
        title.stringValue = entry.displayTitle
        address.stringValue = Self.shortAddress(entry.url)
        age.stringValue = Self.age(of: entry.date, now: now)
    }

    /// The address without `https://` and `www.`.
    private static func shortAddress(_ url: String) -> String {
        var text = url
        for prefix in ["https://", "http://", "www."] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        return text
    }

    /// "Now", "5m", "3h", "Yesterday", or the date.
    private static func age(of date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Shows the chosen row in the accent colour, as if the list had focus: typing stays in the field, so the list never
/// actually does.
private final class EmphasizedRowView: NSTableRowView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    /// Rounded to sit concentric inside the list's corners.
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
}

/// Dia's logo in flat grey, the placeholder text's colour. The shape comes from Dia's own flat logo, so none of Dia's
/// artwork is bundled here; without it, a magnifying glass.
private final class DiaLogoView: NSView {
    /// The shape, and the part of the image it fills (Dia's file pads the logo top and bottom).
    private let shape: (image: NSImage, crop: NSRect)?

    override init(frame: NSRect) {
        let logo = NSWorkspace.shared.urlForApplication(withBundleIdentifier: BrowserAdapter.dia.bundleID)?
            .appendingPathComponent("Contents/Resources/web-chat-resources/dist/provider-icons/dia.svg")
        if let logo, let image = NSImage(contentsOf: logo), image.size == NSSize(width: 86, height: 86) {
            shape = (image, NSRect(x: 0, y: 8, width: 86, height: 70))
        } else if let glass = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium)) {
            shape = (glass, NSRect(origin: .zero, size: glass.size))
        } else {
            shape = nil
        }
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Dia")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Blends with the box's background the way the placeholder text does, so the two greys match.
    override var allowsVibrancy: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let shape, let context = NSGraphicsContext.current?.cgContext else { return }
        // Fit the shape's crop in the view, keeping its proportions.
        let scale = min(bounds.width / shape.crop.width, bounds.height / shape.crop.height)
        let size = NSSize(width: shape.crop.width * scale, height: shape.crop.height * scale)
        let target = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        let whole = NSRect(x: target.minX - shape.crop.minX * scale, y: target.minY - shape.crop.minY * scale,
                           width: shape.image.size.width * scale, height: shape.image.size.height * scale)

        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        NSColor.placeholderTextColor.setFill()
        target.fill()
        shape.image.draw(in: whole, from: .zero, operation: .destinationIn, fraction: 1)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

/// A small keyboard key in line art: an outline with a thicker bottom edge, so it reads as a key to press without
/// shading. The face stays clear, so the box's background shows through.
private final class KeyCapView: NSView {
    var label: String { didSet { needsDisplay = true } }

    var labelWidth: CGFloat {
        var width = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]).size().width
        if style == .button, let symbol {
            width += Self.symbolGap + NSAttributedString(string: symbol, attributes: [.font: NSFont.systemFont(ofSize: fontSize)]).size().width
        }
        return ceil(width)
    }
    var fontSize: CGFloat { didSet { needsDisplay = true } }
    /// A keyboard key in line art (a hint), or a flat solid button.
    enum Style { case keycap, button }
    var style = Style.keycap { didSet { needsDisplay = true } }
    /// A button's symbol after its label (↩), centred on its own shape.
    var symbol: String? { didSet { needsDisplay = true } }
    private static let symbolGap: CGFloat = 4
    /// Makes the key a button: a pointing hand over it, and it looks pressed while held.
    var onClick: (() -> Void)? {
        didSet {
            window?.invalidateCursorRects(for: self)
            setAccessibilityElement(onClick != nil)
            setAccessibilityRole(onClick != nil ? .button : nil)
        }
    }
    private var isPressed = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }

    /// Hover shows even though Little Dia isn't the active app (the box doesn't activate it).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        if onClick != nil { isHovered = true }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override var isHidden: Bool {
        didSet { if isHidden { isHovered = false } }
    }

    init(label: String, fontSize: CGFloat = 11) {
        self.label = label
        self.fontSize = fontSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    /// Flat and solid: dark grey with white text in light mode, light grey with dark text in dark mode.
    private func drawButton() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = NSColor(white: dark ? (isPressed ? 0.7 : 0.8) : (isPressed ? 0.18 : 0.3), alpha: 1)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        let color = dark ? NSColor(white: 0.1, alpha: 1) : NSColor.white
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: color,
        ])
        let textSize = text.size()
        let left = bounds.midX - labelWidth / 2
        text.draw(at: NSPoint(x: left, y: bounds.midY - textSize.height / 2))
        guard let symbol, let context = NSGraphicsContext.current?.cgContext else { return }
        // The symbol is centred on its own shape: its line box would put it off the middle.
        let mark = NSAttributedString(string: symbol, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(mark)
        // Measured from the origin: the bounds are offset by wherever the text position was left.
        context.textMatrix = .identity
        context.textPosition = .zero
        let ink = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: left + textSize.width + Self.symbolGap - ink.minX, y: bounds.midY - ink.midY)
        CTLineDraw(line, context)
    }

    override func resetCursorRects() {
        if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        onClick == nil ? nil : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        onClick?()
    }

    override func accessibilityLabel() -> String? {
        label
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return onClick != nil
    }

    override func draw(_ dirtyRect: NSRect) {
        if style == .button { return drawButton() }
        // Pressed, the key goes down: its top drops and its thick bottom edge thins, so the face sits lower.
        let radius: CGFloat = 5, line: CGFloat = 1, edge: CGFloat = isPressed ? 1 : 3
        var key = bounds.insetBy(dx: 0.5, dy: 0.5)
        if isPressed { key.size.height -= 2 }
        let face = NSRect(x: key.minX + line, y: key.minY + edge, width: key.width - 2 * line, height: key.height - edge - line)

        // The key minus its face: thin at the top and sides, thick along the bottom.
        let outline = NSBezierPath(roundedRect: key, xRadius: radius, yRadius: radius)
        outline.append(NSBezierPath(roundedRect: face, xRadius: radius - line, yRadius: radius - line))
        outline.windingRule = .evenOdd
        NSColor.tertiaryLabelColor.setFill()
        outline.fill()
        // Hovered (and held), the face lightens.
        if isHovered || isPressed {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSColor.white.withAlphaComponent(dark ? 0.12 : 0.6).setFill()
            NSBezierPath(roundedRect: face, xRadius: radius - line, yRadius: radius - line).fill()
        }

        let color = NSColor.secondaryLabelColor
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: color,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
        if let symbol = label.first, label.count == 1, !symbol.isLetter, let context = NSGraphicsContext.current?.cgContext {
            // A symbol (↩, ↓, ↑): centre its shape, which sits off the middle of its line.
            let line = CTLineCreateWithAttributedString(text)
            context.textMatrix = .identity
            context.textPosition = .zero   // the bounds are offset by wherever the text position was left
            let ink = CTLineGetImageBounds(line, context)
            context.textPosition = CGPoint(x: face.midX - ink.midX, y: face.midY - ink.midY)
            CTLineDraw(line, context)
        } else {
            let size = text.size()
            text.draw(at: NSPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2))
        }
    }
}

/// A borderless panel doesn't take typing unless it says it can. It also handles the editing shortcuts itself: a
/// menu-bar app has no Edit menu, which is what normally turns ⌘V and the rest into actions.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    /// Told about each click, in window coordinates, before it's handled.
    var onMouseDown: ((NSPoint) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown?(event.locationInWindow) }
        super.sendEvent(event)
    }

    private static let editing: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")), "Z": Selector(("redo:")),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if modifiers == .command || modifiers == [.command, .shift], let key = event.charactersIgnoringModifiers,
           let action = Self.editing[modifiers.contains(.shift) ? key.uppercased() : key.lowercased()],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
