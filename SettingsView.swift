import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

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

            FileSearchSettingsTab()
                .tabItem {
                    Label("File Search", systemImage: "magnifyingglass")
                }

            QuickLinksSettingsTab()
                .tabItem {
                    Label("Quick Links", systemImage: "link")
                }

            StickersSettingsTab()
                .tabItem {
                    Label("Stickers", systemImage: "face.smiling")
                }

            ClipboardSettingsTab()
                .tabItem {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
        }
        .frame(width: 520, height: 420)
        .background(SettingsWindowAccessor())
    }
}

/// Invisible helper that hands `SettingsOpener` a reference to the actual `NSWindow`
/// SwiftUI creates for the `Settings` scene — there's no other way to reach it, since
/// SwiftUI never surfaces that window itself. `updateNSView` (rather than just
/// `makeNSView`) is what actually catches it: the view has no window yet at construction
/// time, only once SwiftUI has finished inserting it into the real window hierarchy, which
/// is when `updateNSView` next runs.
private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            // `.moveToActiveSpace` makes activating Settings bring it to whichever desktop
            // you're on, rather than switching you to the one it was left open on.
            nsView.window?.collectionBehavior.insert(.moveToActiveSpace)
            SettingsOpener.window = nsView.window
        }
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

// MARK: - File Search Tab

private struct FileSearchSettingsTab: View {
    @State private var limitScope = SearchEngine.limitFileSearchScope
    @State private var paths: [String] = SearchEngine.fileSearchPaths

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Search — and its empty-query \"recent files\" list — only looks in the folders below.")
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

            Divider()

            Toggle("Limit File Search scope for speed", isOn: $limitScope)
                .onChange(of: limitScope) { _, newValue in
                    SearchEngine.limitFileSearchScope = newValue
                }

            Text("Off by default: File Search walks every file in the folders above, so a search is guaranteed to find every match — it may just take a while in an especially large folder. Turning this on caps how many files it's willing to look at per folder instead, so results stay fast no matter how big those folders get, at the cost of possibly missing a match buried deep inside one.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to include in File Search"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !paths.contains(path) else { return }

        paths.append(path)
        SearchEngine.fileSearchPaths = paths
    }

    private func remove(_ path: String) {
        paths.removeAll { $0 == path }
        SearchEngine.fileSearchPaths = paths
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

// MARK: - Stickers Tab

private struct StickersSettingsTab: View {
    @ObservedObject private var store = StickerStore.shared
    @State private var newName = ""
    /// `clipboardHasImage` is a plain computed property, so SwiftUI only re-checks it
    /// when the view's body re-renders — which normally only happens in response to a
    /// `@State`/`@Published` change. Copying something in another app happens entirely
    /// outside this view's observed state, so without this the button's enabled state
    /// would freeze at whatever the clipboard held the last time this view happened to
    /// redraw for some unrelated reason, never reflecting what you copy afterward.
    /// Toggling this on a timer is what actually forces the periodic re-check.
    @State private var clipboardPollTick = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stickers are custom images/GIFs, searchable by name alongside emoji and pasted the same way.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(store.stickers) { sticker in
                    HStack {
                        StickerThumbnail(fileURL: store.fileURL(for: sticker))
                        Text(sticker.name)

                        Spacer()

                        Button {
                            store.remove(sticker)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)

            HStack(spacing: 8) {
                TextField("Name (optional)", text: $newName)
                Spacer()
                Button("Add from Clipboard", action: addStickerFromClipboard)
                    .disabled(!clipboardHasImage)
                Button("Add Sticker…", action: addSticker)
            }
        }
        .padding()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            clipboardPollTick.toggle()
        }
    }

    /// Whether the clipboard currently holds something `addStickerFromClipboard` could
    /// actually use — checked on every body re-render rather than cached, since there's
    /// no notification for "the clipboard changed" to invalidate a cache against.
    private var clipboardHasImage: Bool {
        let pasteboard = NSPasteboard.general
        if pasteboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")) != nil { return true }
        // `readEmbeddedImage` covers both a direct image type (HEIC, JPEG, PDF, etc.)
        // and an image wrapped in RTFD — how Messages in particular copies pictures.
        return pasteboard.readEmbeddedImage() != nil
    }

    private func addSticker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .gif]
        panel.message = "Choose an image or GIF to add as a sticker"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = newName.trimmingCharacters(in: .whitespaces).isEmpty
            ? url.deletingPathExtension().lastPathComponent
            : newName.trimmingCharacters(in: .whitespaces)

        store.add(name: name, sourceURL: url)
        newName = ""
    }

    private func addStickerFromClipboard() {
        let pasteboard = NSPasteboard.general
        let name = newName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Sticker"
            : newName.trimmingCharacters(in: .whitespaces)

        // Keep an actual GIF as-is so its animation survives. For everything else, a
        // direct image type (HEIC, JPEG, PDF, ...) or one wrapped in RTFD —
        // `readEmbeddedImage` decodes it and we flatten the result to PNG, so stickers
        // always end up in one predictable, widely-supported format rather than
        // whatever the source app happened to put on the clipboard.
        if let gifData = pasteboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")) {
            store.add(name: name, data: gifData, fileExtension: "gif")
        } else if let image = pasteboard.readEmbeddedImage(),
                  let pngData = image.pngData() {
            store.add(name: name, data: pngData, fileExtension: "png")
        } else {
            return
        }
        newName = ""
    }
}

private struct StickerThumbnail: View {
    let fileURL: URL
    /// Loaded once in `.onAppear` rather than decoded straight in `body`: the parent tab
    /// re-renders every second (its clipboard-polling timer), and without this, every
    /// thumbnail in the list would re-read and re-decode its file from disk on every one
    /// of those tics for as long as the Stickers tab is open — sticker files never change
    /// after being added, so there's nothing to gain from redoing that work.
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .onAppear {
            guard image == nil else { return }
            image = NSImage(contentsOf: fileURL)
        }
    }
}

// MARK: - Clipboard Tab

private struct ClipboardSettingsTab: View {
    @ObservedObject private var store = ClipboardHistoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Clipboard History", isOn: $store.isEnabled)

            Text("When enabled, ReFlow keeps a short history of things you copy, searchable from the launcher by typing \"cb\". History is kept in memory only — never written to disk — and is cleared whenever this is turned off or ReFlow quits.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if store.isEnabled {
                Divider()

                HStack {
                    Text("\(store.entries.count) item\(store.entries.count == 1 ? "" : "s") in history")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History") {
                        store.clear()
                    }
                    .disabled(store.entries.isEmpty)
                }
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
