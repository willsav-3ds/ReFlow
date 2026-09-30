import SwiftUI
import AppKit

struct LauncherView: View {
    @ObservedObject private var searchEngine = SearchEngine.shared
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @ObservedObject private var windowController = LauncherWindowController.shared
    @State private var searchText = ""
    @State private var selectedResult: SearchResult?
    @State private var showingFileActions = false
    @State private var fileToManage: URL?
    @State private var launcherKeyMonitor: Any?
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: searchBarIconName)
                    .foregroundStyle(.secondary)

                TextField(searchBarPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        // `results` may still reflect the *previous* query: typing debounces
                        // for a beat before a search actually runs, and Enter can land inside
                        // that window. Wait for whatever's in flight so we act on results for
                        // what's actually in the field, not whatever was there a moment ago.
                        Task {
                            await searchEngine.waitForPendingSearch()
                            if let firstResult = searchEngine.results.first {
                                execute(firstResult)
                            }
                        }
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Mode toggle
                Button(action: { searchEngine.toggleMode() }) {
                    Image(systemName: searchEngine.searchMode == .emoji ? "command" : "face.smiling")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(searchEngine.searchMode == .emoji
                      ? "Switch to launcher (\(shortcuts.binding(for: .toggleEmojiMode).displayString))"
                      : "Switch to emoji search (\(shortcuts.binding(for: .toggleEmojiMode).displayString))")

                // Settings
                Button(action: { closeWindow(); SettingsOpener.open() }) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings (\(shortcuts.binding(for: .openSettings).displayString))")
            }
            .padding()
            .background(WindowDragHandle())

            Divider()

            // Results list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(searchEngine.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isSelected: index == 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if result.type == .file {
                                    selectedResult = result
                                    if let subtitle = result.subtitle {
                                        fileToManage = URL(fileURLWithPath: subtitle)
                                    }
                                    showingFileActions = true
                                } else {
                                    execute(result)
                                }
                            }
                            .contextMenu {
                                if result.type == .file, let fileURL = result.fileURL {
                                    Button("Open") {
                                        execute(result)
                                    }
                                    Button("Show in Finder (\(shortcuts.binding(for: .showInFinderTopResult).displayString) for top result)") {
                                        FileOps.showInFinder(fileURL)
                                        closeWindow()
                                    }
                                    Button("Move to... (\(shortcuts.binding(for: .moveTopResult).displayString) for top result)") {
                                        FileOps.moveWithPicker(fileURL) {
                                            searchEngine.search(query: searchText)
                                        }
                                    }
                                    Divider()
                                    Button("Move to Trash (\(shortcuts.binding(for: .trashTopResult).displayString) for top result)", role: .destructive) {
                                        FileOps.trash(fileURL)
                                        searchEngine.search(query: searchText)
                                    }
                                    Divider()
                                }
                                if let rankingKey = result.rankingKey {
                                    Button("Reset Ranking") {
                                        RankingStore.shared.reset(rankingKey)
                                        searchEngine.search(query: searchText)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .background(.regularMaterial)
        .frame(width: 600, height: 450)
        .onChange(of: searchText) { _, newValue in
            searchEngine.search(query: newValue)
        }
        .onAppear {
            installLauncherKeyMonitor()
            // Registers the real `openSettings` environment action for `SettingsOpener`
            // to use — this view is the one place in the app that already has it, so
            // AppKit-only code with no SwiftUI environment of its own (like the status
            // item's right-click menu) can still reach it.
            SettingsOpener.openAction = {
                closeWindow()
                openSettings()
            }
        }
        .onDisappear {
            removeLauncherKeyMonitor()
        }
        .onChange(of: windowController.isVisible) { _, visible in
            // The panel and this view are reused across show/hide cycles, so refresh
            // explicitly on every reopen instead of relying on onAppear (which won't refire).
            guard visible else { return }
            searchText = ""
            isSearchFieldFocused = true
            searchEngine.search(query: "")
        }
        .sheet(isPresented: $showingFileActions) {
            if let fileURL = fileToManage {
                FileActionsView(fileURL: fileURL, isPresented: $showingFileActions) {
                    closeWindow()
                }
            }
        }
    }

    // MARK: - Keyboard-driven top-result actions

    private func installLauncherKeyMonitor() {
        guard launcherKeyMonitor == nil else { return }
        launcherKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape: back out of File Search/emoji mode first, then close the launcher.
            if event.keyCode == 53 {
                if searchEngine.searchMode != .launcher {
                    searchEngine.searchMode = .launcher
                    searchText = ""
                    searchEngine.search(query: "")
                } else {
                    closeWindow()
                }
                return nil
            }

            guard let action = shortcuts.action(matching: event, scope: .launcher) else {
                return event
            }
            handleLauncherAction(action)
            return nil
        }
    }

    private func removeLauncherKeyMonitor() {
        if let monitor = launcherKeyMonitor {
            NSEvent.removeMonitor(monitor)
            launcherKeyMonitor = nil
        }
    }

    private func handleLauncherAction(_ action: ShortcutAction) {
        switch action {
        case .trashTopResult:
            // Same stale-results race as `onSubmit` below — wait for any in-flight search
            // before trusting `results.first`.
            Task {
                await searchEngine.waitForPendingSearch()
                guard let fileURL = searchEngine.results.first?.fileURL else { return }
                FileOps.trash(fileURL)
                searchEngine.search(query: searchText)
            }
        case .moveTopResult:
            Task {
                await searchEngine.waitForPendingSearch()
                guard let fileURL = searchEngine.results.first?.fileURL else { return }
                FileOps.moveWithPicker(fileURL) {
                    searchEngine.search(query: searchText)
                }
            }
        case .showInFinderTopResult:
            Task {
                await searchEngine.waitForPendingSearch()
                guard let fileURL = searchEngine.results.first?.fileURL else { return }
                FileOps.showInFinder(fileURL)
            }
        case .openSettings:
            // The launcher panel floats above normal windows (so it stays visible while
            // tiling apps etc.), which meant Settings — an ordinary window — was opening
            // *behind* it: pressing ⌘, while the launcher was up looked like nothing
            // happened, when Settings had actually opened, just hidden from view. Close
            // the launcher first so Settings actually ends up on top. Going through
            // `SettingsOpener.open()` (rather than calling `openSettings()` directly) is
            // what makes an already-open Settings window get closed and reopened on the
            // current desktop instead of just revealed wherever it was left.
            closeWindow()
            SettingsOpener.open()
        default:
            break
        }
    }

    private func closeWindow() {
        searchText = ""
        LauncherWindowController.shared.hide()
    }

    /// Runs a result's action. Mode-switch entries like "File Search" (`.command`) stay
    /// open since nothing was actually launched; everything else closes the window after.
    private func execute(_ result: SearchResult) {
        result.execute()
        if result.type == .command {
            // A command result switches modes rather than launching anything — clear the
            // field so it doesn't keep showing e.g. "fs" once we're in the new mode.
            searchText = ""
        } else {
            closeWindow()
        }
    }

    private var searchBarIconName: String {
        switch searchEngine.searchMode {
        case .emoji: return "face.smiling"
        case .fileSearch: return "folder"
        case .launcher: return "magnifyingglass"
        case .clipboardHistory: return "doc.on.clipboard"
        }
    }

    private var searchBarPlaceholder: String {
        switch searchEngine.searchMode {
        case .emoji: return "Search emoji and stickers..."
        case .fileSearch: return "Search files or enter a path..."
        case .launcher: return "Search apps, scripts, or type fs for File Search..."
        case .clipboardHistory: return "Search clipboard history..."
        }
    }
}

/// Lets the borderless launcher window be dragged from empty parts of its own content,
/// since a SwiftUI-hosted window covers the whole frame and `isMovableByWindowBackground`
/// alone has nothing left to claim as "background."
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Shared file operations used by both the context menu and the keyboard shortcuts
/// that act on the top search result.
enum FileOps {
    static func trash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }

    static func moveWithPicker(_ url: URL, completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"

        if panel.runModal() == .OK, let destination = panel.url {
            let destinationURL = destination.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.moveItem(at: url, to: destinationURL)
            completion?()
        }
    }

    static func duplicate(_ url: URL) {
        let destinationURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + " copy")
            .appendingPathExtension(url.pathExtension)
        try? FileManager.default.copyItem(at: url, to: destinationURL)
    }
}

struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            if let icon = result.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else if let emoji = result.emoji {
                Text(emoji)
                    .font(.system(size: 32))
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: result.systemIcon ?? "questionmark.circle")
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            // Type badge
            Text(result.type.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isHovering ? Color.accentColor.opacity(0.1) :
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct FileActionsView: View {
    let fileURL: URL
    @Binding var isPresented: Bool
    let onComplete: () -> Void
    @State private var showingDestinationPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                .resizable()
                .frame(width: 64, height: 64)
            
            Text(fileURL.lastPathComponent)
                .font(.headline)
            
            Text(fileURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 10) {
                Button("Open") {
                    NSWorkspace.shared.open(fileURL)
                    isPresented = false
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Show in Finder") {
                    FileOps.showInFinder(fileURL)
                    isPresented = false
                    onComplete()
                }

                Button("Move to...") {
                    FileOps.moveWithPicker(fileURL) {
                        isPresented = false
                        onComplete()
                    }
                }

                Button("Duplicate") {
                    FileOps.duplicate(fileURL)
                    isPresented = false
                }

                Divider()

                Button("Move to Trash", role: .destructive) {
                    FileOps.trash(fileURL)
                    isPresented = false
                    onComplete()
                }
            }
            .frame(width: 200)
        }
        .padding()
        .frame(width: 300, height: 400)
    }
}

#Preview {
    LauncherView()
        .frame(width: 600, height: 450)
}
