import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Combine

enum SearchMode {
    case launcher
    case emoji
    case fileSearch
    case clipboardHistory
}

@MainActor
class SearchEngine: ObservableObject {
    /// A singleton (like `ShortcutStore`/`QuickLinkStore`/`RankingStore`) rather than a
    /// view-owned `@StateObject`, so the global emoji-picker hotkey (handled in
    /// `AppDelegate`, well outside the view hierarchy) can force `searchMode` and kick off
    /// a search before the launcher window even appears.
    static let shared = SearchEngine()

    @Published var results: [SearchResult] = []
    @Published var searchMode: SearchMode = .launcher
    /// Which row of `results` the arrow keys have moved to — what Enter and the
    /// selected-result shortcuts (Trash / Move to… / Show in Finder) act on. Lives here
    /// rather than in `LauncherView` so it resets in the same step as `results` itself:
    /// anything that waits out a pending search (see `waitForPendingSearch`) and then
    /// reads `selectedResult` can never see fresh results paired with a stale index.
    @Published var selectedIndex = 0

    var selectedResult: SearchResult? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    private init() {}

    private var searchTask: Task<Void, Never>?
    private var lastQuery: String = ""

    /// Built once on first use instead of re-walking `/Applications` on every keystroke,
    /// then rebuilt only when `appDirectoriesChanged()` says something was installed or
    /// removed since.
    private var cachedApps: [CachedApp]?
    /// Modification date of each app folder root and its direct subfolders (like
    /// `/Applications/KiCad`), keyed by path. A folder's mtime changes whenever an entry
    /// is added to or removed from it, so comparing these is a few dozen `stat`s — far
    /// cheaper than a filesystem watcher or a periodic rescan, and it catches a new
    /// download the next time you search. Deliberately only one level deep: the scan
    /// itself walks every nested folder, and tracking all of those (Unity's install
    /// alone is well over a thousand, and game folders churn whenever they patch) made
    /// the check slow enough to lag typing and kept triggering needless full rescans.
    private var appScanDirectoryDates: [String: Date?] = [:]
    /// Throttles `appDirectoriesChanged()` — searches fire on nearly every keystroke,
    /// but a new install only needs to be noticed within a second or two.
    private var lastAppDirectoryCheck = Date.distantPast
    private static let appDirectoryCheckInterval: TimeInterval = 2
    /// The scan currently filling `cachedApps`, if any — shared so concurrent searches
    /// wait on one scan instead of each starting their own.
    private var appScanTask: Task<[CachedApp], Never>?
    private var stickerIconCache: [String: NSImage] = [:]

    /// Script files found in `scriptSearchPaths`, rescanned in the background each time
    /// the launcher opens (see `search(query:)`) rather than walked on every keystroke.
    private var cachedScripts: [URL]?
    private var scriptScanTask: Task<[URL], Never>?

    /// Plain values, so the scan that builds them can run off the main thread. Icons
    /// aren't part of it: they're loaded lazily by `ResultRow`, only for rows actually
    /// on screen (see `IconCache`).
    nonisolated struct CachedApp: Sendable {
        let title: String
        let path: String
    }

    /// The most results a search ever shows. Short or fuzzy queries can match hundreds
    /// of apps or files; nobody scrolls that far, and every extra row is SwiftUI work.
    private static let maxResults = 50

    /// Read-only snapshot of the in-memory caches above, for the debug stats window only
    /// — nothing here is read by search itself. `apps` is `nil` until the app scan
    /// (started at launch by `warmUp()`) has finished.
    var cacheStats: (apps: Int?, icons: Int, stickerIcons: Int) {
        (cachedApps?.count, IconCache.shared.count, stickerIconCache.count)
    }

    /// Builds the app list in the background at launch, so the very first search after
    /// starting ReFlow doesn't have to wait for it.
    func warmUp() {
        if cachedApps == nil && appScanTask == nil {
            startAppScan()
        }
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

    /// Off by default: File Search walks every file in Documents/Downloads/Desktop, so a
    /// query is guaranteed to find every match, no matter how large those folders are —
    /// at the cost of a search potentially taking a while in an especially large folder.
    /// Turning this on (Settings → File Search) caps how many files it's willing to look
    /// at per folder instead, trading that guarantee for results that stay fast no matter
    /// how big the folder is.
    static var limitFileSearchScope: Bool {
        get { UserDefaults.standard.bool(forKey: limitFileSearchDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: limitFileSearchDefaultsKey) }
    }
    private static let limitFileSearchDefaultsKey = "limitFileSearchScope"
    private static let fileSearchScopeLimit = 2000

    /// Folders File Search (and its empty-query recent-files default list) looks in.
    /// User-managed (Settings → File Search), defaulting to Downloads/Documents/Desktop
    /// until edited — mirrors `scriptSearchPaths` above.
    static var fileSearchPaths: [String] {
        get {
            if let saved = UserDefaults.standard.stringArray(forKey: fileSearchPathsDefaultsKey) {
                return saved
            }
            return defaultFileSearchPaths
        }
        set {
            UserDefaults.standard.set(newValue, forKey: fileSearchPathsDefaultsKey)
        }
    }
    private static let fileSearchPathsDefaultsKey = "fileSearchPaths"
    private static var defaultFileSearchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Downloads").path,
            home.appendingPathComponent("Documents").path,
            home.appendingPathComponent("Desktop").path,
        ]
    }

    func search(query: String) {
        // Cancel previous search
        searchTask?.cancel()
        lastQuery = query

        // An empty launcher query means the launcher just opened (or was cleared):
        // pick up scripts added since last time, in the background, so typing itself
        // only ever filters what's already in memory.
        if query.isEmpty && searchMode == .launcher {
            refreshScripts()
        }

        searchTask = Task {
            // Debounce: only File Search still walks the disk per query, so only it waits
            // a beat for more keystrokes first. Every other mode filters in-memory data
            // and answers instantly — debouncing those just added lag to every keystroke.
            if !query.isEmpty && searchMode == .fileSearch {
                do {
                    try await Task.sleep(for: .milliseconds(80))
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
                // An empty query still shows something useful — recently added/changed
                // files — rather than the blank list this used to show, so landing in
                // File Search (e.g. via "fs" + Enter) greets you with what's probably on
                // your mind instead of nothing.
                newResults = query.isEmpty ? await getDefaultFileResults() : await performFileSearch(query: query)
            case .clipboardHistory:
                newResults = clipboardHistoryResults(query: query)
            case .launcher:
                let trimmedLower = query.trimmingCharacters(in: .whitespaces).lowercased()
                if query.isEmpty {
                    // Show recent/default items
                    newResults = await getDefaultResults()
                } else if trimmedLower == "fs" {
                    newResults = [fileSearchCommandResult()]
                } else if trimmedLower == "cb", ClipboardHistoryStore.shared.isEnabled {
                    // Only offer this mode switch if the (opt-in, off-by-default) feature
                    // is actually turned on in Settings.
                    newResults = [clipboardHistoryCommandResult()]
                } else if CalculatorEngine.looksLikeExpression(query) {
                    // A query that's shaped like a math expression (digits/operators
                    // only) is never a real app/file/script match, so it fully replaces
                    // the usual search rather than being mixed in with it — including
                    // showing nothing while it's mid-typed and not yet a valid expression
                    // (e.g. "12+"), rather than briefly flashing unrelated results.
                    newResults = calculatorResult(for: query).map { [$0] } ?? []
                } else {
                    newResults = await performSearch(query: query)
                }
            }

            // A slower, superseded search must never clobber fresher results.
            guard !Task.isCancelled else { return }
            // Usage-based ranking: nudge frequently-launched items up, without letting
            // the boost outweigh genuine text relevance (see RankingStore.boostScore).
            // Scores are computed once per result rather than inside the comparator.
            results = newResults
                .map { ($0, $0.relevance + RankingStore.shared.boostScore(for: $0.rankingKey)) }
                .sorted { $0.1 > $1.1 }
                .prefix(Self.maxResults)
                .map(\.0)
            selectedIndex = 0
        }
    }

    /// Waits for whatever search is currently in flight — including its debounce delay —
    /// to finish. Callers that act on `results` right after a keystroke (like submitting
    /// the top result on Enter) need this: without it, they'd read whatever `results`
    /// held *before* the debounce for the just-typed character had even elapsed, and end
    /// up acting on a stale, previous query's top result instead of the current one.
    func waitForPendingSearch() async {
        await searchTask?.value
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

        // Built-in "Camera" utility — a live mirror window, mixed in alongside apps/
        // quick links so partial typing ("cam") surfaces it too, not just the exact word.
        if let camera = cameraCommandResult(query: query) {
            allResults.append(camera)
        }

        // Window commands ("next desktop", "left half", …)
        allResults.append(contentsOf: windowCommandResults(query: query))

        // Sort by relevance
        return allResults.sorted { $0.relevance > $1.relevance }
    }

    /// Every window action that has a shortcut can also be run by name: type "next
    /// desktop" or "left half" and press Return. It acts on the window that was in front
    /// when the launcher opened, since the launcher never takes over as the active app.
    private func windowCommandResults(query: String) -> [SearchResult] {
        ShortcutAction.allCases.compactMap { action in
            guard action.isLauncherCommand else { return nil }
            let relevance = ([action.displayName] + action.searchAliases)
                .map { Self.calculateRelevance(text: $0, query: query) }
                .max() ?? 0
            // Stricter than apps (anything above zero): there are a couple of dozen of
            // these with long, similar names, and a loose in-order letter match would have
            // most of them turning up for nearly any short query.
            guard relevance > 0.5 else { return nil }

            return SearchResult(
                title: action.displayName,
                subtitle: "Shortcut: \(ShortcutStore.shared.binding(for: action).displayString)",
                type: .windowAction,
                systemIcon: action.symbolName,
                relevance: relevance,
                rankingKey: "action:\(action.rawValue)",
                action: {
                    // Out of the way first, then a beat for the window underneath to be
                    // the focused one again before anything asks which window that is.
                    LauncherWindowController.shared.hide()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        HotKeyCenter.shared.trigger(action)
                    }
                }
            )
        }
    }

    /// Opens a live self-view window (see `CameraView`) — ⌘C in that window copies the
    /// current frame, Return saves it to the Desktop.
    private func cameraCommandResult(query: String) -> SearchResult? {
        let relevance = Self.calculateRelevance(text: "Camera", query: query)
        guard relevance > 0 else { return nil }

        return SearchResult(
            title: "Camera",
            subtitle: "Live mirror — ⌘C copies the frame, Return saves it to the Desktop",
            type: .windowAction,
            systemIcon: "camera",
            relevance: relevance,
            action: {
                CameraWindowController.shared.show()
            }
        )
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

    private func clipboardHistoryCommandResult() -> SearchResult {
        SearchResult(
            title: "Clipboard History",
            subtitle: "Browse and paste recently copied items",
            type: .command,
            systemIcon: "doc.on.clipboard",
            relevance: 1.0,
            action: {
                self.searchMode = .clipboardHistory
                self.search(query: "")
            }
        )
    }

    /// The inline calculator: typing a math expression shows the answer as the sole
    /// result, and running it (Enter, or a click, same as any other result) copies the
    /// answer to the clipboard instead of opening anything.
    private func calculatorResult(for query: String) -> SearchResult? {
        guard let value = CalculatorEngine.evaluate(query) else { return nil }
        let answer = CalculatorEngine.format(value)
        return SearchResult(
            title: "\(CalculatorEngine.prettyPrinted(query)) = \(answer)",
            subtitle: "Press Enter to copy \(answer) to the clipboard",
            type: .calculator,
            systemIcon: "equal",
            relevance: 1.0,
            action: {
                ClipboardPaste.copyText(answer)
            }
        )
    }

    private func clipboardHistoryResults(query: String) -> [SearchResult] {
        ClipboardHistoryStore.shared.entries.compactMap { entry in
            let relevance: Double
            if query.isEmpty {
                relevance = 0.5
            } else if let text = entry.text {
                relevance = Self.calculateRelevance(text: text, query: query)
            } else {
                // Image/GIF entries have no text to match a typed query against.
                relevance = 0
            }
            guard relevance > 0 else { return nil }

            return SearchResult(
                title: entry.text ?? "Copied image",
                subtitle: entry.text == nil ? nil : DateFormatter.localizedString(from: entry.date, dateStyle: .none, timeStyle: .short),
                type: .clipboardHistory,
                icon: entry.image,
                systemIcon: entry.text == nil ? "photo" : "doc.on.clipboard",
                relevance: relevance,
                action: {
                    ClipboardPaste.paste {
                        if let text = entry.text {
                            ClipboardPaste.copyText(text)
                        } else if let data = entry.rawData, let type = entry.rawType {
                            ClipboardPaste.copyRaw(data: data, type: type)
                        }
                    }
                }
            )
        }
    }

    private func performFileSearch(query: String) async -> [SearchResult] {
        let expandedPath = (query as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            let url = URL(fileURLWithPath: expandedPath)
            return [SearchResult(
                title: url.lastPathComponent,
                subtitle: expandedPath,
                type: .file,
                iconPath: expandedPath,
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

    /// File Search's default listing before any query is typed: whatever's most recently
    /// been added to or changed in the folders configured in Settings → File Search, so
    /// opening File Search greets you with what's probably on your mind (something you
    /// just downloaded or touched) instead of a blank list.
    private func getDefaultFileResults() async -> [SearchResult] {
        let mostRecent = await Self.recentFiles(in: Self.fileSearchPaths)

        // Relevance here isn't a text-match score — there's no query — so encode the
        // recency ranking directly into it, spaced widely enough that the usage-based
        // boost (see the sort in `search(query:)`) can still nudge a frequently-opened
        // file up without completely scrambling the recency order.
        return mostRecent.enumerated().map { index, url in
            SearchResult(
                title: url.lastPathComponent,
                subtitle: url.path,
                type: .file,
                iconPath: url.path,
                relevance: max(0.01, 1.0 - Double(index) * 0.01),
                fileURL: url,
                rankingKey: url.path,
                action: {
                    NSWorkspace.shared.open(url)
                }
            )
        }
    }

    /// The walk behind `getDefaultFileResults`, off the main thread.
    @concurrent
    private nonisolated static func recentFiles(in paths: [String]) async -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .addedToDirectoryDateKey, .contentModificationDateKey]
        var candidates: [(url: URL, date: Date)] = []

        for path in paths {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            var examined = 0
            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { return [] }
                // A soft cap on how many entries we look at per folder — sorting by date
                // needs a broad-enough scan to actually find the true most-recent files
                // (unlike a text search, there's no relevance filter to naturally bound
                // this), but an unbounded walk of a huge Documents folder isn't worth it
                // for a convenience default list.
                guard examined < 200 else { break }
                examined += 1

                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory != true else { continue }
                // Prefer contentModificationDate: addedToDirectoryDate reflects when a
                // file last landed in this folder (any move/copy/extract resets it), not
                // when it was actually created or edited — so an old file dragged onto
                // Desktop during a cleanup would otherwise look brand new here.
                guard let date = values?.contentModificationDate ?? values?.addedToDirectoryDate else { continue }
                candidates.append((fileURL, date))
            }
        }

        return candidates.sorted { $0.date > $1.date }.prefix(20).map(\.url)
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
            guard FileManager.default.fileExists(atPath: path) else { return nil }

            // Prefer the already-scanned name; reading Info.plist directly otherwise,
            // rather than via `Bundle(path:)`, which Foundation caches for the life of
            // the process.
            let name = cachedApps?.first(where: { $0.path == path })?.title ?? Self.appDisplayName(at: path)

            return SearchResult(
                title: name,
                subtitle: path,
                type: .application,
                iconPath: path,
                relevance: 0.5,
                rankingKey: path,
                action: { Self.launchApplication(at: path) }
            )
        }
    }
    
    /// Returns the cached app list immediately whenever there is one — starting a
    /// background rescan if the app folders changed, and serving the old list until it
    /// lands — so a search never waits on the disk except before the very first scan.
    private func loadApps() async -> [CachedApp] {
        if let cachedApps {
            if appScanTask == nil, appDirectoriesChanged() {
                startAppScan()
            }
            return cachedApps
        }
        if appScanTask == nil {
            startAppScan()
        }
        return await appScanTask?.value ?? []
    }

    private func startAppScan() {
        // Unstructured on purpose: a search being superseded mid-scan shouldn't throw
        // the scan away, since the next keystroke needs the same list.
        appScanTask = Task {
            let scan = await Self.scanApplications()
            cachedApps = scan.apps
            appScanDirectoryDates = scan.directoryDates
            lastAppDirectoryCheck = Date()
            appScanTask = nil
            return scan.apps
        }
    }

    /// The actual walk of the app folders, off the main thread.
    @concurrent
    private nonisolated static func scanApplications() async -> (apps: [CachedApp], directoryDates: [String: Date?]) {
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        var apps: [CachedApp] = []
        var directoryDates: [String: Date?] = [:]

        for dir in appDirs {
            // Recorded even when the folder doesn't exist (nil), so creating
            // ~/Applications later also counts as a change.
            directoryDates[dir] = modificationDate(ofPath: dir)
            guard let enumerator = FileManager.default.enumerator(atPath: dir) else { continue }

            while let file = enumerator.nextObject() as? String {
                guard file.hasSuffix(".app") else {
                    if enumerator.level == 1, enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                        directoryDates[(dir as NSString).appendingPathComponent(file)] = enumerator.fileAttributes?[.modificationDate] as? Date
                    }
                    continue
                }

                let fullPath = (dir as NSString).appendingPathComponent(file)
                apps.append(CachedApp(title: appDisplayName(at: fullPath), path: fullPath))

                // Don't recurse into .app bundles
                enumerator.skipDescendants()
            }
        }

        return (apps, directoryDates)
    }

    /// An app's `CFBundleName`, falling back to its file name.
    private nonisolated static func appDisplayName(at path: String) -> String {
        let info = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("Contents/Info.plist"))
        return info?["CFBundleName"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func appDirectoriesChanged() -> Bool {
        guard Date().timeIntervalSince(lastAppDirectoryCheck) >= Self.appDirectoryCheckInterval else { return false }
        lastAppDirectoryCheck = Date()
        return appScanDirectoryDates.contains { path, date in
            Self.modificationDate(ofPath: path) != date
        }
    }

    private nonisolated static func modificationDate(ofPath path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
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
                iconPath: path,
                relevance: relevance,
                rankingKey: path,
                action: {
                    Self.launchApplication(at: path)
                }
            ))
        }

        return results
    }

    /// Launches an app, surfacing failures instead of silently doing nothing — e.g. a
    /// freshly downloaded, still-quarantined app (like a Homebrew-installed KiCad) that
    /// LaunchServices refuses to open. Falls back to a plain `open`, which goes through
    /// the same path as double-clicking it in Finder (including the Gatekeeper
    /// "downloaded from the Internet" prompt), before giving up with an alert.
    static func launchApplication(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            print("ReFlow[launch]: openApplication failed for \(path): \(error.localizedDescription) — falling back to NSWorkspace.open.")
            DispatchQueue.main.async {
                guard !NSWorkspace.shared.open(url) else { return }
                let alert = NSAlert()
                alert.messageText = "Couldn't open \(url.deletingPathExtension().lastPathComponent)"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }
    
    private func searchFiles(query: String) async -> [SearchResult] {
        let hits = await Self.findFiles(
            matching: query,
            in: Self.fileSearchPaths,
            scopeLimit: Self.limitFileSearchScope ? Self.fileSearchScopeLimit : nil
        )
        return hits.map { hit in
            let fileURL = hit.url
            return SearchResult(
                title: fileURL.lastPathComponent,
                subtitle: fileURL.path,
                type: .file,
                iconPath: fileURL.path,
                relevance: hit.relevance,
                fileURL: fileURL,
                rankingKey: fileURL.path,
                action: {
                    NSWorkspace.shared.open(fileURL)
                }
            )
        }
    }

    nonisolated struct FileHit: Sendable {
        let url: URL
        let relevance: Double
    }

    /// The File Search walk itself, off the main thread so typing never stalls on the
    /// disk. Called from the search task with `await`, so it inherits that task's
    /// cancellation: a newer keystroke stops a stale walk partway through.
    @concurrent
    private nonisolated static func findFiles(matching query: String, in paths: [String], scopeLimit: Int?) async -> [FileHit] {
        var hits: [FileHit] = []

        for path in paths {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path),
                // The dates are prefetched for `recencyBonus`, so it doesn't go back to
                // the disk once per match.
                includingPropertiesForKeys: [.addedToDirectoryDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            var count = 0
            var examined = 0
            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { return [] }
                guard count < 20 else { break } // Limit results per directory
                // Only bail early on how many files we've looked at (as opposed to how many
                // matches we've kept) when the user's opted into it — otherwise a query with
                // few or no matches always walks every nested file in Documents/Downloads/
                // Desktop before giving up, however long that takes, so nothing is ever missed.
                if let scopeLimit {
                    guard examined < scopeLimit else { break }
                    examined += 1
                }

                let textRelevance = calculateRelevance(text: fileURL.lastPathComponent, query: query)

                // Threshold on text relevance alone — recency should never let an
                // otherwise-irrelevant file leak through, only break ties/near-ties in
                // favor of whatever was added or changed more recently.
                guard textRelevance > 0.3 else { continue }

                hits.append(FileHit(url: fileURL, relevance: textRelevance + recencyBonus(for: fileURL)))
                count += 1
            }
        }

        return hits
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
        
        for fileURL in await scriptURLs() {
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

        return results
    }

    /// The cached script list, waiting on a scan only if there's never been one.
    private func scriptURLs() async -> [URL] {
        if let cachedScripts { return cachedScripts }
        refreshScripts()
        return await scriptScanTask?.value ?? []
    }

    /// Rescans the script folders in the background, keeping the old list in use until
    /// the new one lands. A no-op while a scan is already running.
    private func refreshScripts() {
        guard scriptScanTask == nil else { return }
        let paths = Self.scriptSearchPaths
        scriptScanTask = Task {
            let scripts = await Self.scanScripts(in: paths)
            cachedScripts = scripts
            scriptScanTask = nil
            return scripts
        }
    }

    /// Search only the folders configured in Settings → Scripts — nothing else is
    /// scanned automatically. Off the main thread.
    @concurrent
    private nonisolated static func scanScripts(in paths: [String]) async -> [URL] {
        let scriptExtensions: Set<String> = ["sh", "command", "py", "rb", "js", "swift"]
        var scripts: [URL] = []

        for path in paths {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                includingPropertiesForKeys: [.nameKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                if scriptExtensions.contains(fileURL.pathExtension.lowercased()) {
                    scripts.append(fileURL)
                }
            }
        }

        return scripts
    }

    /// A small, decaying bonus for files added or changed recently — so among similar
    /// text matches, something downloaded yesterday outranks something untouched for
    /// years. Capped well below a full relevance tier so it only breaks ties/near-ties,
    /// never promotes an irrelevant match past a genuine one.
    nonisolated static func recencyBonus(for url: URL) -> Double {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
        // Prefer contentModificationDate over addedToDirectoryDate — see the matching
        // comment in getDefaultFileResults for why.
        guard let date = values?.contentModificationDate ?? values?.addedToDirectoryDate else {
            return 0
        }
        let ageInDays = max(0, Date().timeIntervalSince(date) / 86400)
        let maxBonus = 0.3
        let decayDays = 365.0
        return max(0, maxBonus - min(ageInDays, decayDays) / decayDays * maxBonus)
    }

    nonisolated static func calculateRelevance(text: String, query: String) -> Double {
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
            switch await Self.runShellCommand(command) {
            case .success(let output):
                guard !output.isEmpty else { return }
                // Show output in a dialog
                let alert = NSAlert()
                alert.messageText = "Command Output"
                alert.informativeText = output
                alert.alertStyle = .informational
                alert.runModal()
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Error"
                alert.informativeText = "Failed to execute command: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    /// Runs the command and waits for it off the main thread — waiting on it from the
    /// main actor froze the whole UI for as long as the command took.
    @concurrent
    private nonisolated static func runShellCommand(_ command: String) async -> Result<String, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // `-l` (login shell) makes zsh source `~/.zprofile`/`~/.zlogin` the same way
        // opening Terminal does. Without it, this only gets `/etc/zshenv`'s minimal
        // PATH — anything installed via Homebrew, pip, etc. (added to PATH in
        // `~/.zprofile`, the usual place) silently can't be found, since ReFlow itself
        // was launched by Finder/LaunchServices, not a login shell.
        process.arguments = ["-l", "-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            // Drain the pipe before waiting: a command writing more than the pipe's
            // buffer (~64 KB) would otherwise block forever waiting for a reader.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return .success(String(data: data, encoding: .utf8) ?? "")
        } catch {
            return .failure(error)
        }
    }

    private func executeScript(at url: URL) {
        let process = Process()

        // Determine how to execute based on extension
        switch url.pathExtension.lowercased() {
        case "sh", "command":
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // `-l` (login shell): see the matching comment in `executeShellCommand` — same
            // fix, same reason (a script that shells out to a Homebrew/pip-installed tool
            // otherwise can't find it, since ReFlow wasn't launched from a login shell).
            process.arguments = ["-l", url.path]
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

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // `Process`/`Pipe` (unlike `NSWorkspace`/`NSImage`) have no main-thread requirement,
        // so waiting for the script to finish here — needed to know whether it actually
        // succeeded — doesn't have to block the UI the way `executeShellCommand` does.
        Task.detached {
            do {
                try process.run()
                process.waitUntilExit()

                // A script that exits cleanly is meant to run and get out of the way (the
                // same "no-view" behavior Raycast scripts expect) — only a real failure is
                // worth interrupting anything for, not a dialog on every successful run.
                guard process.terminationStatus != 0 else { return }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Script exited with status \(process.terminationStatus)"
                    alert.informativeText = output.isEmpty ? "No output." : output
                    alert.alertStyle = .warning
                    alert.runModal()
                }
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
    
    /// Emoji mode's results are emoji plus the user's own custom stickers merged together
    /// — stickers are meant to be "searchable in the emojis," not a separate mode, per how
    /// this was asked for.
    private func searchEmojis(query: String) -> [SearchResult] {
        let emojiResults = EmojiDatabase.shared.search(query: query).map { emoji in
            SearchResult(
                title: emoji.emoji,
                subtitle: emoji.keywords.joined(separator: ", "),
                type: .emoji,
                systemIcon: "face.smiling",
                emoji: emoji.emoji,
                relevance: emoji.relevance,
                rankingKey: "emoji:\(emoji.emoji)",
                action: {
                    ClipboardPaste.paste { ClipboardPaste.copyEmoji(emoji.emoji) }
                }
            )
        }

        let stickerResults = StickerStore.shared.stickers.compactMap { sticker -> SearchResult? in
            // No query yet (just opened emoji mode) shows every sticker, same as
            // `EmojiDatabase.search` showing its first 24 entries for an empty query.
            let relevance = query.isEmpty ? 0.5 : Self.calculateRelevance(text: sticker.name, query: query)
            guard relevance > 0 else { return nil }

            let fileURL = StickerStore.shared.fileURL(for: sticker)
            return SearchResult(
                title: sticker.name,
                subtitle: sticker.isGIF ? "GIF Sticker" : "Sticker",
                type: .sticker,
                icon: stickerThumbnail(for: fileURL),
                systemIcon: "photo",
                relevance: relevance,
                rankingKey: "sticker:\(sticker.id.uuidString)",
                action: {
                    ClipboardPaste.paste { ClipboardPaste.copySticker(fileURL: fileURL) }
                }
            )
        }

        return (emojiResults + stickerResults).sorted { $0.relevance > $1.relevance }
    }

    /// A small, cached thumbnail of a sticker's actual image content (its first frame, for
    /// a GIF) — unlike a Finder icon by file type, this shows what the sticker actually
    /// looks like. Decoded straight to row size (64px, i.e. 32pt on Retina) rather than
    /// holding every sticker's full-size image or every frame of a GIF in memory.
    private func stickerThumbnail(for fileURL: URL) -> NSImage? {
        let key = fileURL.path
        if let cached = stickerIconCache[key] { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width / 2, height: thumbnail.height / 2))
        stickerIconCache[key] = image
        return image
    }
}

