import AppKit

@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private var p = Pomodoro()
    private let defaults = UserDefaults.standard
    private var activity: NSObjectProtocol?

    private var item: NSStatusItem!
    private let startItems: [NSMenuItem] = Pomodoro.lengths.map {
        let i = NSMenuItem(title: "Start \($0) min", action: #selector(start(_:)), keyEquivalent: "")
        i.tag = $0
        return i
    }
    private let stopItem = NSMenuItem(title: "Stop", action: #selector(stop), keyEquivalent: "")
    private let breakItem = NSMenuItem(title: "Start Break", action: #selector(startBreak), keyEquivalent: "")
    private let windowItem = NSMenuItem(title: "Show Window", action: #selector(toggleWindow), keyEquivalent: "")

    private var panel: NSPanel!
    private let timeLabel = NSTextField(labelWithString: "")
    private let infoLabel = NSTextField(labelWithString: "")
    private let startButtons: [NSButton] = Pomodoro.lengths.map {
        let b = NSButton(title: "\($0)", target: nil, action: #selector(start(_:)))
        b.tag = $0
        return b
    }
    private let stopButton = NSButton(title: "Stop", target: nil, action: #selector(stop))
    private let breakButton = NSButton(title: "Break", target: nil, action: #selector(startBreak))
    private let taskField = NSTextField(string: "")  // current focus task, in the empty strip beside the close button

    private var dialogs: [NSPanel] = []  // "pomodoro finished", one per display

    func applicationDidFinishLaunching(_ note: Notification) {
        // A second copy would fight over the saved state.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        defaults.register(defaults: ["windowVisible": true])
        if let data = defaults.data(forKey: "state"), let s = try? JSONDecoder().decode(State.self, from: data) {
            p.s = s
        }
        // Keep ticking on time in the background (no App Nap); idle sleep is still allowed.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Pomodoro countdown")

        buildMenu()
        buildPanel()

        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(tick(_:)), userInfo: nil, repeats: true)
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)  // .common keeps it running while the menu is open
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(tick(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        tick(nil)
    }

    private func buildMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

        let menu = NSMenu()
        menu.autoenablesItems = false
        for i in startItems + [breakItem, stopItem] { menu.addItem(i) }
        menu.addItem(.separator())
        menu.addItem(windowItem)
        menu.addItem(NSMenuItem(title: "Reset Count", action: #selector(resetCount), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for i in menu.items { i.target = self }
        item.menu = menu
    }

    private func buildPanel() {
        let size = NSSize(width: 220, height: 130)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .light)
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabelColor
        for b in startButtons + [stopButton, breakButton] {
            b.bezelStyle = .rounded
            b.target = self
        }

        let buttons = NSStackView(views: startButtons + [stopButton, breakButton])
        buttons.setHuggingPriority(.defaultHigh, for: .horizontal)  // shrink to the visible buttons so they stay centered
        let stack = NSStackView(views: [timeLabel, infoLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        taskField.stringValue = defaults.string(forKey: "task") ?? ""
        taskField.placeholderString = "What are you working on?"
        taskField.font = .systemFont(ofSize: 12)
        taskField.alignment = .center
        taskField.isBordered = false
        taskField.drawsBackground = false
        taskField.focusRingType = .none
        taskField.usesSingleLineMode = true
        taskField.lineBreakMode = .byTruncatingTail
        taskField.delegate = self
        taskField.target = self
        taskField.action = #selector(taskEntered)
        taskField.translatesAutoresizingMaskIntoConstraints = false

        let content = panel.contentView!
        content.addSubview(stack)
        content.addSubview(taskField)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: 6),
            taskField.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            taskField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            taskField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
        ])

        panel.center()
        panel.setFrameAutosaveName("PomodoroWindow")  // restores the saved position, if any
        panel.setContentSize(size)                    // ...but never an old size
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.center()  // saved position was on a disconnected display
        }
        if defaults.bool(forKey: "windowVisible") { panel.orderFrontRegardless() }
        panel.makeFirstResponder(nil)  // the window would otherwise start editing the task field on first show
    }

    @objc private func tick(_ sender: Any?) {
        let before = p.s
        if let last = p.tick(now: Date()).last {
            NSSound(named: last == .focusDone ? "Glass" : "Hero")?.play()
        }
        if p.s != before { save() }
        render()
    }

    private func render() {
        let left = clock(p.secondsLeft(now: Date()))
        let count = "\(p.s.count)/\(goal)"
        let (bar, time, info, color): (String, String, String, NSColor)
        switch p.s.phase {
        case .idle: (bar, time, info, color) = ("🍅 \(count)", "--:--", "\(count) today", .secondaryLabelColor)
        case .focus: (bar, time, info, color) = ("🍅 \(left)  \(count)", left, "Focus · \(count)", .systemRed)
        case .finished: (bar, time, info, color) = ("✅ \(count)", "Done", "Finished · \(count)", .labelColor)
        case .shortBreak: (bar, time, info, color) = ("☕ \(left)  \(count)", left, "Break · \(count)", .systemGreen)
        case .longBreak: (bar, time, info, color) = ("☕ \(left)  \(count)", left, "Long break · \(count)", .systemGreen)
        }
        item.button?.title = bar
        timeLabel.stringValue = time
        timeLabel.textColor = color
        infoLabel.stringValue = info

        let phase = p.s.phase
        for b in startButtons { b.isHidden = phase != .idle }
        stopButton.isHidden = phase == .idle
        stopButton.title = phase == .focus ? "Stop" : phase == .finished ? "Skip" : "Skip Break"
        breakButton.isHidden = phase != .finished
        for i in startItems { i.isHidden = phase != .idle }
        breakItem.isHidden = phase != .finished
        breakItem.title = breakTitle
        stopItem.isHidden = phase == .idle
        stopItem.title = phase == .focus ? "Stop (restart pomodoro)" : "Skip Break"
        windowItem.title = panel.isVisible ? "Hide Window" : "Show Window"

        if phase == .finished, dialogs.isEmpty { showDialogs() }
        if phase != .finished, !dialogs.isEmpty { closeDialogs() }
    }

    private var breakTitle: String { "Start \(Int(p.nextBreak / 60)) min Break" }

    /// Shown on every display so it can't be missed; answering any copy closes them all.
    private func showDialogs() {
        let mouse = NSEvent.mouseLocation
        dialogs = NSScreen.screens.map { screen in
            let d = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            d.titlebarAppearsTransparent = true
            d.titleVisibility = .hidden
            d.isMovableByWindowBackground = true
            d.level = .modalPanel
            d.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            d.hidesOnDeactivate = false
            d.isReleasedWhenClosed = false
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                d.standardWindowButton(b)?.isHidden = true
            }

            let title = NSTextField(labelWithString: "Pomodoro finished")
            title.font = .systemFont(ofSize: 22, weight: .semibold)
            let info = NSTextField(labelWithString: "\(p.s.count)/\(goal) today. Take a break?")
            info.textColor = .secondaryLabelColor
            let skip = NSButton(title: "Skip Break", target: self, action: #selector(stop))
            skip.keyEquivalent = "\u{1b}"  // Esc
            let rest = NSButton(title: breakTitle, target: self, action: #selector(startBreak))
            rest.keyEquivalent = "\r"
            let stack = NSStackView(views: [title, info, NSStackView(views: [skip, rest])])
            stack.orientation = .vertical
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            let content = d.contentView!
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])

            let f = screen.visibleFrame
            d.setFrameOrigin(NSPoint(x: f.midX - d.frame.width / 2, y: f.midY - d.frame.height / 2))
            // Keyboard (Return / Esc) goes to the copy on the display you're looking at.
            if NSMouseInRect(mouse, screen.frame, false) { d.makeKeyAndOrderFront(nil) } else { d.orderFrontRegardless() }
            return d
        }
    }

    private func closeDialogs() {
        dialogs.forEach { $0.close() }
        dialogs = []
    }

    /// Display added or removed: rebuild the dialogs for the new set of screens.
    @objc private func screensChanged() {
        closeDialogs()
        render()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(p.s) { defaults.set(data, forKey: "state") }
    }

    private func changed() {
        save()
        render()
    }

    @objc private func start(_ sender: Any) {
        guard let minutes = (sender as? NSMenuItem)?.tag ?? (sender as? NSButton)?.tag else { return }
        p.start(minutes: minutes, now: Date())
        changed()
    }
    @objc private func startBreak() { p.startBreak(now: Date()); changed() }
    @objc private func stop() { p.stop(); changed() }
    @objc private func resetCount() { p.resetCount(now: Date()); changed() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleWindow() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        defaults.set(panel.isVisible, forKey: "windowVisible")
        render()
    }

    func controlTextDidChange(_ note: Notification) {
        defaults.set(taskField.stringValue, forKey: "task")
    }

    /// Return finishes editing.
    @objc private func taskEntered() { panel.makeFirstResponder(nil) }

    func windowWillClose(_ note: Notification) {
        defaults.set(false, forKey: "windowVisible")
        DispatchQueue.main.async { self.render() }  // isVisible is still true during this callback
    }
}
