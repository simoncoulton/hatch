import AppKit
import ServiceManagement
import SwiftUI

struct ResultItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let kind: String
    var iconPath: String? = nil
    var symbol: String? = nil
    /// Draws the title large and in the accent color (calculator answers).
    var emphasized = false
    /// Query text that Tab swaps in (folder paths).
    var completion: String? = nil
    /// Keep the panel open after running (choosing a type from the `:` picker).
    var keepOpen = false
    let action: @MainActor () -> Void
}

enum Layout {
    static let width: CGFloat = 660
    static let inputHeight: CGFloat = 60
    /// Vertical padding inside each row; set from config.yml.
    static var rowPadding: CGFloat = 8
    static var rowHeight: CGFloat { 30 + rowPadding * 2 }
    static let maxRows = 10
    /// Gap above and below the rows; matches the 6pt inset at the sides.
    static let listInset: CGFloat = 6

    /// Transparent margin around the card so its shadow isn't clipped by the window.
    static let pad: CGFloat = 24
    static var windowSize: CGSize {
        CGSize(width: width + pad * 2, height: height(forRows: maxRows) + pad * 2)
    }

    static func height(forRows n: Int) -> CGFloat {
        let rows = min(n, maxRows)
        return rows == 0 ? inputHeight : inputHeight + 1 + CGFloat(rows) * rowHeight + listInset * 2
    }
}

/// A result type the user can narrow search to with `:`.
enum Scope: String, CaseIterable {
    case apps, scripts, folders, themes

    var title: String {
        switch self {
        case .apps: "Applications"
        case .scripts: "Scripts"
        case .folders: "Folders"
        case .themes: "Themes"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "app"
        case .scripts: "terminal"
        case .folders: "folder"
        case .themes: "paintpalette"
        }
    }

    var hint: String {
        switch self {
        case .apps: "Browse and search applications"
        case .scripts: "Run one of your scripts"
        case .folders: "Find folders under your home, or type a path"
        case .themes: "Switch the color theme"
        }
    }

    /// Resolves any prefix of the type's name (`:s`, `:scr`, `:apps`); "theme" and "application" work too.
    /// First letters are distinct, so a prefix is never ambiguous.
    static func resolve(_ token: String) -> Scope? {
        let t = token.lowercased()
        guard !t.isEmpty else { return nil }
        return allCases.first { $0.rawValue.hasPrefix(t) || $0.title.lowercased().hasPrefix(t) }
    }
}

@MainActor
final class HatchModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            applyShorthand()
            update()
        }
    }
    /// Active type filter, shown as a chip before the text field.
    @Published var scope: Scope?
    @Published var results: [ResultItem] = []
    @Published var selection = 0
    @Published var theme: Theme
    /// Bumped on every show so the text field regains focus.
    @Published var focusTick = 0

    var themes: [Theme] = Themes.presets

    /// Standalone setting from config.yml, independent of the theme.
    var opacity: Double { opacityOverride ?? Config.defaultOpacity }
    private var opacityOverride: Double?

    func setOpacity(_ raw: Double) {
        let v = (raw * 100).rounded() / 100
        Config.set("opacity", String(v))
        opacityOverride = v
        objectWillChange.send()
    }

    var padding: Double { Double(Layout.rowPadding) }

    // MARK: Settings window

    @Published var hotkeyStatus = ""
    @Published var recordingHotkey = false
    var onHotkeyChange: () -> Void = {}
    var suspendHotkey: () -> Void = {}
    private var recorder: Any?

    var hotkeyText: String { Config.value("hotkey") ?? Config.defaultHotkey }

    /// Listens for the next key combination. The live hotkey is released first, or pressing it would just toggle the panel.
    func startRecordingHotkey() {
        guard !recordingHotkey else { return }
        recordingHotkey = true
        suspendHotkey()
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                if event.keyCode == 53 { self.stopRecordingHotkey(); return nil }
                if let text = Config.hotkeyString(keyCode: Int(event.keyCode), flags: event.modifierFlags) {
                    Config.set("hotkey", text)
                    self.stopRecordingHotkey()
                }
                return nil
            }
        }
    }

    func stopRecordingHotkey() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        recordingHotkey = false
        onHotkeyChange()
    }

    // MARK: Start at login

    /// Shown under the toggle: an approval prompt or the error from macOS.
    @Published var loginMessage = ""
    private var lastLoginSetting: Bool?

    /// The real login item state, since the user can also change it in System Settings.
    var startAtLogin: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    func setStartAtLogin(_ on: Bool) {
        Config.set("start_at_login", on ? "true" : "false")
        lastLoginSetting = on
        applyLogin(on)
    }

    private func applyLogin(_ on: Bool) {
        loginMessage = ""
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginMessage = error.localizedDescription
        }
        if on, SMAppService.mainApp.status == .requiresApproval {
            loginMessage = "Allow Hatch in System Settings > General > Login Items."
        }
        objectWillChange.send()
    }

    /// Applies `start_at_login` from config.yml when it first appears or changes. With the key absent the login item
    /// is left alone, so a switch made in System Settings isn't undone.
    private func syncLoginItem() {
        guard let raw = Config.value("start_at_login")?.lowercased(), raw == "true" || raw == "false" else { return }
        let want = raw == "true"
        guard want != lastLoginSetting else { return }
        lastLoginSetting = want
        if want != startAtLogin { applyLogin(want) }
    }

    var recents: Int { recentCount }

    func setRecents(_ n: Int) {
        Config.set("recents", String(n))
        recentCount = n
        objectWillChange.send()
    }

    private(set) var folderCandidates: [URL] = []
    private(set) var linkCandidates: [URL] = []

    /// Apps macOS says can open a folder / an https link. Looked up when the settings window opens.
    func refreshCandidates() {
        folderCandidates = NSWorkspace.shared.urlsForApplications(toOpen: URL(fileURLWithPath: "/"))
            .filter { $0.path != "/System/Library/CoreServices/Finder.app" }
        linkCandidates = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        reloadThemes()
        objectWillChange.send()
    }

    /// Writes a copy of the current theme to the themes folder as a starting point for your own.
    func saveThemeCopy() {
        let t = theme
        let copy = Theme(name: t.name + " Custom", isDark: t.isDark, background: t.background, surface: t.surface,
                         text: t.text, subtext: t.subtext, accent: t.accent, selection: t.selection,
                         radius: t.radius, rowRadius: t.rowRadius)
        guard let url = try? Themes.save(copy) else { return }
        reloadThemes()
        objectWillChange.send()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// `icons: monochrome` in config.yml tints every icon with the theme accent.
    private(set) var monochromeIcons = false

    /// `recents` in config.yml: how many most-used apps to show for an empty query.
    private var recentCount = 0

    func setMonochromeIcons(_ on: Bool) {
        Config.set("icons", on ? "monochrome" : "color")
        monochromeIcons = on
        objectWillChange.send()
    }

    func setPadding(_ v: Double) {
        Config.set("padding", String(Int(v)))
        Layout.rowPadding = CGFloat(v)
        objectWillChange.send()
    }

    /// Re-reads opacity and padding. Runs on every show, so hand edits apply without a reload.
    func loadConfig() {
        opacityOverride = Config.value("opacity").flatMap(Double.init).map { min(max($0, 0.3), 1) }
        Layout.rowPadding = Config.value("padding").flatMap(Double.init).map { CGFloat(min(max($0, 0), 20)) } ?? 8
        recentCount = Config.value("recents").flatMap(Int.init).map { min(max($0, 0), 10) } ?? 0
        syncLoginItem()
        monochromeIcons = Config.value("icons")?.lowercased() == "monochrome"
        if let name = Config.value("theme"), let t = themes.first(where: { $0.name == name }) { theme = t }
        objectWillChange.send()
    }

    /// App used to open folders (`folder_app` in config.yml); nil means the system default (Finder).
    var folderApp: URL? {
        get { Self.appURL(Config.value("folder_app")) }
        set {
            Config.set("folder_app", newValue?.path)
            objectWillChange.send()
        }
    }

    /// App used to open http(s) links (`link_app`); nil means the system default browser.
    var linkApp: URL? {
        get { Self.appURL(Config.value("link_app")) }
        set {
            Config.set("link_app", newValue?.path)
            objectWillChange.send()
        }
    }

    private static func appURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }
    var hide: () -> Void = {}

    private var apps: [AppEntry] = []
    private var scripts: [ScriptEntry] = []
    private var lastScan = Date.distantPast
    private let defaults = UserDefaults.standard

    init() {
        theme = Themes.presets[0]
        Config.migrateRenamedDirectory()
        Config.seedIfNeeded()
        migrateDefaults()
        importLauncherUsage()
        Config.migrateLegacy("themes")
        Scripts.seedIfNeeded()
        prepare()
    }

    /// Launch counts from when the app was called Launcher (a different preferences domain). Script paths moved too.
    private func importLauncherUsage() {
        guard defaults.dictionary(forKey: "usage") == nil,
              let old = UserDefaults(suiteName: "app.launcher.macos")?.dictionary(forKey: "usage") as? [String: Int] else { return }
        var moved: [String: Int] = [:]
        for (key, count) in old { moved[key.replacingOccurrences(of: "/.config/launcher/", with: "/.config/hatch/")] = count }
        defaults.set(moved, forKey: "usage")
    }

    /// Earlier versions kept the theme and the folder/link apps in macOS preferences; move them into config.yml once.
    private func migrateDefaults() {
        for (old, key) in [("theme", "theme"), ("folderApp", "folder_app"), ("linkApp", "link_app"), ("opacity", "opacity")] {
            guard let stored = defaults.object(forKey: old) else { continue }
            let value = "\(stored)"
            if Config.value(key) == nil { Config.set(key, key == "theme" ? "\"\(value)\"" : value) }
            defaults.removeObject(forKey: old)
        }
    }

    /// Called when the panel hides, so the next show can't flash the previous results.
    func reset() {
        scope = nil
        query = ""
        results = []
        selection = 0
    }

    /// Called before every show: clears the query and refreshes whatever may have changed on disk.
    func prepare() {
        scope = nil
        query = ""
        scripts = Scripts.load()
        reloadThemes()
        loadConfig()
        if Date().timeIntervalSince(lastScan) > 60 {
            lastScan = Date()
            Task.detached {
                let found = AppIndex.scan()
                await MainActor.run { self.apps = found; self.update() }
            }
        }
        update()
    }

    func reloadThemes() {
        themes = Themes.presets + Themes.loadCustom()
        if let current = themes.first(where: { $0.name == theme.name }) { theme = current }
    }

    func setTheme(_ t: Theme) {
        theme = t
        Config.set("theme", "\"\(t.name)\"")
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func activate() {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        if item.keepOpen {
            item.action()
            return
        }
        if item.id.hasPrefix("app:") || item.id.hasPrefix("script:") { bumpUsage(item.id) }
        hide()
        item.action()
    }

    // MARK: Scopes

    func chooseScope(_ s: Scope) {
        scope = s
        let hadText = !query.isEmpty
        query = ""
        if !hadText { update() }
    }

    func clearScope() {
        scope = nil
        update()
    }

    /// ":scripts lock" becomes the Scripts chip plus the text "lock". Needs the trailing space, so ":s" alone
    /// still shows the picker. Assigning inside didSet doesn't re-trigger it, so the caller runs update().
    private func applyShorthand() {
        guard scope == nil, query.hasPrefix(":"), let space = query.firstIndex(of: " ") else { return }
        let token = String(query[query.index(after: query.startIndex)..<space])
        guard let s = Scope.resolve(token) else { return }
        scope = s
        query = String(query[query.index(after: space)...])
    }

    private func pickerResults(_ typed: String) -> [ResultItem] {
        let t = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return Scope.allCases.filter { t.isEmpty || Scope.resolve(t) == $0 }.map { s in
            ResultItem(id: "scope:" + s.rawValue, title: s.title, subtitle: s.hint, kind: "Type", symbol: s.symbol,
                       completion: ":" + s.rawValue + " ", keepOpen: true) { [weak self] in self?.chooseScope(s) }
        }
    }

    private func scopedResults(_ s: Scope, _ q: String) -> [ResultItem] {
        let used = usage
        switch s {
        case .apps:
            let scored = apps.compactMap { app in Fuzzy.score(q, in: app.name).map { (app, $0 + bonus(used[app.id])) } }
            return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
                .prefix(300).map { appItem($0.0) }
        case .scripts:
            let scored = scripts.compactMap { sc in
                [sc.name, sc.keywords].compactMap { Fuzzy.score(q, in: $0) }.max().map { (sc, $0 + bonus(used[sc.id])) }
            }
            return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
                .map { scriptItem($0.0) }
        case .folders:
            // Bare text is relative to home; explicit paths work as before.
            let path = q.hasPrefix("/") || q.hasPrefix("~") ? q : "~/" + q
            return folderResults(path)
        case .themes:
            let scored = themes.compactMap { t in Fuzzy.score(q, in: t.name).map { (t, $0) } }
            return scored.sorted { $0.1 > $1.1 }.map { themeItem($0.0) }
        }
    }

    // MARK: Search

    private var usage: [String: Int] {
        get { defaults.dictionary(forKey: "usage") as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: "usage") }
    }

    private func bumpUsage(_ id: String) { usage[id, default: 0] += 1 }

    private func appItem(_ app: AppEntry) -> ResultItem {
        ResultItem(id: app.id, title: app.name, subtitle: "", kind: "Application", iconPath: app.url.path) {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func scriptItem(_ s: ScriptEntry) -> ResultItem {
        ResultItem(id: s.id, title: s.name, subtitle: s.detail, kind: "Script", symbol: "terminal") { Scripts.run(s) }
    }

    private func themeItem(_ t: Theme) -> ResultItem {
        ResultItem(id: "theme:" + t.name, title: "Theme: " + t.name, subtitle: t.isDark ? "Dark" : "Light",
                   kind: "Theme", symbol: "paintpalette") { [weak self] in self?.setTheme(t) }
    }

    private func folderItem(_ url: URL) -> ResultItem {
        let shown = (url.path as NSString).abbreviatingWithTildeInPath
        return ResultItem(id: "folder:" + url.path, title: url.lastPathComponent, subtitle: shown, kind: "Folder",
                          iconPath: url.path, completion: shown + "/") { [weak self] in self?.openFolder(url) }
    }

    /// Only an explicit http:// or https:// prefix counts, and only with a host and no spaces.
    private func linkItem(_ text: String) -> ResultItem? {
        let lower = text.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://"), !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return ResultItem(id: "link", title: text, subtitle: host, kind: "Open", symbol: "globe") { [weak self] in
            self?.openLink(url)
        }
    }

    func openLink(_ url: URL) {
        if let app = linkApp {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func openFolder(_ url: URL) {
        if let app = folderApp {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// "~/Pro" lists matching siblings; "~/Projects/" lists the folder's children.
    private func folderResults(_ q: String) -> [ResultItem] {
        let expanded = (q as NSString).expandingTildeInPath
        let endsWithSlash = expanded.hasSuffix("/")
        let dir = endsWithSlash ? expanded : (expanded as NSString).deletingLastPathComponent
        let needle = endsWithSlash ? "" : (expanded as NSString).lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.isEmpty ? "/" : dir)) ?? []
        let scored: [(URL, Int)] = names.compactMap { name in
            guard needle.hasPrefix(".") || !name.hasPrefix(".") else { return nil }
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true, url.pathExtension != "app" else { return nil }
            return Fuzzy.score(needle, in: name).map { (url, $0) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastPathComponent.localizedCaseInsensitiveCompare($1.0.lastPathComponent) == .orderedAscending }
            .prefix(100).map { folderItem($0.0) }
    }

    private func update() {
        selection = 0
        let q = query.trimmingCharacters(in: .whitespaces)
        let used = usage

        if let scope {
            results = scopedResults(scope, q)
            return
        }

        if q.hasPrefix(":") {
            results = pickerResults(String(q.dropFirst()))
            return
        }

        if q.isEmpty {
            results = apps.filter { used[$0.id, default: 0] > 0 }
                .sorted { used[$0.id, default: 0] > used[$1.id, default: 0] }
                .prefix(recentCount).map(appItem)
            return
        }

        if q.hasPrefix("/") || q.hasPrefix("~") {
            results = folderResults(q)
            return
        }

        var out: [ResultItem] = []

        if let link = linkItem(q) { out.append(link) }

        if let answer = Calculator.evaluate(q) {
            out.append(ResultItem(id: "calc", title: answer, subtitle: q, kind: "Copy", symbol: "equal.circle", emphasized: true) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(answer, forType: .string)
            })
        }

        // "theme" / "theme nord" lists themes; they stay out of ordinary searches.
        if q.lowercased().hasPrefix("theme") {
            let rest = String(q.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let matches = themes.compactMap { t in Fuzzy.score(rest, in: t.name).map { (t, $0) } }
            out += matches.sorted { $0.1 > $1.1 }.map { themeItem($0.0) }
        }

        var scored: [(ResultItem, Int)] = []
        for app in apps {
            if let s = Fuzzy.score(q, in: app.name) { scored.append((appItem(app), s + bonus(used[app.id])) ) }
        }
        for script in scripts {
            let best = [script.name, script.keywords].compactMap { Fuzzy.score(q, in: $0) }.max()
            if let s = best { scored.append((scriptItem(script), s + bonus(used[script.id]))) }
        }
        out += scored.sorted { $0.1 > $1.1 }.prefix(100).map(\.0)
        results = out
    }

    private func bonus(_ count: Int?) -> Int { min(count ?? 0, 20) * 2 }
}
