# ReFlow

ReFlow is a lightweight macOS menu bar utility that combines a Spotlight/Raycast-style
launcher with Rectangle/Magnet-style window tiling — all driven by fully customizable
global keyboard shortcuts.

Press a hotkey, and a floating search panel appears wherever it was last positioned. From
there you can launch apps, open files, run scripts, do quick math, search emoji and custom
stickers, browse clipboard history, or jump straight to a saved link — all without leaving
the keyboard. Separate hotkeys snap the frontmost window into halves, thirds, corners, or
across displays.

## Features

- **Launcher** — search installed applications, files, folders, shell scripts, and your own
  Quick Links from one search field. Results are ranked by text relevance, recency, and how
  often you actually pick them.
- **Inline calculator** — type a math expression (`12 * (4 + 1)`) and the answer appears as
  the top result; press Enter to copy it.
- **Shell commands** — prefix a query with `>`, `$`, or `!` to run it directly (`-l` login
  shell, so your normal `PATH` applies).
- **File Search mode** — type `fs` (or Enter it as a suggestion) to search a dedicated set of
  folders by name, or paste in a full path to jump straight to it. Shows recently
  added/changed files by default.
- **Emoji & sticker search** — type `:` inline, use the toolbar toggle, or press a dedicated
  hotkey to search built-in emoji alongside your own custom images/GIFs ("stickers").
  Selecting one pastes it into whatever app was frontmost before the launcher opened.
- **Clipboard History** *(opt-in)* — type `cb` to browse and re-paste recent clipboard
  contents. Kept in memory only, never written to disk, and cleared whenever it's turned off
  or ReFlow quits.
- **Window tiling** — snap the active window to halves, corners, thirds, two-thirds, or
  maximize/center it, and move it between displays — all via global hotkeys, no launcher
  needed.
- **Fully customizable shortcuts** — every action has a default binding but can be
  re-recorded in Settings, with conflict detection per scope.
- **Quick Links** — name a URL, file, or folder once in Settings and find it by name from the
  launcher from then on.
- **Usage-based ranking** — items you launch often gradually rank higher than similarly
  matching but rarely-used ones (with a per-item "Reset Ranking" available from the launcher's
  context menu).

## Requirements

- macOS 27 or later
- Accessibility permission (for window tiling — see [Permissions](#permissions))

## Building & Running

Open `ReFlow.xcodeproj` in Xcode and run the `ReFlow` scheme. ReFlow is a menu bar app (no
Dock icon, no regular window) — once launched, look for its icon in the menu bar.

## Permissions

On first launch, ReFlow requests **Accessibility** access (System Settings → Privacy &
Security → Accessibility). This is required for window tiling, which reads and repositions
the frontmost window via the Accessibility API. Without it, the launcher and shortcuts still
work, but window-tiling hotkeys will silently do nothing.

## Using ReFlow

- **Toggle the launcher**: `⌘Space` (default)
- **Open emoji/sticker search directly**: `⌃⌘Space` (default) — also toggles back to the
  launcher if already open
- Click the menu bar icon to toggle the launcher; right-click it for Settings and Quit.
- Inside the launcher:
  - `Esc` — back out of File Search/emoji mode, then close the launcher
  - `⌘,` — open Settings
  - `⌘Delete` / `⌘M` / `⇧⌘R` — Trash / Move to… / Show in Finder, applied to the **top**
    result
  - Right-click any file result for the same actions via a context menu

### Default window-tiling shortcuts

All tiling shortcuts default to Magnet's scheme: `⌃⌥` (Control+Option) plus a key.

| Action | Default |
|---|---|
| Left / Right half | `⌃⌥←` / `⌃⌥→` |
| Top / Bottom half | `⌃⌥↑` / `⌃⌥↓` |
| Maximize | `⌃⌥⏎` |
| Center | `⌃⌥C` |
| Corners (TL/TR/BL/BR) | `⌃⌥U` / `⌃⌥I` / `⌃⌥J` / `⌃⌥K` |
| Left / Center / Right third | `⌃⌥D` / `⌃⌥F` / `⌃⌥G` |
| Left / Right two-thirds | `⌃⌥E` / `⌃⌥T` |
| Previous / Next display | `⌃⌥⌘←` / `⌃⌥⌘→` |

All of the above — plus every launcher shortcut — can be changed in **Settings → Shortcuts**.

## Settings

Open Settings from the menu bar's right-click menu, the launcher's gear icon, or `⌘,`:

- **Shortcuts** — view and re-record every global and launcher-scoped hotkey; reset
  individually or all at once.
- **Scripts** — folders scanned for runnable scripts (`.sh .command .py .rb .js .swift`),
  default `~/Scripts`.
- **File Search** — folders searched by File Search mode, default Downloads/Documents/Desktop;
  optionally cap how many files are scanned per folder for speed on very large folders.
- **Quick Links** — add/remove named shortcuts to a URL, file, or folder.
- **Stickers** — add custom images/GIFs from a file or directly from the clipboard, for use
  alongside emoji.
- **Clipboard** — enable/disable Clipboard History and clear it.

## Privacy

- Clipboard History, when enabled, is kept in memory only — it's never written to disk, and
  is cleared the moment it's turned off or ReFlow quits.
- Nothing ReFlow indexes (apps, files, scripts, clipboard contents) is sent anywhere; all
  search and matching happens entirely on-device.
