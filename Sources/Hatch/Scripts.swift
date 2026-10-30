import AppKit

struct ScriptEntry {
    let url: URL
    let name: String
    let detail: String
    let keywords: String
    let confirm: Bool
    var id: String { "script:" + url.path }
}

/// Every executable file in the scripts folder is a command. Optional header comments configure it:
///
///     # name: Lock Screen
///     # description: Lock the display
///     # keywords: sleep away
///     # confirm: true
enum Scripts {
    static var directory: URL {
        Config.directory.appendingPathComponent("scripts", isDirectory: true)
    }

    private static let starters: [(file: String, body: String)] = [
        ("lock-screen.sh", """
        #!/bin/zsh
        # name: Lock Screen
        # description: Lock the display
        # keywords: lock sleep
        pmset displaysleepnow
        """),
        ("screensaver.sh", """
        #!/bin/zsh
        # name: Start Screensaver
        # description: Start the screen saver
        open -a ScreenSaverEngine
        """),
        ("sleep.sh", """
        #!/bin/zsh
        # name: Sleep
        # description: Put the Mac to sleep
        pmset sleepnow
        """),
        ("shutdown.sh", """
        #!/bin/zsh
        # name: Shut Down
        # description: Shut down the Mac
        # keywords: power off
        # confirm: true
        osascript -e 'tell application "System Events" to shut down'
        """),
    ]

    /// Writes starter scripts the first time the folder is missing, so deleting one later sticks.
    static func seedIfNeeded() {
        let fm = FileManager.default
        Config.migrateLegacy("scripts")
        guard !fm.fileExists(atPath: directory.path) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (file, body) in starters {
            let url = directory.appendingPathComponent(file)
            try? (body + "\n").write(to: url, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    static func load() -> [ScriptEntry] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { fm.isExecutableFile(atPath: $0.path) && !$0.hasDirectoryPath }
            .map(parse)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func parse(_ url: URL) -> ScriptEntry {
        var meta: [String: String] = [:]
        let head = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for raw in head.split(separator: "\n", omittingEmptySubsequences: false).prefix(15) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") || line.hasPrefix("//"), !line.hasPrefix("#!") else { continue }
            line = String(line.drop(while: { $0 == "#" || $0 == "/" })).trimmingCharacters(in: .whitespaces)
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { meta[parts[0].lowercased()] = parts[1] }
        }
        let fallback = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
        return ScriptEntry(
            url: url,
            name: meta["name"] ?? fallback,
            detail: meta["description"] ?? "",
            keywords: meta["keywords"] ?? "",
            confirm: meta["confirm"]?.lowercased() == "true"
        )
    }

    @MainActor
    static func run(_ script: ScriptEntry) {
        if script.confirm {
            let alert = NSAlert()
            alert.messageText = "Run “\(script.name)”?"
            if !script.detail.isEmpty { alert.informativeText = script.detail }
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        DispatchQueue.global().async {
            let (status, stderr) = execute(script.url)
            guard status != 0 else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "“\(script.name)” failed (exit \(status))"
                alert.informativeText = String(stderr.suffix(600))
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    /// Apps launched from Finder get a bare PATH, so add the usual Homebrew locations.
    private static func execute(_ url: URL) -> (Int32, String) {
        func attempt(_ exe: URL, _ args: [String]) throws -> (Int32, String) {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            p.environment = env
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            try p.run()
            let data = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        // No shebang makes direct exec fail with ENOEXEC; fall back to zsh.
        if let result = try? attempt(url, []) { return result }
        return (try? attempt(URL(fileURLWithPath: "/bin/zsh"), [url.path])) ?? (127, "Could not launch script")
    }
}
