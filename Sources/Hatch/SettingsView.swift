import SwiftUI

/// Every control reads and writes through the model, which stores the value in config.yml and applies it immediately.
struct SettingsView: View {
    @ObservedObject var model: HatchModel

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Shortcut") {
                    VStack(alignment: .trailing, spacing: 3) {
                        Button(model.recordingHotkey ? "Press a shortcut…  (Esc cancels)" : Config.pretty(model.hotkeyText)) {
                            model.recordingHotkey ? model.stopRecordingHotkey() : model.startRecordingHotkey()
                        }
                        if !model.hotkeyStatus.isEmpty {
                            Text(model.hotkeyStatus).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
                }
                Toggle("Start at login", isOn: Binding(get: { model.startAtLogin }, set: { model.setStartAtLogin($0) }))
                if !model.loginMessage.isEmpty {
                    Text(model.loginMessage).font(.caption).foregroundColor(.secondary)
                }
                Stepper(value: Binding(get: { model.recents }, set: { model.setRecents($0) }), in: 0...10) {
                    LabeledContent("Recent apps when empty", value: model.recents == 0 ? "Off" : "\(model.recents)")
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { model.theme.name },
                    set: { name in if let t = model.themes.first(where: { $0.name == name }) { model.setTheme(t) } })
                ) {
                    ForEach(model.themes) { Text($0.name).tag($0.name) }
                }
                LabeledContent("") {
                    HStack(spacing: 5) {
                        ForEach([model.theme.background, model.theme.surface, model.theme.text, model.theme.accent], id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                        }
                        Spacer()
                        Button("Save Copy…") { model.saveThemeCopy() }
                        Button("Themes Folder") { Themes.openFolder() }
                    }
                }
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: Binding(get: { model.opacity }, set: { model.setOpacity($0) }), in: 0.3...1, step: 0.05)
                        Text("\(Int((model.opacity * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Row padding") {
                    HStack {
                        Slider(value: Binding(get: { model.padding }, set: { model.setPadding($0) }), in: 0...20, step: 1)
                        Text("\(Int(model.padding)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Icons", selection: Binding(get: { model.monochromeIcons }, set: { model.setMonochromeIcons($0) })) {
                    Text("Color").tag(false)
                    Text("Monochrome").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Open with") {
                appPicker("Folders", defaultLabel: "Finder (default)", current: model.folderApp,
                          candidates: model.folderCandidates, prompt: "Choose the app that opens folders") { model.folderApp = $0 }
                appPicker("Links", defaultLabel: "System default browser", current: model.linkApp,
                          candidates: model.linkCandidates, prompt: "Choose the app that opens links") { model.linkApp = $0 }
            }

            Section("Files") {
                LabeledContent("Everything above is stored in") {
                    HStack {
                        Button("Config File") { Config.openFile() }
                        Button("Scripts Folder") { Scripts.openFolder() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 620)
        .onDisappear { model.stopRecordingHotkey() }
    }

    private func appPicker(_ title: String, defaultLabel: String, current: URL?, candidates: [URL], prompt: String,
                           set: @escaping (URL?) -> Void) -> some View {
        var options = candidates
        if let current, !options.contains(where: { $0.path == current.path }) { options.append(current) }
        return LabeledContent(title) {
            HStack {
                Picker("", selection: Binding(
                    get: { current?.path ?? "" },
                    set: { set($0.isEmpty ? nil : URL(fileURLWithPath: $0)) })
                ) {
                    Text(defaultLabel).tag("")
                    ForEach(options, id: \.path) { url in
                        Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")).tag(url.path)
                    }
                }
                .labelsHidden()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowedContentTypes = [.application]
                    panel.message = prompt
                    if panel.runModal() == .OK { set(panel.url) }
                }
            }
        }
    }
}

extension Config {
    static func openFile() {
        seedIfNeeded()
        NSWorkspace.shared.open(url)
    }
}

extension Scripts {
    static func openFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

extension Themes {
    static func openFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
