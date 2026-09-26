import SwiftUI
import AppKit

struct LauncherView: View {
    @StateObject private var searchEngine = SearchEngine()
    @State private var searchText = ""
    @State private var selectedResult: SearchResult?
    @State private var showingFileActions = false
    @State private var fileToManage: URL?
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: searchEngine.searchMode == .emoji ? "face.smiling" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField(searchEngine.searchMode == .emoji ? "Search emoji..." : "Search apps, files, scripts, or window actions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        if let firstResult = searchEngine.results.first {
                            firstResult.execute()
                            closeWindow()
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
                .help(searchEngine.searchMode == .emoji ? "Switch to launcher" : "Switch to emoji search")
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Results list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(searchEngine.results) { result in
                        ResultRow(result: result)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if result.type == .file {
                                    selectedResult = result
                                    if let subtitle = result.subtitle {
                                        fileToManage = URL(fileURLWithPath: subtitle)
                                    }
                                    showingFileActions = true
                                } else {
                                    result.execute()
                                    closeWindow()
                                }
                            }
                            .contextMenu {
                                if result.type == .file, let subtitle = result.subtitle {
                                    Button("Open") {
                                        result.execute()
                                        closeWindow()
                                    }
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.selectFile(subtitle, inFileViewerRootedAtPath: "")
                                        closeWindow()
                                    }
                                    Divider()
                                    Button("Move to Trash", role: .destructive) {
                                        FileManager.default.trashItem(at: URL(fileURLWithPath: subtitle))
                                        searchEngine.search(query: searchText)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .frame(width: 600, height: 450)
        .onChange(of: searchText) { _, newValue in
            searchEngine.search(query: newValue)
        }
        .onAppear {
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
    
    private func closeWindow() {
        searchText = ""
        NSApp.hide(nil)
    }
}

struct ResultRow: View {
    let result: SearchResult
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
        .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
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
                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
                    isPresented = false
                    onComplete()
                }
                
                Button("Move to...") {
                    showMovePicker()
                }
                
                Button("Duplicate") {
                    duplicateFile()
                }
                
                Divider()
                
                Button("Move to Trash", role: .destructive) {
                    try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                    isPresented = false
                    onComplete()
                }
            }
            .frame(width: 200)
        }
        .padding()
        .frame(width: 300, height: 400)
    }
    
    func showMovePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        
        if panel.runModal() == .OK, let destination = panel.url {
            let destinationURL = destination.appendingPathComponent(fileURL.lastPathComponent)
            try? FileManager.default.moveItem(at: fileURL, to: destinationURL)
            isPresented = false
            onComplete()
        }
    }
    
    func duplicateFile() {
        let destinationURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + " copy")
            .appendingPathExtension(fileURL.pathExtension)
        try? FileManager.default.copyItem(at: fileURL, to: destinationURL)
        isPresented = false
    }
}

#Preview {
    LauncherView()
        .frame(width: 600, height: 450)
}
