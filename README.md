# D'Monte's Toolbox

A native macOS menu bar toolbox — 18 fast, focused utilities in one lightweight Swift app, inspired by the convenience of Parallels Toolbox.

Open the toolbox from the menu bar, search for what you need, and launch it. Each tool is a self-contained helper with its own polished SwiftUI interface; tools that run continuously (like System Monitor and Clipboard History) add their own menu bar item.

> **macOS 14+** · Universal · Signed with Developer ID and **notarized by Apple** — downloads open without Gatekeeper warnings.

## Download

Grab the latest signed, notarized build from the [**Releases**](https://github.com/havokentity/MacTools/releases/latest) page:

1. Download `DMonte-Toolbox-<version>.zip`
2. Unzip and drag **DMonte Toolbox.app** to `/Applications`
3. Launch it — the toolbox icon appears in your menu bar

The app updates itself automatically via [Sparkle](https://sparkle-project.org); new releases are delivered in the background.

## The tools

| Tool | What it does |
| --- | --- |
| **System Monitor** | Live menu bar CPU, memory, disk, network, and temperature metrics |
| **Clipboard History** | Searchable clipboard with text/image/file capture, pinning, and quick‑paste (⇧⌘V) |
| **Clean Drive** | Reclaim space by clearing caches, logs, and temp files — async, with a live freeing‑up gauge |
| **Disk Usage Analyzer** | Interactive treemap of what's eating your disk |
| **Duplicate Finder** | Find and trash byte‑identical duplicate files |
| **Uninstall Apps** | Remove apps and their leftover support files |
| **Download Video** | Save videos from the web (bundled, checksum‑verified yt‑dlp) |
| **Image Converter** | Batch convert / resize / compress images (HEIC, JPEG, PNG, …) |
| **Grab Text** | OCR any region of the screen straight to your clipboard |
| **QR Studio** | Generate QR codes and scan them from the screen |
| **Color Picker** | System eyedropper with hex / RGB / HSL and a recent‑colors palette |
| **Window Manager** | Snap windows to halves, thirds, and corners with global shortcuts (⌃⌥ + arrows) |
| **Audio Switcher** | One‑click switching of the default input/output device |
| **Focus Timer** | Pomodoro timer with a live menu bar countdown |
| **Calendar** | Menu bar month view with your upcoming events |
| **Keep Awake** | Prevent sleep, optionally for a set duration |
| **Maintenance** | Handy Finder/system toggles and cache/index refreshes |
| **Dev Tools** | JSON, Base64, URL, hashing, UUID, timestamp, and case utilities |

### Permissions

A few tools ask macOS for access the first time you use them, and degrade gracefully if you decline:

- **Window Manager** — Accessibility (to move other apps' windows)
- **Clipboard History** — Accessibility (to paste into the active app)
- **Grab Text** / **QR Studio** (screen scan) — Screen Recording
- **Calendar** — Calendar access

Clipboard history is stored locally with owner‑only permissions and never records password‑manager or transient copies.

## Building from source

Requires macOS 14+ and a recent Swift toolchain (Xcode 26 / Swift 6.1).

```bash
swift build          # debug build
swift test           # run the test suite
swift run DMonte     # run the toolbox from the menu bar
```

### Package a distributable app

```bash
Scripts/package_app.sh
open "dist/DMonte Toolbox.app"
```

`package_app.sh` builds in release mode, assembles the bundle with all helpers, and code‑signs it. With a Developer ID identity present it signs with the Hardened Runtime (notarization‑ready); otherwise it falls back to an ad‑hoc signature for local testing.

## Releasing

Releases are fully automated. Tagging `vX.Y.Z` triggers CI to build, hardened‑sign, **notarize and staple** with Apple, publish a GitHub Release, and update the Sparkle appcast.

```bash
Scripts/bump_version.sh 0.7.2
git commit -am "Release 0.7.2"
git tag v0.7.2
git push origin main v0.7.2
```

A `-rc` suffix (e.g. `v0.7.2-rc1`) publishes as a prerelease, so it's testable without reaching the auto‑update feed. See [`CHANGELOG.md`](CHANGELOG.md) for release history.

The auto‑update feed:

```text
https://github.com/havokentity/MacTools/releases/latest/download/appcast.xml
```

## Architecture

A single `DMonteCore` library holds each tool's pure, testable logic plus its SwiftUI views; the toolbox and every tool are separate executables that share it. A data‑driven `ToolboxCatalog` is the single source of truth for the dashboard, the launcher, and packaging — adding a tool is one catalog entry plus its helper target.

## License

GPL-3.0-only
