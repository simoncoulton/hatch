import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Borderless panel that can take keyboard focus without activating the app, and routes
/// navigation keys to the model before the text field sees them.
final class HatchPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var onResign: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = HatchModel()
    private var panel: HatchPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var panelTop: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()
        model.hide = { [weak self] in self?.hide() }
        model.onHotkeyChange = { [weak self] in self?.registerHotKey() }
        model.suspendHotkey = { [weak self] in self?.hotKey = nil }
        if let q = ProcessInfo.processInfo.environment["HATCH_DEBUG_QUERY"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.show()
                if let o = ProcessInfo.processInfo.environment["HATCH_DEBUG_OPACITY"], let v = Double(o) { self.model.setOpacity(v) }
                for (i, ch) in q.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(i)) { self.model.query += String(ch) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 + 0.15 * Double(q.count)) {
                FileHandle.standardError.write(Data("top=\(self.model.results.first?.id ?? "-") kind=\(self.model.results.first?.kind ?? "-") q=\(self.model.query) rows=\(self.model.results.count) expectedH=\(Layout.height(forRows: self.model.results.count)) frame=\(self.panel.frame)\n".utf8))
            }
        }
        Config.seedIfNeeded()
        registerHotKey()
        if ProcessInfo.processInfo.environment["HATCH_DEBUG_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showSettings() }
        }
    }

    private var settingsWindow: NSWindow?
    private var registeredHotkey = ""

    /// Picks up an edited `hotkey` without needing Reload Config.
    private func refreshHotKeyIfChanged() {
        if (Config.value("hotkey") ?? Config.defaultHotkey) != registeredHotkey { registerHotKey() }
    }

    /// (Re)reads `hotkey` from config.yml. A bad or taken combination falls back to the default.
    private func registerHotKey() {
        hotKey = nil
        let requested = Config.value("hotkey") ?? Config.defaultHotkey
        registeredHotkey = requested
        for text in [requested, Config.defaultHotkey] {
            guard let spec = Config.parseHotkey(text),
                  let key = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers, onPress: { [weak self] in
                      DispatchQueue.main.async { self?.toggle() }
                  }) else { continue }
            hotKey = key
            model.hotkeyStatus = text == requested ? "" : "“\(requested)” is invalid or already in use, so \(Config.pretty(text)) is active."
            return
        }
        model.hotkeyStatus = "No shortcut is active."
    }

    // MARK: Panel

    private func buildPanel() {
        panel = HatchPanel(
            contentRect: NSRect(origin: .zero, size: Layout.windowSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // the card draws its own shadow
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: HatchView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.onResign = { [weak self] in self?.hide() }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let ctrl = event.modifierFlags.contains(.control)
        // No Edit menu in a menu-bar app, so route the standard text shortcuts by hand.
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: .command),
           !event.modifierFlags.contains(.option) {
            let shift = event.modifierFlags.contains(.shift)
            let action: Selector?
            switch Int(event.keyCode) {
            case kVK_ANSI_A: action = #selector(NSText.selectAll(_:))
            case kVK_ANSI_C: action = #selector(NSText.copy(_:))
            case kVK_ANSI_V: action = #selector(NSText.paste(_:))
            case kVK_ANSI_X: action = #selector(NSText.cut(_:))
            case kVK_ANSI_Z: action = Selector(shift ? "redo:" : "undo:")
            default: action = nil
            }
            if let action { return NSApp.sendAction(action, to: nil, from: nil) }
        }
        switch Int(event.keyCode) {
        case kVK_DownArrow: model.move(1)
        case kVK_UpArrow: model.move(-1)
        case kVK_ANSI_N where ctrl: model.move(1)
        case kVK_ANSI_P where ctrl: model.move(-1)
        case kVK_Tab:
            guard model.results.indices.contains(model.selection), let next = model.results[model.selection].completion else { return true }
            model.query = next
        case kVK_Delete where model.query.isEmpty && model.scope != nil: model.clearScope()
        case kVK_Escape:
            if model.scope != nil { model.clearScope() } else { hide() }
        case kVK_Return, kVK_ANSI_KeypadEnter: model.activate()
        default: return false
        }
        return true
    }

    private func toggle() { panel.isVisible ? hide() : show() }

    private func show() {
        model.prepare()
        refreshHotKeyIfChanged()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        panelTop = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.18
        let size = Layout.windowSize
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: panelTop + Layout.pad - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusTick += 1
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.reset()
    }

    // MARK: Menu bar and settings

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Hatch")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Settings all live in the Settings window; the menu is just actions.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshHotKeyIfChanged()
        menu.removeAllItems()
        menu.addItem(withTitle: "Show Hatch", action: #selector(showFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Config File", action: #selector(openConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Scripts Folder", action: #selector(openScripts), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Themes Folder", action: #selector(openThemes), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func showFromMenu() { DispatchQueue.main.async { self.show() } }

    @objc private func showSettings() {
        model.refreshCandidates()
        model.loadConfig()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Hatch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openConfig() { Config.openFile() }
    @objc private func openScripts() { Scripts.openFolder() }
    @objc private func openThemes() { Themes.openFolder() }
}
