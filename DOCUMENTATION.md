# ReFlow — Technical Documentation

This document describes ReFlow's internal architecture for anyone modifying the app. For a
user-facing overview, see [README.md](README.md).

## Overview

ReFlow is a SwiftUI + AppKit menu bar app with no Dock icon or regular windows. It's built
around a handful of singleton stores/engines (the standard pattern used throughout this
codebase — see [Singletons](#singletons-vs-state)) plus two AppKit-hosted SwiftUI surfaces:
a floating launcher panel and a standard `Settings` scene.

```
AppDelegate (MyApp.swift)
 ├─ status bar item (left-click toggles launcher, right-click shows menu)
 ├─ HotKeyCenter — global Carbon hotkeys → ShortcutAction
 └─ LauncherWindowController — owns the floating launcher NSPanel

LauncherView (ContentView.swift)
 ├─ search field bound to SearchEngine.results
 ├─ local key monitor for launcher-scoped shortcuts (Esc, trash/move/finder/settings)
 └─ ResultRow / FileActionsView / context menus

SearchEngine — the core: query → [SearchResult], per searchMode
 ├─ launcher mode: apps, scripts, quick links, calculator, mode-switch commands
 ├─ fileSearch mode: recursive search over configured folders
 ├─ emoji mode: EmojiDatabase + StickerStore, merged
 └─ clipboardHistory mode: ClipboardHistoryStore entries

WindowManager — AX-based window tiling, invoked directly by AppDelegate.perform(_:)
```

## Files

| File | Responsibility |
|---|---|
| `ReFlow/MyApp.swift` | App entry point, `AppDelegate` (status item, accessibility permission prompt, hotkey wiring, `ShortcutAction` dispatch), `LauncherPanel`/`LauncherWindowController` (the floating launcher window), `SettingsOpener` |
| `ReFlow/ContentView.swift` | `LauncherView` (the launcher's SwiftUI UI and its own local key monitor), `ResultRow`, `FileActionsView` (file action sheet), `WindowDragHandle`, `FileOps` (trash/show-in-Finder/move/duplicate) |
| `SearchEngine.swift` | The `SearchEngine` singleton: query routing per `SearchMode`, app/file/script/quick-link/emoji/sticker/calculator search, relevance scoring, recency bonus, shell command & script execution |
| `SearchResult.swift` | `SearchResult` model and `ResultType` enum shown in the results list |
| `WindowManager.swift` | `WindowManager` singleton: all window-tiling geometry plus the Accessibility-API plumbing to read/move the frontmost window |
| `Shortcuts.swift` | `KeyBinding`, `ShortcutAction` (every bindable action, its scope/section/display name/default), `ShortcutStore` (persisted bindings + conflict detection), `HotKeyCenter` (Carbon global-hotkey registration) |
| `SettingsView.swift` | The `Settings` scene: one tab per feature area (Shortcuts, Scripts, File Search, Quick Links, Stickers, Clipboard) |
| `RankingStore.swift` | Persists per-item usage counts and turns them into a small relevance boost |
| `QuickLinkStore.swift` | `QuickLink` model + persisted store; `QuickLinkStore.open(_:)` opens a URL or filesystem path |
| `ClipboardPaste.swift` | The paste mechanism: snapshot the pasteboard → set new contents → reactivate the previously-frontmost app → simulate `⌘V` → restore the original pasteboard |
| `StickerStore.swift` | `Sticker` model + persisted store; copies added images/GIFs into Application Support; `NSImage.pngData()` and `NSPasteboard.readEmbeddedImage()` helpers |
| `ClipboardHistoryStore.swift` | Opt-in, in-memory-only clipboard history via pasteboard `changeCount` polling |
| `CalculatorEngine.swift` | Hand-rolled recursive-descent arithmetic parser/evaluator backing the inline calculator |
| `EmojiDatabase.swift` | Hardcoded emoji + keyword list, searched the same way as everything else |

## Singletons vs. `@State`

Nearly every store (`SearchEngine`, `ShortcutStore`, `QuickLinkStore`, `StickerStore`,
`ClipboardHistoryStore`, `RankingStore`, `WindowManager`, `HotKeyCenter`,
`LauncherWindowController`) is a `static let shared` singleton rather than a view-owned
`@StateObject`. This is deliberate: several of these need to be reached from pure-AppKit code
that has no SwiftUI view hierarchy of its own (the status item's right-click menu, the global
hotkey handler in `AppDelegate`), so a singleton is the one shape that's reachable from both
worlds. `ObservableObject` conformance + `@Published` properties still let SwiftUI views
observe them normally via `@ObservedObject`.

## The launcher window

`LauncherWindowController` owns a single `LauncherPanel` (a borderless, non-activating
`NSPanel`) and a single `NSHostingController(rootView: LauncherView())`, both created once and
reused across every show/hide — not recreated per-toggle. Consequences of that:

- `LauncherView.onAppear` only fires once per app launch, not on every reopen. The view
  instead observes `LauncherWindowController.isVisible` and resets itself (`searchText = ""`,
  refocus, re-run an empty search) on every transition to visible.
- `SettingsOpener.openAction` — which lets AppKit-only code trigger SwiftUI's
  `openSettings` environment action — is captured once, in that one `onAppear`. To guarantee
  it's captured before it's ever needed, `AppDelegate.applicationDidFinishLaunching` calls
  `LauncherWindowController.shared.prepareContentOffscreen()`, which briefly orders the panel
  on-screen far off any real display purely to let SwiftUI run `onAppear`, then orders it out
  again — without ever visibly flashing the launcher.
- The panel is deliberately **non-activating**: showing it never steals "frontmost app"
  status from whatever app the user was in. That's what lets emoji/sticker/clipboard-history
  selections paste back into that original app (`ClipboardPaste`), and it's why window-tiling
  hotkeys correctly act on the app that was actually active, not on ReFlow itself.
- It closes automatically when key status moves to a genuinely different app
  (`windowDidResignKey`), but not when it moves to one of ReFlow's own windows (Settings, an
  `NSOpenPanel`, a sheet) — checked via `NSApp.keyWindow == nil`, since that only reports
  windows owned by the current process.
- Its on-screen position is user-draggable and persisted to `UserDefaults`
  (`launcherWindowOrigin_v2`); a guard flag (`isProgrammaticMove`) prevents the controller's
  own programmatic repositioning (initial placement, the offscreen warm-up trick) from being
  mistaken for a real user drag and overwriting that saved position.

## Search & ranking

`SearchEngine.search(query:)` runs on a cancellable `Task` with a 120ms debounce (skipped for
an empty query, so clearing the field shows defaults instantly). A later call always
supersedes an earlier one still in flight; callers that need to act on `results` right after a
keystroke (submitting on Enter, the top-result shortcuts) call
`waitForPendingSearch()` first to avoid racing a stale query.

Within `.launcher` mode, a query is checked against several special forms *before* falling
back to the general app/file/script/quick-link search:

1. Exactly `fs` → switches to File Search mode
2. Exactly `cb` (only if Clipboard History is enabled) → switches to Clipboard History mode
3. Looks like a math expression (`CalculatorEngine.looksLikeExpression`) → replaces the
   result list entirely with the calculator answer
4. Otherwise → apps + scripts + quick links, merged and sorted by relevance

**Relevance** (`SearchEngine.calculateRelevance`) is a simple tiered text match: exact match
(1.0) > prefix match (0.9) > substring match (0.7) > in-order fuzzy match, i.e. every query
character appears somewhere in the target in order (0.5) > no match (0.0). File Search results
additionally get a small recency bonus (up to +0.3, decaying linearly to 0 over a year) so
among similar text matches, a more recently touched file ranks higher — capped low enough that
it only breaks ties, never lets an irrelevant match outrank a genuine one.

**Ranking** (`RankingStore`) then adds a further per-item boost — `min(useCount, 20) * 0.02`,
so up to +0.4 — recorded every time a result with a stable `rankingKey` is executed
(`SearchResult.execute()`). This is small enough to nudge a frequently-used item above a
similarly-relevant one without ever letting usage alone beat genuine text relevance. It's
keyed by a stable identity: an app/file/script path, `"quicklink:<target>"`,
`"emoji:<char>"`, or `"sticker:<uuid>"`. One-off entries (ad-hoc shell commands, mode-switch
results) have no `rankingKey` and are never boosted or persisted. The launcher's context menu
exposes "Reset Ranking" per item, calling `RankingStore.reset(_:)`.

Application listings are cached in memory after the first scan (`loadApps()`/`cachedApps`) —
`/Applications`, `/System/Applications`, `/System/Applications/Utilities`, and
`~/Applications` are walked once, not on every keystroke. Icons are cached similarly
(`iconCache`, `stickerIconCache`).

## Window tiling

`WindowManager` does everything through the Accessibility API (`AXUIElement`), not any
private API:

- **Finding the frontmost window** (`getFrontmostWindow`) tries
  `AXUIElementCreateSystemWide` + `kAXFocusedApplicationAttribute` first (works around a
  real case — seen with Safari — where `NSWorkspace.frontmostApplication` reports an app
  whose `processIdentifier` AX rejects), falls back to `NSWorkspace.frontmostApplication` if
  that fails, then tries `kAXFocusedWindowAttribute` before falling back further to
  `kAXWindowsAttribute` and picking the one flagged `kAXMainAttribute` (some apps'
  full-screen-capable windows answer the first with `kAXErrorInvalidUIElement` regardless).
  ReFlow's own windows are explicitly excluded so a tiling hotkey pressed while Settings is
  focused (e.g. mid-shortcut-recording) can't move Settings itself.
- **Coordinate spaces**: AX frames use top-left origin with Y increasing downward; `NSScreen`
  frames use AppKit's bottom-left-origin, Y-increasing-upward space. `verticallyFlipped(_:)`
  converts between them (the same formula works in both directions) — skipping this
  conversion is what would make "snap to top left" land at the bottom of the screen.
- **Multi-display correctness**: the target screen is resolved from whichever `NSScreen`
  actually contains the window's center (falling back to greatest-overlap, then
  `NSScreen.main`) rather than `NSScreen.main` directly — for a background app like ReFlow,
  `.main` tracks whichever window is key *in this process*, which is usually `nil` and
  silently falls back to the primary display.
- **Debouncing** (`setWindowFrame`, 50ms): rapid-fire hotkey presses coalesce to only the
  most recently requested frame, so cycling quickly through tiling positions doesn't visibly
  bounce the window through intermediate states.
- **App-specific workarounds** applied in `applyWindowFrame`, both matching known fixes from
  other AX-driven tiling tools (Rectangle, Amethyst, Silica/Slate):
  - Temporarily disables an app's `"AXEnhancedUserInterface"` attribute (undocumented but
    public) while writing the frame — Safari and others can have this on, which otherwise
    makes position/size writes report `.success` while silently doing nothing.
  - Writes position before size normally (avoids a visible "jump then resize" double-step
    when growing), but size before position when *shrinking* — except for apps with
    interdependent position/size (currently just Safari, `hasInterdependentPositionAndSize`),
    where position must always be written first or the app silently discards the size it was
    just given.
  - Explicitly checks `AXUIElementIsAttributeSettable` first and skips (with a log line)
    windows that can't be resized via AX at all — e.g. one in native full-screen.

All tiling failures are logged to stderr with the `ReFlow[tiling]:` prefix rather than failing
silently, to make diagnosing a misbehaving target app possible.

## Shortcuts

- `KeyBinding` wraps a key code + modifier flags, masked to just control/option/shift/command
  (`relevantModifierMask`) for both equality and Carbon registration — necessary because a
  binding *recorded* from a real keypress (e.g. an arrow key, which also sets `.numericPad`)
  can carry extra `NSEvent.modifierFlags` bits that a programmatically-built default binding
  never has; comparing raw bits would make two Carbon-identical bindings look different.
- Every `ShortcutAction` has a `scope` — `.global` (works everywhere, registered as a Carbon
  hotkey) or `.launcher` (only handled while the launcher panel has focus, via a local
  `NSEvent` monitor installed in `LauncherView`). Carbon hotkeys are used for global scope
  because they consume the keypress and work from within the sandbox; plain `NSEvent` global
  monitors can only observe, not intercept.
- `ShortcutStore` persists bindings as JSON in `UserDefaults` (`shortcutBindings`), self-heals
  on load: if two actions in the same scope were ever left pointing at the same binding
  (e.g. from an older default scheme), the second one silently falls back to its own current
  default rather than failing to register later. `set(_:for:)` refuses to assign a binding
  that conflicts with another action in the same scope, returning the conflicting action so
  the UI can surface it.
- `HotKeyCenter` re-registers all global hotkeys (`registerAll()`, called on
  `ShortcutStore.onChange`) whenever a binding changes. Settings' shortcut recorder
  temporarily calls `unregisterAll()` while capturing a keypress — otherwise a currently-bound
  combo (the most likely thing someone tries to *change*) would never reach the recorder at
  all, since the Carbon hotkey would intercept it first.

## Pasting into other apps

There's no public API to insert text or an image directly into another app's focused text
field. `ClipboardPaste.paste(afterSettingClipboard:)` uses the same approach as other
emoji-picker replacements (e.g. Rocket):

1. Snapshot the current pasteboard contents (`NSPasteboardItem` doesn't allow holding a live
   reference, so each item's data is copied into a fresh one).
2. Set the new content (emoji, sticker, or a clipboard-history entry).
3. After a short delay, reactivate the app that was frontmost before the launcher opened
   (`LauncherWindowController.appToRestoreFocusTo`) and synthesize `⌘V` via `CGEvent`.
4. After another short delay (to give the target app time to actually read the pasteboard),
   restore the original clipboard contents — so picking an emoji pastes it once and gets out
   of the way, rather than permanently clobbering whatever was actually copied.

`ClipboardHistoryStore.suppressNextChange()` is called around steps 2 and 4 so ReFlow's own
programmatic pasteboard writes never pollute clipboard history with content the user didn't
actually copy themselves.

## Persistence summary

| Store | Backing | Notes |
|---|---|---|
| `ShortcutStore` | `UserDefaults` (JSON) | Self-healing on load; see above |
| `QuickLinkStore` | `UserDefaults` (JSON) | |
| `StickerStore` | `UserDefaults` (JSON metadata) + files in `~/Library/Application Support/ReFlow/Stickers/` | Images are copied in, not referenced by original path, so they survive the source file moving/being deleted |
| `RankingStore` | `UserDefaults` (dictionary) | Keyed by `rankingKey`; capped boost per item |
| `ClipboardHistoryStore` | **In-memory only** | Never persisted; cleared on disable or quit, by design (clipboard contents can include secrets) |
| Launcher window position | `UserDefaults` (`launcherWindowOrigin_v2`) | |
| `SearchEngine.scriptSearchPaths` / `fileSearchPaths` / `limitFileSearchScope` | `UserDefaults`, static properties | Thin typed wrappers so Settings can read/write them without a `SearchEngine` instance |

## Extending ReFlow

- **Add a built-in emoji**: append an `Entry` to `EmojiDatabase.entries`.
- **Add a new `SearchMode`**: extend the `SearchMode` enum (`SearchEngine.swift`), branch on
  it in `search(query:)`, and add a case to `searchBarIconName`/`searchBarPlaceholder` in
  `ContentView.swift`.
- **Add a new bindable action**: add a case to `ShortcutAction`, give it a `scope`,
  `section`, `displayName`, and `defaultBinding`, then handle it in
  `AppDelegate.perform(_:)` (global scope) or `LauncherView.handleLauncherAction(_:)`
  (launcher scope).
- **Add a script language**: add a case to the extension switch in
  `SearchEngine.searchScripts`/`executeScript`, and to `scriptExtensions`.

## Known limitations

- Messages' "Copy" on a photo bubble doesn't reliably produce an image
  `NSPasteboard.readEmbeddedImage()` can extract, even though the same clipboard contents
  paste fine as an image into apps like Notes (`StickerStore.swift`).
- `EmojiDatabase` is a small hardcoded list, not the full Unicode emoji set.
- Window tiling requires Accessibility permission and will no-op (with a logged reason) for
  windows that don't expose settable AX position/size, such as native full-screen windows.
