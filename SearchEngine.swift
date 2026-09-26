import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
class SearchEngine: ObservableObject {
    @Published var results: [SearchResult] = []
    
    private var searchTask: Task<Void, Never>?
    
    var customScriptDirectory: URL {
        get {
            if let savedPath = UserDefaults.standard.string(forKey: "customScriptDirectory") {
                return URL(fileURLWithPath: savedPath)
            }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Scripts")
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: "customScriptDirectory")
        }
    }
    
    func search(query: String) {
        // Cancel previous search
        searchTask?.cancel()
        
        searchTask = Task {
            if query.isEmpty {
                // Show recent/default items
                results = await getDefaultResults()
            } else {
                results = await performSearch(query: query)
            }
        }
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
        
        // Search files
        let files = await searchFiles(query: query)
        allResults.append(contentsOf: files)
        
        // Check for script commands
        let scripts = await searchScripts(query: query)
        allResults.append(contentsOf: scripts)
        
        // Sort by relevance
        return allResults.sorted { $0.relevance > $1.relevance }
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
                action: { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) }
            )
        }
    }
    
    private func searchApplications(query: String) async -> [SearchResult] {
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        
        var results: [SearchResult] = []
        
        for dir in appDirs {
            guard let enumerator = FileManager.default.enumerator(atPath: dir) else { continue }
            
            for case let file as String in enumerator {
                guard file.hasSuffix(".app") else { continue }
                
                let fullPath = (dir as NSString).appendingPathComponent(file)
                let appName = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
                
                // Check if matches query
                let relevance = calculateRelevance(text: appName, query: query)
                guard relevance > 0 else { continue }
                
                if let bundle = Bundle(path: fullPath) {
                    let displayName = bundle.infoDictionary?["CFBundleName"] as? String ?? appName
                    let icon = NSWorkspace.shared.icon(forFile: fullPath)
                    
                    results.append(SearchResult(
                        title: displayName,
                        subtitle: fullPath,
                        type: .application,
                        icon: icon,
                        relevance: relevance,
                        action: { 
                            NSWorkspace.shared.openApplication(
                                at: URL(fileURLWithPath: fullPath),
                                configuration: NSWorkspace.OpenConfiguration()
                            )
                        }
                    ))
                }
                
                // Don't recurse into .app bundles
                if file.hasSuffix(".app") {
                    enumerator.skipDescendants()
                }
            }
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
                guard count < 20 else { break } // Limit results per directory
                
                let fileName = fileURL.lastPathComponent
                let relevance = calculateRelevance(text: fileName, query: query)
                
                guard relevance > 0.3 else { continue }
                
                let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                
                results.append(SearchResult(
                    title: fileName,
                    subtitle: fileURL.path,
                    type: .file,
                    icon: icon,
                    relevance: relevance,
                    fileURL: fileURL,
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
        
        // Search for .sh, .command, .py, .rb scripts in user directories
        var scriptDirs = [
            customScriptDirectory, // Use custom directory
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
        ]
        
        let scriptExtensions = ["sh", "command", "py", "rb", "js", "swift"]
        
        for dir in scriptDirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.nameKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                guard scriptExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                
                let fileName = fileURL.lastPathComponent
                let relevance = calculateRelevance(text: fileName, query: query)
                
                guard relevance > 0.3 else { continue }
                
                results.append(SearchResult(
                    title: fileName,
                    subtitle: fileURL.path,
                    type: .script,
                    systemIcon: "terminal.fill",
                    relevance: relevance,
                    action: {
                        self.executeScript(at: fileURL)
                    }
                ))
            }
        }
        
        return results
    }
    
    private func calculateRelevance(text: String, query: String) -> Double {
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
                relevance: emoji.relevance,
                action: {
                    // Copy emoji to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(emoji.emoji, forType: .string)
                    
                    // Show notification
                    Task { @MainActor in
                        let notification = NSUserNotification()
                        notification.title = "Emoji Copied"
                        notification.informativeText = "\(emoji.emoji) copied to clipboard"
                        NSUserNotificationCenter.default.deliver(notification)
                    }
                }
            )
        }
    }
}

