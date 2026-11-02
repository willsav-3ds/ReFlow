import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct SettingsView: View {
    @ObservedObject private var themes = ThemeStore.shared

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

            ThemesSettingsTab()
                .tabItem {
                    Label("Themes", systemImage: "paintpalette")
                }
        }
        .frame(width: 600, height: 460)
        .tint(themes.accentColor)
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

    @ObservedObject private var themes = ThemeStore.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: startRecording) {
            Text(isRecording ? "Press keys…" : binding.displayString)
                .frame(minWidth: 110)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isRecording ? themes.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
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
    /// Cached rather than computed in `body`, and refreshed by the timer below when the
    /// clipboard changes: copying something in another app happens entirely outside this
    /// view's observed state, and there's no notification for it. Reading this in `body`
    /// is also what makes the refresh redraw the button — SwiftUI ignores changes to
    /// `@State` that `body` never reads.
    @State private var clipboardHasImage = false
    @State private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    @State private var isDownloadingGIF = false
    @State private var statusMessage: String?

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

                        if sticker.isGIF {
                            Text("GIF")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

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

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Name (optional)", text: $newName)
                Spacer()
                if isDownloadingGIF {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Add from Clipboard", action: addStickerFromClipboard)
                    .disabled(!clipboardHasImage || isDownloadingGIF)
                Button("Add Sticker…", action: addSticker)
            }
        }
        .padding()
        .onAppear(perform: refreshClipboardState)
        .onReceive(Timer.publish(every: 1, tolerance: 0.25, on: .main, in: .common).autoconnect()) { _ in
            // Only re-check when the clipboard actually changed: the check decodes
            // whatever's on it, which isn't something to redo every second.
            guard NSPasteboard.general.changeCount != lastPasteboardChangeCount else { return }
            refreshClipboardState()
        }
    }

    private func refreshClipboardState() {
        let pasteboard = NSPasteboard.general
        lastPasteboardChangeCount = pasteboard.changeCount
        clipboardHasImage = pasteboard.readStickerContent() != nil
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
        let name = newName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Sticker"
            : newName.trimmingCharacters(in: .whitespaces)
        statusMessage = nil

        // Keep an actual GIF as-is so its animation survives. Everything else gets
        // flattened to PNG, so stickers always end up in one predictable, widely-supported
        // format rather than whatever the source app happened to put on the clipboard.
        switch NSPasteboard.general.readStickerContent() {
        case .gif(let data):
            finishAdding(store.add(name: name, data: data, fileExtension: "gif"))
        case .image(let image):
            addStill(image, name: name)
        case .remoteGIF(let url, let fallback):
            isDownloadingGIF = true
            Task {
                let data = await store.downloadGIF(from: url)
                isDownloadingGIF = false
                if let data {
                    finishAdding(store.add(name: name, data: data, fileExtension: "gif"))
                } else if let fallback {
                    addStill(fallback, name: name)
                    statusMessage = "Couldn't download the animated GIF, so this was added as a still image."
                } else {
                    statusMessage = "Couldn't download that GIF."
                }
            }
        case nil:
            statusMessage = "Couldn't read an image from the clipboard."
        }
    }

    private func addStill(_ image: NSImage, name: String) {
        guard let pngData = image.pngData() else {
            statusMessage = "Couldn't read an image from the clipboard."
            return
        }
        finishAdding(store.add(name: name, data: pngData, fileExtension: "png"))
    }

    private func finishAdding(_ succeeded: Bool) {
        if succeeded {
            newName = ""
        } else {
            statusMessage = "Couldn't save the sticker."
        }
    }
}

private struct StickerThumbnail: View {
    let fileURL: URL
    /// Loaded once in `.onAppear` rather than decoded straight in `body`: the parent tab
    /// re-renders whenever the clipboard changes or the name field is edited, and without
    /// this, every thumbnail in the list would re-read and re-decode its file from disk
    /// each time — sticker files never change after being added, so there's nothing to
    /// gain from redoing that work.
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

// MARK: - Themes Tab

private struct ThemesSettingsTab: View {
    @ObservedObject private var store = ThemeStore.shared

    /// Selecting a row is what activates a theme, so the list's selection *is* the active theme.
    private var selection: Binding<UUID?> {
        Binding(
            get: { store.activeThemeID },
            set: { id in
                if let id { store.activate(id) }
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: selection) {
                    Section("Built-In") {
                        ForEach(ThemeStore.builtInThemes) { theme in
                            ThemeListRow(theme: theme)
                        }
                    }
                    if !store.customThemes.isEmpty {
                        Section("Custom") {
                            ForEach(store.customThemes) { theme in
                                ThemeListRow(theme: theme)
                            }
                        }
                    }
                }
                .listStyle(.inset)

                HStack(spacing: 8) {
                    Button {
                        store.duplicateActiveTheme()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Create a new theme from the selected one")

                    Button {
                        store.remove(store.activeThemeID)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(store.isActiveThemeBuiltIn)
                    .help("Delete the selected theme")
                }
            }
            .frame(width: 180)

            ThemeEditor(store: store)
        }
        .padding()
    }
}

private struct ThemeListRow: View {
    let theme: Theme

    var body: some View {
        HStack {
            ThemeSwatch(theme: theme)
            Text(theme.displayName)
                .lineLimit(1)
        }
        .tag(theme.id)
    }
}

private struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        Circle()
            .fill(theme.background?.color ?? Color.secondary.opacity(0.3))
            .overlay {
                Circle()
                    .fill(theme.accent?.color ?? Color.accentColor)
                    .padding(4)
            }
            .frame(width: 16, height: 16)
    }
}

private struct ThemeEditor: View {
    @ObservedObject var store: ThemeStore

    /// A binding to one field of the active theme, saving every change as it's made.
    private func field<Value>(_ keyPath: WritableKeyPath<Theme, Value>) -> Binding<Value> {
        Binding(
            get: { store.activeTheme[keyPath: keyPath] },
            set: { newValue in
                var theme = store.activeTheme
                theme[keyPath: keyPath] = newValue
                store.update(theme)
            }
        )
    }

    /// Bridges an optional stored color to a toggle: on starts from `fallback`, off clears it.
    private func isEnabled(_ keyPath: WritableKeyPath<Theme, ThemeColor?>, fallback: NSColor) -> Binding<Bool> {
        Binding(
            get: { store.activeTheme[keyPath: keyPath] != nil },
            set: { enabled in
                field(keyPath).wrappedValue = enabled ? ThemeColor(fallback) : nil
            }
        )
    }

    /// Bridges a stored color to `ColorPicker`, which only speaks SwiftUI's `Color`.
    private func pickerColor(_ keyPath: WritableKeyPath<Theme, ThemeColor?>) -> Binding<Color> {
        Binding(
            get: { store.activeTheme[keyPath: keyPath]?.color ?? .clear },
            set: { newColor in
                if let color = ThemeColor(NSColor(newColor)) {
                    field(keyPath).wrappedValue = color
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemePreview(theme: store.activeTheme, accent: store.accentColor)

            if store.isActiveThemeBuiltIn {
                HStack {
                    Text("Built-in themes can't be edited.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Duplicate to Customize") {
                        store.duplicateActiveTheme()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: field(\.name))

                Picker("Appearance", selection: field(\.appearance)) {
                    ForEach(ThemeAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Toggle("Custom accent color", isOn: isEnabled(\.accent, fallback: .controlAccentColor))
                    Spacer()
                    if store.activeTheme.accent != nil {
                        ColorPicker("Accent color", selection: pickerColor(\.accent), supportsOpacity: false)
                            .labelsHidden()
                    }
                }

                HStack {
                    Toggle("Custom launcher background", isOn: isEnabled(\.background, fallback: .windowBackgroundColor))
                    Spacer()
                    if store.activeTheme.background != nil {
                        ColorPicker("Launcher background", selection: pickerColor(\.background), supportsOpacity: false)
                            .labelsHidden()
                    }
                }

                if store.activeTheme.background != nil {
                    HStack {
                        Text("Opacity")
                        Slider(value: field(\.backgroundOpacity), in: 0.2...1)
                    }
                }
            }
            .disabled(store.isActiveThemeBuiltIn)

            Spacer()
        }
    }
}

/// A miniature launcher showing what the selected theme looks like.
private struct ThemePreview: View {
    let theme: Theme
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search…")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
                Text("Selected result")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(accent.opacity(0.15))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
                Text("Another result")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(ThemeBackground(theme: theme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.3))
        }
    }
}

#Preview {
    SettingsView()
}
