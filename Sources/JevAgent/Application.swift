import AppKit
import Carbon
import JevCore

final class CandidatePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onKey: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

final class Application: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let settings = Settings()
    private let hotKey = HotKey()
    private var bridge: ModelBridge!
    private var store: HistoryStore!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var ownChange: Int?
    private var target: TargetSnapshot?
    private var session = NativeSession()
    private var requestSession: NativeSession.RequestToken?
    private var targetInvalid: Bool { !session.isOpen }
    private var captureEpoch = 0
    private var captureFinished = false
    private var pasteInFlight: Bool { session.pasteInFlight }
    private var pendingPastePID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let demo = CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--demo-live")
    private var panel: CandidatePanel!
    private let search = NSSearchField()
    private let table = NSTableView()
    private let preview = NSTextView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private let providerLabel = NSTextField(labelWithString: "")
    private var entries: [ClipboardEntry] = []
    private var candidates: [ClipboardEntry] = []
    private var touched: Bool { session.hasManualSelection }
    private var pasteButton: NSButton!
    private var settingsWindow: NSWindow?
    private var providerPicker: NSPopUpButton!
    private var modelField: NSTextField!
    private var keyField: NSSecureTextField!
    private var pauseCheck: NSButton!
    private var excludedField: NSTextField!
    private var keyPicker: NSPopUpButton!
    private var modifierPicker: NSPopUpButton!
    private var settingsStatus: NSTextField!
    private var permissionLabel: NSTextField?
    private var lastPrune = Date.distantPast
    private var demoLive: Bool { CommandLine.arguments.contains("--demo-live") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let directory = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("jev-agent-demo-\(ProcessInfo.processInfo.processIdentifier)") :
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Jev agent/history")
            store = try HistoryStore(directory: directory)
            if demo {
                for text in ["https://example.com/project", "123 Sample Street\nExample City", "Alex Chen", "alex.chen@example.com"] {
                    _ = try store.add(text: text, sourceApp: "Demo", sourceBundleID: "demo")
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot open clipboard history"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        buildPanel()
        buildMenu()
        bridge = ModelBridge(settings: settings)
        bridge.onStatus = { [weak self] message in
            guard let self else { return }
            self.status.stringValue = message
            if message.hasPrefix("Ready.") { self.attemptDecision() }
        }
        bridge.onResult = { [weak self] selected, error in self?.receive(selected: selected, error: error) }
        hotKey.action = { [weak self] in self?.showPanel() }
        if !hotKey.register(key: settings.shortcutKey, modifiers: settings.shortcutModifiers) {
            status.stringValue = "Shortcut already in use. Open Settings to choose another."
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.captureClipboard() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            if self.demo && !self.demoLive { return }
            if self.pasteInFlight && app.processIdentifier != self.pendingPastePID { self.invalidatePaste() }
            guard self.panel.isVisible else { return }
            self.session.invalidate()
            self.captureEpoch += 1
            self.invalidatePaste()
            self.bridge.cancel()
            self.status.stringValue = "Target changed. Copy this item or open the panel again."
            self.pasteButton.isEnabled = false
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            try? self?.store.prune()
        }
        if !demo || demoLive { bridge.start() }
        if CommandLine.arguments.contains("--show") { showPanel() }
    }
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel { captureEpoch += 1; session.invalidate(); invalidatePaste(); bridge.cancel() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        bridge?.stop()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Jev agent")
        let menu = NSMenu()
        for (title, selector, key) in [("Open Jev agent", #selector(openPanel), ""), ("Settings…", #selector(openSettings), ","),
                                       ("Allow Accessibility…", #selector(allowAccessibility), ""), ("Retry model", #selector(retryModel), ""),
                                       ("Quit Jev agent", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        statusItem.menu = menu
    }
    @objc private func openPanel() { showPanel() }
    @objc private func allowAccessibility() {
        Accessibility.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshPermissionStatus() }
    }
    private func refreshPermissionStatus() {
        permissionLabel?.stringValue = AXIsProcessTrusted() ? "Accessibility: Granted" : "Accessibility: Not granted. Copy remains available."
    }
    @objc private func retryModel() { bridge.reconfigure() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func captureClipboard() {
        if Date().timeIntervalSince(lastPrune) > 60 {
            do { try store.prune(); lastPrune = Date() } catch { status.stringValue = "History maintenance failed: \(error.localizedDescription)" }
        }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard !demo, !settings.paused, ownChange != lastChange else { return }
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]) else { return }
        // Only explicit pasteboard provenance can identify the copying application reliably.
        let source = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        let active = NSWorkspace.shared.frontmostApplication
        guard !settings.excluded.contains(source ?? ""), !settings.excluded.contains(active?.bundleIdentifier ?? "") else { return }
        if AXIsProcessTrusted(), let active, let focused = Accessibility.focused(active),
           Accessibility.string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { return }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        do { _ = try store.add(text: text, sourceApp: source, sourceBundleID: source) }
        catch { status.stringValue = "Cannot save history: \(error.localizedDescription)" }
    }
    private func buildPanel() {
        panel = CandidatePanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 590),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Jev agent"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 590, height: 480)
        let content = NSView()
        panel.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
        let heading = NSTextField(labelWithString: "Choose what belongs here")
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        stack.addArrangedSubview(heading)
        providerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        providerLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(providerLabel)
        targetLabel.font = .systemFont(ofSize: 12)
        targetLabel.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(targetLabel)
        search.placeholderString = "Search clipboard history"
        search.delegate = self
        search.setAccessibilityLabel("Search clipboard history")
        stack.addArrangedSubview(search)
        search.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.title = "History"
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 54
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.setAccessibilityLabel("Clipboard history candidates")
        listScroll.documentView = table
        let previewScroll = NSScrollView()
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        preview.frame = NSRect(x: 0, y: 0, width: 300, height: 250)
        preview.minSize = NSSize(width: 0, height: 0)
        preview.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        preview.isVerticallyResizable = true
        preview.isEditable = false
        preview.isSelectable = true
        preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        preview.textContainerInset = NSSize(width: 10, height: 12)
        preview.isHorizontallyResizable = false
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        preview.setAccessibilityLabel("Complete original text")
        previewScroll.documentView = preview
        split.addArrangedSubview(listScroll)
        split.addArrangedSubview(previewScroll)
        stack.addArrangedSubview(split)
        NSLayoutConstraint.activate([split.widthAnchor.constraint(equalTo: stack.widthAnchor), split.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            listScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 220), previewScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)])
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        for (title, action) in [("Settings…", #selector(openSettings)), ("Delete", #selector(deleteSelected)), ("Copy", #selector(copySelected))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            controls.addArrangedSubview(button)
        }
        let space = NSView()
        controls.addArrangedSubview(space)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPanel))
        cancel.bezelStyle = .rounded
        controls.addArrangedSubview(cancel)
        pasteButton = NSButton(title: "Paste", target: self, action: #selector(pasteSelected))
        pasteButton.bezelStyle = .rounded
        pasteButton.keyEquivalent = "\r"
        controls.addArrangedSubview(pasteButton)
        stack.addArrangedSubview(controls)
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let hint = NSTextField(labelWithString: "↑ ↓ Choose    ↵ Confirm    Esc Cancel    ·    Original text, never rewritten")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)
        panel.onKey = { [weak self] event in
            guard let self else { return false }
            if event.keyCode == 53 { self.cancelPanel(); return true }
            if event.keyCode == 125 || event.keyCode == 126 {
                self.session.selectManually()
                let row = max(0, min(self.entries.count - 1, self.table.selectedRow + (event.keyCode == 125 ? 1 : -1)))
                if !self.entries.isEmpty { self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); self.table.scrollRowToVisible(row) }
                return true
            }
            if event.keyCode == 36 || event.keyCode == 76 { self.pasteSelected(); return true }
            return false
        }
    }
    private func showPanel() {
        if panel.isVisible { cancelPanel(); return }
        invalidatePaste()
        bridge.cancel()
        captureEpoch += 1
        let epoch = captureEpoch
        captureFinished = false
        target = nil
        session.open()
        requestSession = nil
        search.stringValue = ""
        try? store.prune()
        entries = visibleHistory(store.entries)
        candidates = []
        providerLabel.stringValue = settings.title + (demo ? "  ·  Demo history; recording paused" : settings.paused ? "  ·  Recording paused" : "  ·  72 hours / 20 MB")
        targetLabel.stringValue = "Reading the focused field…"
        status.stringValue = entries.isEmpty ? "Copy some text while Jev agent is running. Your history will appear here." : "Choose manually while the field context loads."
        table.reloadData()
        if !entries.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updatePreview()
        // 纯演示模式不读取真实前台应用或 AX 属性，适合公开截图。
        if demo && !demoLive {
            captureFinished = true
            targetLabel.stringValue = "Synthetic form › Email address"
            status.stringValue = "Synthetic clipboard entries only. No model run; automatic paste is disabled."
            presentPanel()
            return
        }
        let originalApp = NSWorkspace.shared.frontmostApplication
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = Accessibility.capture(application: originalApp)
            DispatchQueue.main.async {
                guard let self, self.captureEpoch == epoch, !self.targetInvalid else { return }
                self.captureFinished = true
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == originalApp?.processIdentifier else { return }
                self.target = snapshot
                self.candidates = CandidateRanker.shortlist(entries: self.visibleHistory(self.store.entries), context: snapshot?.context.values.joined(separator: " ") ?? "", limit: 6)
                self.targetLabel.stringValue = snapshot.map { ($0.context["application"] ?? "Unknown") + "  ›  " + ($0.context["field_label"].flatMap { $0.isEmpty ? nil : $0 } ?? "Focused field") } ?? "No target field. Copy an item to paste manually."
                self.updatePreview()
                self.presentPanel()
                guard !self.touched else { return }
                if snapshot?.readable == true {
                    self.status.stringValue = "Choose manually while the model loads, or use Retry model from the menu."
                    self.attemptDecision()
                } else { self.status.stringValue = snapshot?.message ?? "No supported text field detected. Copy is available." }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.captureEpoch == epoch, !self.captureFinished else { return }
            self.captureEpoch += 1
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == originalApp?.processIdentifier else { return }
            self.presentPanel()
            self.targetLabel.stringValue = "Field unavailable. Copy an item to paste manually."
            if !self.touched { self.status.stringValue = "Could not read the field within the time limit. Copy is available." }
        }
    }
    private func presentPanel() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }
    private func attemptDecision() {
        guard panel.isVisible, !candidates.isEmpty,
              let target, target.readable, bridge.ready, !demo || demoLive,
              let request = session.beginRequest() else { return }
        requestSession = request
        bridge.decide(context: target.context, candidates: candidates)
    }
    private func invalidatePaste() {
        session.cancelPaste()
        pendingPastePID = nil
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: String(entry.text.unicodeScalars.prefix(180)).replacingOccurrences(of: "\n", with: " ↵ "))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: (entry.sourceApp ?? "Unknown source") + " · " + entry.copiedAt.formatted(date: .omitted, time: .shortened))
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        for view in [label, detail] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7), detail.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            detail.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4), detail.trailingAnchor.constraint(equalTo: label.trailingAnchor)])
        cell.textField = label
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }
    @objc private func rowClicked() { session.selectManually() }
    private func visibleHistory(_ values: [ClipboardEntry]) -> [ClipboardEntry] {
        values.filter { !settings.excluded.contains($0.sourceBundleID ?? "") }
    }
    private var selected: ClipboardEntry? { entries.indices.contains(table.selectedRow) ? entries[table.selectedRow] : nil }
    private func updatePreview() {
        preview.string = selected?.text ?? "Select an item to inspect the complete original text."
        pasteButton?.isEnabled = selected != nil && target?.readable == true && !targetInvalid && (!demo || demoLive)
    }
    func controlTextDidChange(_ obj: Notification) {
        session.selectManually()
        bridge.cancel()
        try? store.prune()
        entries = visibleHistory(store.search(search.stringValue))
        table.reloadData()
        if !entries.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updatePreview()
        status.stringValue = "\(entries.count) history item\(entries.count == 1 ? "" : "s"). Choose the original text to paste."
    }
    private func receive(selected id: String?, error: String?) {
        guard panel.isVisible, let requestSession,
              let disposition = session.resolveRequest(requestSession) else { return }
        if let error { status.stringValue = error; return }
        guard let id, id != "none" else { status.stringValue = "No matching item found. Choose manually or search your history."; return }
        guard candidates.contains(where: { $0.id == id }), let row = entries.firstIndex(where: { $0.id == id }) else {
            status.stringValue = "Invalid model selection. Choose manually."; return
        }
        if disposition == .applySelection { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row) }
        status.stringValue = disposition == .preserveSelection ? "Recommendation received. Your selection was kept." : "Suggested by \(settings.title). Review the original text before pasting."
    }
    @objc private func cancelPanel() { captureEpoch += 1; session.invalidate(); invalidatePaste(); bridge.cancel(); panel.orderOut(nil) }
    private func writeClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ownChange = NSPasteboard.general.changeCount
        lastChange = NSPasteboard.general.changeCount
    }
    @objc private func copySelected() {
        session.selectManually()
        invalidatePaste()
        guard let selected else { return }
        do { try store.prune() } catch { status.stringValue = "Cannot check history: \(error.localizedDescription)"; return }
        guard store.entries.contains(where: { $0.id == selected.id }) else { status.stringValue = "This item has expired. Search again."; return }
        writeClipboard(selected.text)
        bridge.cancel()
        status.stringValue = "Copied original text. Paste it where you need it."
    }
    @objc private func deleteSelected() {
        guard let selected else { return }
        do { try store.delete(id: selected.id); controlTextDidChange(Notification(name: NSText.didChangeNotification)) }
        catch { status.stringValue = "Cannot delete: \(error.localizedDescription)" }
    }
    @objc private func pasteSelected() {
        guard !pasteInFlight, let selected else { return }
        guard !targetInvalid, (!demo || demoLive), let target, target.readable, AXIsProcessTrusted() else { copySelected(); return }
        do { try store.prune() } catch { status.stringValue = "Cannot check history: \(error.localizedDescription)"; return }
        guard store.entries.contains(where: { $0.id == selected.id }) else { status.stringValue = "This item has expired."; return }
        bridge.cancel()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front == ProcessInfo.processInfo.processIdentifier || front == target.application.processIdentifier else {
            status.stringValue = "Target changed. Use Copy or reopen the panel."; return
        }
        invalidatePaste()
        guard let confirmation = session.beginPaste() else { return }
        pendingPastePID = target.application.processIdentifier
        panel.orderOut(nil)
        target.application.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.session.acceptsPaste(confirmation) else { return }
            // Validate AX off the UI thread, then recheck the foreground and generation at submission.
            DispatchQueue.global(qos: .userInitiated).async {
                let matches = Accessibility.matches(target)
                DispatchQueue.main.async {
                    guard self.session.acceptsPaste(confirmation) else { return }
                    guard matches, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier else {
                        self.invalidatePaste()
                        self.status.stringValue = "Paste cancelled: the target or selection changed. Reopen the panel to try again."
                        return
                    }
                    self.writeClipboard(selected.text)
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier else { self.invalidatePaste(); return }
                    let source = CGEventSource(stateID: .combinedSessionState)
                    let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                    let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                    down?.flags = .maskCommand
                    up?.flags = .maskCommand
                    guard self.session.consumePaste(confirmation) else { return }
                    self.pendingPastePID = nil
                    down?.postToPid(target.application.processIdentifier)
                    up?.postToPid(target.application.processIdentifier)
                }
            }
        }
    }
    @objc private func openSettings() {
        captureEpoch += 1
        session.invalidate()
        invalidatePaste()
        bridge.cancel()
        if let settingsWindow { refreshPermissionStatus(); settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Jev agent Settings"
        window.isReleasedWhenClosed = false
        settingsWindow = window
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        func add(_ title: String, _ control: NSView) {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(control)
            control.setAccessibilityLabel(title)
            control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        providerPicker = NSPopUpButton()
        providerPicker.addItems(withTitles: ["Laya · Local", "Jev · Cloud"])
        providerPicker.selectItem(at: settings.provider == "jev" ? 1 : 0)
        add("Decision provider", providerPicker)
        let explanation = NSTextField(wrappingLabelWithString: "Jev sends the focused-field context and up to six candidate excerpts to TypeSafe only when you request a recommendation. Laya runs on this Mac. Providers never switch automatically.")
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        stack.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        modelField = NSTextField(string: settings.model)
        add("Jev model", modelField)
        keyField = NSSecureTextField()
        keyField.placeholderString = "Leave blank to keep the key stored in Keychain"
        add("TypeSafe API key", keyField)
        pauseCheck = NSButton(checkboxWithTitle: "Pause clipboard recording", target: nil, action: nil)
        pauseCheck.state = settings.paused ? .on : .off
        stack.addArrangedSubview(pauseCheck)
        excludedField = NSTextField(string: settings.excluded.sorted().joined(separator: ", "))
        excludedField.placeholderString = "com.example.application, com.example.other"
        add("Excluded applications (comma-separated Bundle IDs)", excludedField)
        keyPicker = NSPopUpButton()
        keyPicker.addItems(withTitles: ["V", "B", "J", "P"])
        let keyCodes: [UInt32] = [9, 11, 38, 35]
        keyPicker.selectItem(at: keyCodes.firstIndex(of: settings.shortcutKey) ?? 0)
        modifierPicker = NSPopUpButton()
        modifierPicker.addItems(withTitles: ["Command + Shift", "Command + Option", "Control + Option"])
        let modifiers = [UInt32(cmdKey | shiftKey), UInt32(cmdKey | optionKey), UInt32(controlKey | optionKey)]
        modifierPicker.selectItem(at: modifiers.firstIndex(of: settings.shortcutModifiers) ?? 0)
        let shortcutRow = NSStackView(views: [modifierPicker, keyPicker])
        shortcutRow.orientation = .horizontal
        add("Global shortcut", shortcutRow)
        settingsStatus = NSTextField(wrappingLabelWithString: "Keys stay in macOS Keychain. History stays on this Mac.")
        settingsStatus.font = .systemFont(ofSize: 12)
        settingsStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(settingsStatus)
        settingsStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let permission = NSTextField(labelWithString: "")
        permission.font = .systemFont(ofSize: 12, weight: .medium)
        permission.setAccessibilityLabel("Accessibility permission status")
        permissionLabel = permission
        refreshPermissionStatus()
        stack.addArrangedSubview(permission)
        let actions = NSStackView(views: [NSButton(title: "Clear history…", target: self, action: #selector(clearHistory)), NSButton(title: "Allow Accessibility…", target: self, action: #selector(allowAccessibility)), NSButton(title: "Save", target: self, action: #selector(saveSettings))])
        stack.addArrangedSubview(actions)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    @objc private func saveSettings() {
        let key = [UInt32(9), 11, 38, 35][keyPicker.indexOfSelectedItem]
        let modifiers = [UInt32(cmdKey | shiftKey), UInt32(cmdKey | optionKey), UInt32(controlKey | optionKey)][modifierPicker.indexOfSelectedItem]
        do {
            if !keyField.stringValue.isEmpty { try Keychain.save(keyField.stringValue) }
        } catch { settingsStatus.stringValue = "Cannot save key: \(error.localizedDescription)"; return }
        if (key != settings.shortcutKey || modifiers != settings.shortcutModifiers), !hotKey.register(key: key, modifiers: modifiers) {
            settingsStatus.stringValue = "Shortcut is already in use. Choose another combination."; return
        }
        keyField.stringValue = ""
        settings.shortcutKey = key
        settings.shortcutModifiers = modifiers
        settings.provider = providerPicker.indexOfSelectedItem == 1 ? "jev" : "laya"
        settings.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.paused = pauseCheck.state == .on
        settings.excluded = Set(excludedField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        bridge.reconfigure()
        providerLabel.stringValue = settings.title
        session.invalidate()
        pasteButton.isEnabled = false
        settingsStatus.stringValue = "Saved. Reopen the recommendation panel to use these settings."
    }
    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Delete all clipboard history?"
        alert.informativeText = "This removes saved history from this Mac. Your current clipboard is unchanged."
        alert.addButton(withTitle: "Delete history")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try store.clear(); entries = []; table.reloadData(); updatePreview(); settingsStatus.stringValue = "History cleared." }
        catch { settingsStatus.stringValue = "Cannot clear history: \(error.localizedDescription)" }
    }
}
