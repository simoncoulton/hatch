import AppKit
import Carbon.HIToolbox

/// `~/.config/hatch/config.yml`, a flat `key: value` file.
enum Config {
    /// Everything lives here: config.yml, scripts/ and themes/.
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/hatch", isDirectory: true)
    }

    static var url: URL { directory.appendingPathComponent("config.yml") }

    /// This app was called Launcher before it was Hatch. Moves ~/.config/launcher to ~/.config/hatch once,
    /// updating the paths and preset names that the config's comments and `theme` value mention.
    static func migrateRenamedDirectory() {
        let fm = FileManager.default
        let old = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/launcher", isDirectory: true)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: directory.path) else { return }
        guard (try? fm.moveItem(at: old, to: directory)) != nil else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let fixed = text
            .replacingOccurrences(of: ".config/launcher", with: ".config/hatch")
            .replacingOccurrences(of: "\"Launcher Dark\"", with: "\"Hatch Dark\"")
            .replacingOccurrences(of: "\"Launcher Light\"", with: "\"Hatch Light\"")
            .replacingOccurrences(of: "shows the launcher", with: "shows Hatch")
        try? fixed.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Moves `scripts` or `themes` from the old Application Support folder, unless the new one already exists.
    /// Removes the old folder afterwards if nothing else is left in it.
    static func migrateLegacy(_ name: String) {
        let fm = FileManager.default
        let legacyRoot = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Launcher")
        let old = legacyRoot.appendingPathComponent(name), new = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? fm.moveItem(at: old, to: new)) != nil else { return }
        let left = ((try? fm.contentsOfDirectory(atPath: legacyRoot.path)) ?? []).filter { $0 != ".DS_Store" }
        if left.isEmpty { try? fm.removeItem(at: legacyRoot) }
    }

    /// Where the config lived before it moved to ~/.config.
    private static var legacyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Launcher/config.yml")
    }

    static let defaultHotkey = "option+space"
    static let defaultOpacity = 0.85

    /// Every setting, with the comment that documents it. Missing ones are appended to older config files
    /// as commented placeholders, so the file always lists what can be configured.
    private static let documented: [(key: String, text: String)] = [
        ("hotkey", """
        # Global shortcut that shows Hatch. Applies the next time the panel opens.
        # Modifiers: cmd, option (alt), ctrl, shift. Keys: a-z, 0-9, space, return, tab, f1-f12, and - = [ ] ; ' , . / `
        hotkey: \(defaultHotkey)
        """),
        ("opacity", """
        # Panel opacity, 0.3 to 1. Also in Settings.
        # opacity: 0.85
        """),
        ("padding", """
        # Vertical padding inside each result row, in points (0 to 20). Lower is more compact.
        # padding: 8
        """),
        ("start_at_login", """
        # Start Hatch when you log in (true or false). Also in Settings. Leave out to leave the login item alone.
        # start_at_login: false
        """),
        ("recents", """
        # How many of your most-launched apps to list when the search box is empty (0 to 10). 0 shows nothing.
        # recents: 0
        """),
        ("icons", """
        # Result icons: color (as macOS draws them) or monochrome (tinted with the theme's accent color).
        # icons: color
        """),
        ("theme", """
        # Theme name: a built-in preset or the name inside a file in ~/.config/hatch/themes/.
        # theme: "Hatch Dark"
        """),
        ("folder_app", """
        # App that opens folders. Leave out for Finder.
        # folder_app: /Applications/Ghostty.app
        """),
        ("link_app", """
        # App that opens http(s) links. Leave out for the default browser.
        # link_app: /Applications/Firefox.app
        """),
    ]

    private static func mentions(_ key: String, in text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains {
            String($0.drop(while: { $0 == "#" || $0 == " " })).hasPrefix(key + ":")
        }
    }

    static func seedIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacyURL.path),
           (try? fm.moveItem(at: legacyURL, to: url)) != nil {
            // Moved from Application Support; fall through to document anything it lacked.
        }
        let existing = try? String(contentsOf: url, encoding: .utf8)
        let missing = documented.filter { !mentions($0.key, in: existing ?? "") }
        guard !missing.isEmpty else { return }
        var text = existing ?? ""
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += missing.map(\.text).joined(separator: "\n\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Sets `key` in place, keeping comments and other lines. Replaces an active line, else a commented
    /// placeholder (`# key: ...`), else appends.
    /// A nil value removes the active line, so the setting falls back to its default.
    static func set(_ key: String, _ value: String?) {
        seedIfNeeded()
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func index(commented: Bool) -> Int? {
            lines.firstIndex {
                var line = $0.trimmingCharacters(in: .whitespaces)
                if commented {
                    guard line.hasPrefix("#") else { return false }
                    line = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                }
                return line.hasPrefix(key + ":")
            }
        }
        guard let value else {
            if let i = index(commented: false) { lines.remove(at: i) }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let entry = "\(key): \(value)"
        if let i = index(commented: false) ?? index(commented: true) {
            lines[i] = entry
        } else {
            if lines.last == "" { lines.removeLast() }
            lines.append(entry)
            lines.append("")
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func value(_ key: String) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            guard line[..<colon].trimmingCharacters(in: .whitespaces) == key else { continue }
            var v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let comment = v.range(of: " #") { v = v[..<comment.lowerBound].trimmingCharacters(in: .whitespaces) }
            return v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    /// ANSI virtual key codes.
    private static let keys: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "u": 32, "i": 34, "o": 31, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        "space": 49, "return": 36, "tab": 48, "-": 27, "=": 24, "[": 33, "]": 30, "'": 39, ";": 41, ",": 43, "/": 44, ".": 47, "`": 50,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// Builds the config string for a recorded key press, or nil if it isn't a valid hotkey.
    static func hotkeyString(keyCode: Int, flags: NSEvent.ModifierFlags) -> String? {
        guard let name = keys.first(where: { $0.value == keyCode })?.key else { return nil }
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        parts.append(name)
        let text = parts.joined(separator: "+")
        return parseHotkey(text) == nil ? nil : text
    }

    /// "option+space" -> "⌥Space"
    static func pretty(_ text: String) -> String {
        text.lowercased().split(separator: "+").map { part -> String in
            switch part {
            case "cmd", "command": "⌘"
            case "option", "opt", "alt": "⌥"
            case "ctrl", "control": "⌃"
            case "shift": "⇧"
            case "space": "Space"
            case "return": "↩"
            case "tab": "⇥"
            default: part.uppercased()
            }
        }.joined()
    }

    /// Parses "cmd+shift+space". A bare key is only allowed for function keys, since it would swallow ordinary typing.
    static func parseHotkey(_ text: String) -> (keyCode: Int, modifiers: Int)? {
        var mods = 0
        var code: Int?
        for part in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command": mods |= cmdKey
            case "option", "opt", "alt": mods |= optionKey
            case "ctrl", "control": mods |= controlKey
            case "shift": mods |= shiftKey
            default:
                guard code == nil, let k = keys[part] else { return nil }
                code = k
            }
        }
        guard let code else { return nil }
        if mods == 0 && !(96...122).contains(code) { return nil }
        return (code, mods)
    }
}
