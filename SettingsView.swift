import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            ScriptsSettingsTab()
                .tabItem {
                    Label("Scripts", systemImage: "terminal")
                }

            QuickLinksSettingsTab()
                .tabItem {
                    Label("Quick Links", systemImage: "link")
                }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - Shortcuts Tab

private struct ShortcutsSettingsTab: View {
    @ObservedObject private var store = ShortcutStore.shared

    private var sections: [String] {
        var seen: [String] = []
        for action in ShortcutAction.allCases where !seen.contains(action.section) {
            seen.append(action.section)
        }
        return seen
    }

    var body: some View {
        Form {
            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(ShortcutAction.allCases.filter { $0.section == section }, id: \.self) { action in
                        ShortcutRow(action: action, store: store)
                    }
                }
            }

            Section {
                Button("Reset All to Defaults") {
                    store.resetAll()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var store: ShortcutStore
    @State private var conflictMessage: String?

    var body: some View {
        HStack {
            Text(action.displayName)

            Spacer()

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ShortcutRecorder(binding: store.binding(for: action)) { candidate in
                attemptAssign(candidate)
            }

            Button {
                store.reset(action)
                conflictMessage = nil
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("Reset to default")
        }
    }

    private func attemptAssign(_ binding: KeyBinding) {
        if let conflict = store.set(binding, for: action) {
            conflictMessage = "Already used by \(conflict.displayName)"
        } else {
            conflictMessage = nil
        }
    }
}

/// A button that shows the current key combination and, when clicked, captures the next
/// key press (with at least one modifier) as a candidate binding.
private struct ShortcutRecorder: View {
    let binding: KeyBinding
    let onCapture: (KeyBinding) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: startRecording) {
            Text(isRecording ? "Press keys…" : binding.displayString)
                .frame(minWidth: 110)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        // Every window-management default is a real Carbon hotkey, which intercepts a
        // matching combo before it ever becomes a normal NSEvent — so without suspending
        // them, trying to record any currently-bound combo (the first thing you'd try)
        // would silently never reach this monitor at all.
        HotKeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels without changing the binding.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier so a bare letter can never be captured —
            // otherwise typing in the search field would trigger launcher actions.
            guard !flags.isEmpty else { return nil }

            let candidate = KeyBinding(keyCode: event.keyCode, modifiers: flags)
            stopRecording()
            onCapture(candidate)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        HotKeyCenter.shared.registerAll()
    }
}

// MARK: - Scripts Tab

/// Lets the user configure exactly which folders are scanned for scripts, replacing the
/// old hardcoded Documents/Desktop scan. Backed by `SearchEngine.scriptSearchPaths`,
/// which is a static, UserDefaults-backed list — no `SearchEngine` instance needed here.
private struct ScriptsSettingsTab: View {
    @State private var paths: [String] = SearchEngine.scriptSearchPaths

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scripts are only searched for in the folders listed below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            remove(path)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Spacer()
                Button("Add Folder…", action: addFolder)
            }
        }
        .padding()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to search for scripts"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !paths.contains(path) else { return }

        paths.append(path)
        SearchEngine.scriptSearchPaths = paths
    }

    private func remove(_ path: String) {
        paths.removeAll { $0 == path }
        SearchEngine.scriptSearchPaths = paths
    }
}

// MARK: - Quick Links Tab

private struct QuickLinksSettingsTab: View {
    @ObservedObject private var store = QuickLinkStore.shared

    @State private var newName = ""
    @State private var newTarget = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Links are findable by name from the launcher and open a URL, file, or folder.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(store.links) { link in
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(link.name)
                            Text(link.target)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            store.remove(link)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)

            HStack(spacing: 8) {
                TextField("Name", text: $newName)
                    .frame(width: 120)
                TextField("URL or path", text: $newTarget)
                Button("Choose…", action: chooseTarget)
                Button("Add", action: addLink)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              newTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a file or folder for this Quick Link"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        newTarget = url.path
        if newName.trimmingCharacters(in: .whitespaces).isEmpty {
            newName = url.lastPathComponent
        }
    }

    private func addLink() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let target = newTarget.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !target.isEmpty else { return }

        store.add(name: name, target: target)
        newName = ""
        newTarget = ""
    }
}

#Preview {
    SettingsView()
}
