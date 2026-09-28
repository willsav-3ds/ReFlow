import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine

enum SearchMode {
    case launcher
    case emoji
    case fileSearch
}

@MainActor
class SearchEngine: ObservableObject {
    @Published var results: [SearchResult] = []
    @Published var searchMode: SearchMode = .launcher

    private var searchTask: Task<Void, Never>?
    private var lastQuery: String = ""

    /// Built once on first use instead of re-walking `/Applications` on every keystroke.
    private var cachedApps: [CachedApp]?
    private var iconCache: [String: NSImage] = [:]

    private struct CachedApp {
        let title: String
        let path: String
        let icon: NSImage
    }

    /// Folders scripts are searched in. Fully user-managed (Settings → Scripts) — nothing
    /// is scanned automatically beyond this list, defaulting to `~/Scripts` until edited.
    /// Static (not per-instance) so Settings can read/write it without needing a
    /// `SearchEngine` of its own — it's really just a thin, typed view onto UserDefaults.
    static var scriptSearchPaths: [String] {
        get {
            if let saved = UserDefaults.standard.stringArray(forKey: scriptPathsDefaultsKey) {
                return saved
            }
            return [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Scripts").path]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: scriptPathsDefaultsKey)
        }
    }
    private static let scriptPathsDefaultsKey = "scriptSearchPaths"
    
    func search(query: String) {
        // Cancel previous search
        searchTask?.cancel()
        lastQuery = query

        searchTask = Task {
            // Debounce: wait a beat for more keystrokes before doing any real work.
            // Skipped for an empty query so clearing the field shows defaults instantly.
            if !query.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    return // superseded before the debounce even elapsed
                }
            }
            guard !Task.isCancelled else { return }

            let newResults: [SearchResult]
            switch searchMode {
            case .emoji:
                newResults = searchEmojis(query: query)
            case .fileSearch:
                // Don't dump every file in Documents the instant the mode opens.
                newResults = query.isEmpty ? [] : await performFileSearch(query: query)
            case .launcher:
                if query.isEmpty {
                    // Show recent/default items
                    newResults = await getDefaultResults()
                } else if query.trimmingCharacters(in: .whitespaces).lowercased() == "fs" {
                    newResults = [fileSearchCommandResult()]
                } else {
                    newResults = await performSearch(query: query)
                }
            }

            // A slower, superseded search must never clobber fresher results.
            guard !Task.isCancelled else { return }
            // Usage-based ranking: nudge frequently-launched items up, without letting
            // the boost outweigh genuine text relevance (see RankingStore.boostScore).
            results = newResults.sorted {
                $0.relevance + RankingStore.shared.boostScore(for: $0.rankingKey) >
                $1.relevance + RankingStore.shared.boostScore(for: $1.rankingKey)
            }
        }
    }

    func toggleMode() {
        searchMode = (searchMode == .emoji) ? .launcher : .emoji
        search(query: lastQuery)
    }
    
    private func performSearch(query: String) async -> [SearchResult] {
        var allResults: [SearchResult] = []
        
        // Check for emoji search (starts with :)
        if query.hasPrefix(":") {
            let emojiResults = searchEmojis(query: String(query.dropFirst()))
            allResults.append(contentsOf: emojiResults)
            return allResults.sorted { $0.relevance > $1.relevance }
        }
        
        // Search applications
        let apps = await searchApplications(query: query)
        allResults.append(contentsOf: apps)

        // Check for script commands
        let scripts = await searchScripts(query: query)
        allResults.append(contentsOf: scripts)

        // Search quick links
        let quickLinks = searchQuickLinks(query: query)
        allResults.append(contentsOf: quickLinks)

        // Sort by relevance
        return allResults.sorted { $0.relevance > $1.relevance }
    }

    private func searchQuickLinks(query: String) -> [SearchResult] {
        QuickLinkStore.shared.links.compactMap { link in
            let relevance = Self.calculateRelevance(text: link.name, query: query)
            guard relevance > 0 else { return nil }

            let target = link.target
            return SearchResult(
                title: link.name,
                subtitle: target,
                type: .quickLink,
                systemIcon: "link",
                relevance: relevance,
                rankingKey: "quicklink:\(target)",
                action: {
                    QuickLinkStore.open(target)
                }
            )
        }
    }
    
    private func fileSearchCommandResult() -> SearchResult {
        SearchResult(
            title: "File Search",
            subtitle: "Search files by name or enter a path",
            type: .command,
            systemIcon: "folder",
            relevance: 1.0,
            action: {
                self.searchMode = .fileSearch
                self.search(query: "")
            }
        )
    }

    private func performFileSearch(query: String) async -> [SearchResult] {
        let expandedPath = (query as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            let url = URL(fileURLWithPath: expandedPath)
            return [SearchResult(
                title: url.lastPathComponent,
                subtitle: expandedPath,
                type: .file,
                icon: icon(for: expandedPath),
                relevance: 1.0,
                fileURL: url,
                rankingKey: expandedPath,
                action: {
                    NSWorkspace.shared.open(url)
                }
            )]
        }

        return await searchFiles(query: query)
    }

    private func getDefaultResults() async -> [SearchResult] {
        // Return frequently used apps
        let appPaths = [
            "/System/Applications/Safari.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app",
            "/Applications/Xcode.app",
        ]
        
        return appPaths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path),
                  let bundle = Bundle(path: path) else { return nil }
            
            let name = bundle.infoDictionary?["CFBundleName"] as? String ?? 
                       URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: path)
            
            return SearchResult(
                title: name,
                subtitle: path,
                type: .application,
                icon: icon,
                relevance: 0.5,
                rankingKey: path,
                action: { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) }
            )
        }
    }
    
    private func loadApps() async -> [CachedApp] {
        if let cachedApps { return cachedApps }

        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        var apps: [CachedApp] = []

        for dir in appDirs {
            guard let enumerator = FileManager.default.enumerator(atPath: dir) else { continue }

            for case let file as String in enumerator {
                guard file.hasSuffix(".app") else { continue }

                let fullPath = (dir as NSString).appendingPathComponent(file)
                let appName = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent

                if let bundle = Bundle(path: fullPath) {
                    let displayName = bundle.infoDictionary?["CFBundleName"] as? String ?? appName
                    let icon = NSWorkspace.shared.icon(forFile: fullPath)
                    apps.append(CachedApp(title: displayName, path: fullPath, icon: icon))
                }

                // Don't recurse into .app bundles
                enumerator.skipDescendants()
            }
        }

        cachedApps = apps
        return apps
    }

    private func searchApplications(query: String) async -> [SearchResult] {
        let apps = await loadApps()
        var results: [SearchResult] = []

        for app in apps {
            if Task.isCancelled { return [] }

            let relevance = Self.calculateRelevance(text: app.title, query: query)
            guard relevance > 0 else { continue }

            let path = app.path
            results.append(SearchResult(
                title: app.title,
                subtitle: path,
                type: .application,
                icon: app.icon,
                relevance: relevance,
                rankingKey: path,
                action: {
                    NSWorkspace.shared.openApplication(
                        at: URL(fileURLWithPath: path),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
            ))
        }

        return results
    }
    
    private func searchFiles(query: String) async -> [SearchResult] {
        var results: [SearchResult] = []
        
        // Search common directories
        let searchDirs = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
        ]
        
        for dir in searchDirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            
            var count = 0
            for case let fileURL as URL in enumerator {
                if Task.isCancelled { return [] }
                guard count < 20 else { break } // Limit results per directory

                let fileName = fileURL.lastPathComponent
                let textRelevance = Self.calculateRelevance(text: fileName, query: query)

                // Threshold on text relevance alone — recency should never let an
                // otherwise-irrelevant file leak through, only break ties/near-ties in
                // favor of whatever was added or changed more recently.
                guard textRelevance > 0.3 else { continue }

                let icon = icon(for: fileURL.path)

                results.append(SearchResult(
                    title: fileName,
                    subtitle: fileURL.path,
                    type: .file,
                    icon: icon,
                    relevance: textRelevance + Self.recencyBonus(for: fileURL),
                    fileURL: fileURL,
                    rankingKey: fileURL.path,
                    action: {
                        NSWorkspace.shared.open(fileURL)
                    }
                ))

                count += 1
            }
        }
        
        return results
    }
    
    private func searchScripts(query: String) async -> [SearchResult] {
        var results: [SearchResult] = []
        
        // Check if it looks like a shell command
        if query.starts(with: ">") || query.starts(with: "$") || query.starts(with: "!") {
            let command = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
            
            if !command.isEmpty {
                results.append(SearchResult(
                    title: "Run: \(command)",
                    subtitle: "Execute shell command",
                    type: .script,
                    systemIcon: "terminal",
                    relevance: 1.0,
                    action: {
                        self.executeShellCommand(command)
                    }
                ))
            }
        }
        
        // Search only the folders configured in Settings → Scripts — nothing else is
        // scanned automatically.
        let scriptDirs = Self.scriptSearchPaths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

        let scriptExtensions = ["sh", "command", "py", "rb", "js", "swift"]

        for dir in scriptDirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.nameKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                if Task.isCancelled { return [] }
                guard scriptExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

                let fileName = fileURL.lastPathComponent
                let relevance = Self.calculateRelevance(text: fileName, query: query)
                
                guard relevance > 0.3 else { continue }
                
                results.append(SearchResult(
                    title: fileName,
                    subtitle: fileURL.path,
                    type: .script,
                    systemIcon: "terminal.fill",
                    relevance: relevance,
                    rankingKey: fileURL.path,
                    action: {
                        self.executeScript(at: fileURL)
                    }
                ))
            }
        }
        
        return results
    }
    
    private func icon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = icon
        return icon
    }

    /// A small, decaying bonus for files added or changed recently — so among similar
    /// text matches, something downloaded yesterday outranks something untouched for
    /// years. Capped well below a full relevance tier so it only breaks ties/near-ties,
    /// never promotes an irrelevant match past a genuine one.
    static func recencyBonus(for url: URL) -> Double {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
        guard let date = values?.addedToDirectoryDate ?? values?.contentModificationDate else {
            return 0
        }
        let ageInDays = max(0, Date().timeIntervalSince(date) / 86400)
        let maxBonus = 0.3
        let decayDays = 365.0
        return max(0, maxBonus - min(ageInDays, decayDays) / decayDays * maxBonus)
    }

    static func calculateRelevance(text: String, query: String) -> Double {
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()
        
        // Exact match
        if lowerText == lowerQuery {
            return 1.0
        }
        
        // Starts with
        if lowerText.hasPrefix(lowerQuery) {
            return 0.9
        }
        
        // Contains
        if lowerText.contains(lowerQuery) {
            return 0.7
        }
        
        // Fuzzy match (all characters present in order)
        var queryIndex = lowerQuery.startIndex
        for char in lowerText {
            if queryIndex < lowerQuery.endIndex && char == lowerQuery[queryIndex] {
                queryIndex = lowerQuery.index(after: queryIndex)
            }
        }
        
        if queryIndex == lowerQuery.endIndex {
            return 0.5
        }
        
        return 0.0
    }
    
    private func executeShellCommand(_ command: String) {
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    // Show output in a dialog
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Command Output"
                        alert.informativeText = output
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Error"
                    alert.informativeText = "Failed to execute command: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    private func executeScript(at url: URL) {
        Task {
            let process = Process()
            
            // Determine how to execute based on extension
            switch url.pathExtension.lowercased() {
            case "sh", "command":
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [url.path]
            case "py":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [url.path]
            case "rb":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
                process.arguments = [url.path]
            case "js":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-l", "JavaScript", url.path]
            case "swift":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
                process.arguments = [url.path]
            default:
                return
            }
            
            do {
                try process.run()
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Error"
                    alert.informativeText = "Failed to execute script: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    private func searchEmojis(query: String) -> [SearchResult] {
        let emojis = EmojiDatabase.shared.search(query: query)
        
        return emojis.map { emoji in
            SearchResult(
                title: emoji.emoji,
                subtitle: emoji.keywords.joined(separator: ", "),
                type: .emoji,
                systemIcon: "face.smiling",
                emoji: emoji.emoji,
                relevance: emoji.relevance,
                rankingKey: "emoji:\(emoji.emoji)",
                action: {
                    // Copy emoji to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(emoji.emoji, forType: .string)
                }
            )
        }
    }
}

