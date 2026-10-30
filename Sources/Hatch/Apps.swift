import Foundation

struct AppEntry {
    let name: String
    let url: URL
    var id: String { "app:" + url.path }
}

enum AppIndex {
    private static let roots = [
        "/Applications",
        "/System/Applications",
        "/System/Library/CoreServices/Applications",
        "/System/Cryptexes/App/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Finder lives outside the usual folders.
    private static let extras = ["/System/Library/CoreServices/Finder.app"]

    static func scan() -> [AppEntry] {
        var found: [String: AppEntry] = [:]
        for root in roots { collect(URL(fileURLWithPath: root), depth: 0, into: &found) }
        for path in extras where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            found[url.path] = AppEntry(name: displayName(url), url: url)
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Descends into plain folders (Utilities, vendor folders) but never into bundles.
    private static func collect(_ dir: URL, depth: Int, into found: inout [String: AppEntry]) {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for url in items {
            if url.pathExtension == "app" {
                found[url.path] = AppEntry(name: displayName(url), url: url)
            } else if depth < 2, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collect(url, depth: depth + 1, into: &found)
            }
        }
    }

    private static func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum Fuzzy {
    /// Subsequence match with bonuses for word starts, runs and prefixes. Nil means no match.
    static func score(_ query: String, in text: String) -> Int? {
        let q = Array(query.lowercased()), t = Array(text.lowercased())
        guard !q.isEmpty else { return 0 }
        var qi = 0, score = 0, last = -2
        for (ti, c) in t.enumerated() where qi < q.count && c == q[qi] {
            var s = 1
            if ti == 0 { s += 8 } else if !t[ti - 1].isLetter && !t[ti - 1].isNumber { s += 6 }
            if ti == last + 1 { s += 4 }
            score += s
            last = ti
            qi += 1
        }
        guard qi == q.count else { return nil }
        if t.starts(with: q) { score += 20 }
        return score - t.count / 4
    }
}
