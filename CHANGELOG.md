# Changelog

All notable changes to D'Monte's Tool Box are documented here. This project
adheres to [Semantic Versioning](https://semver.org) and the
[Keep a Changelog](https://keepachangelog.com) format.

## [0.8.5] — 2026-06-10

### Fixed
- Sparkle update details now mark embedded release notes as Markdown so headings
  and lists render as rich text instead of showing raw Markdown syntax.

## [0.8.4] — 2026-06-10

### Changed
- Sparkle update details now use embedded release notes only, so the update
  pane shows the release's notes instead of the full GitHub release page.

## [0.8.3] — 2026-06-10

### Changed
- System Monitor and Grab Text use a higher-contrast green treatment in the
  Tool Box grid.
- System Monitor's menu bar ECG glyph now uses the same stronger green.

### Fixed
- Sparkle update-check dialogs are forced in front of the Tool Box panel so the
  "you're up to date" window remains clickable.

## [0.8.2] — 2026-06-10

### Added
- Right-click context menus on the Tool Box and menu bar tool icons now include
  a Quit action.

### Changed
- Sparkle automatic update checks are enabled by default and run daily.
- Release appcasts now embed release notes from the GitHub release body, with a
  changelog fallback.

### Fixed
- Sparkle's "you're up to date" dialog no longer gets trapped behind the Tool
  Box settings panel.

## [0.8.1] — 2026-06-09

### Added
- Disk Usage Analyzer now includes a side tree for navigating scanned folders.
- Volume Mixer now exposes master output volume and mute controls above the app list.
- Recently used toolbox items can be removed with a hover `x`.

### Changed
- Disk Usage Analyzer uses cached tree paths and treemap layouts for smoother navigation.
- Video Downloader reveals the completed output file when yt-dlp reports one, falling back to the save folder.

## [0.8.0] — 2026-06-09

### Added
- **Volume Mixer** — a new separate menu bar tool for per-app volume control
  using CoreAudio process taps. It lists active and inactive apps, groups helper
  processes under their parent app, supports mute, pinning, smart pinning,
  search, ignored-app management, and per-app output routing.

### Changed
- Volume Mixer restores saved app volume and routing state as soon as its tray
  helper starts, without needing to open the popover first.
- Volume Mixer is 200px taller, giving the app and ignored lists more room.
- Volume Mixer refresh work now runs off the main thread, slider persistence is
  debounced, and the real-time render path uses Accelerate for lower overhead.

## [0.7.1] — 2026-06-01

### Fixed
- **Menu bar icons no longer disappear.** Each tool's icon was hosted as a custom
  subview on the status button, leaving the button itself empty — so when the
  menu bar got crowded macOS culled the "empty" items. All icons now use the
  status item's native button, which AppKit keeps put.
- **Toolbox icon styling.** The hand‑drawn toolbox glyph rendered solid black;
  it's now an adaptive template (semi‑transparent white on dark menu bars) that
  highlights on hover, consistent with every other tool.
- **Launching the Tool Box no longer reopens previously‑open tools.** The
  session‑restore behaviour misfired because a menu‑bar app rarely gets a clean
  termination, so the saved set persisted and tools reopened on nearly every
  launch. Removed entirely — tools open only when you click them.

### Changed
- **Video Downloader**: clicking a completed download now reveals its folder in
  Finder (failed → retry, complete → reveal, otherwise → copy).
- **Clean Drive**: the progress bar's drain is rate‑limited so a fast/instant
  clean still shows a fluid sweep instead of snapping to empty.

## [0.7.0] — 2026-06-01

First public release. 🎉

### Added
- **Public distribution**: releases are now signed with Developer ID under the
  Hardened Runtime and **notarized + stapled by Apple** in CI, so downloads open
  without Gatekeeper warnings.
- A version label in the Tool Box settings sheet (sourced from the bundle).

The suite now ships **18 tools**: System Monitor, Clipboard History, Clean Drive,
Disk Usage Analyzer, Duplicate Finder, Uninstall Apps, Download Video, Image
Converter, Grab Text (OCR), QR Studio, Color Picker, Window Manager, Audio
Switcher, Focus Timer, Calendar, Keep Awake, Maintenance, and Dev Tools.

### Changed
- Notarization pipeline: inside‑out signing of every nested helper, the Sparkle
  framework's XPC services / updater, and the bundled yt‑dlp, each with the
  correct entitlements. `-rc` tags publish as prereleases that bypass the
  auto‑update feed.

## [0.6.1] — 2026-05-30

### Fixed
- **Third‑party review follow‑ups.** Audio Switcher and Maintenance now respect
  the display/menu‑bar scale and no longer cast a square shadow halo; Duplicate
  Finder's result rows scale with the window.
- **Security hardening.** Clipboard history is stored with owner‑only
  permissions (`0700`/`0600`); the bundled yt‑dlp download is verified against
  its official SHA‑256 checksum.

## [0.6.0] — 2026-05-30

### Added
- **Window Manager** — snap the focused window to halves, thirds, two‑thirds,
  corners, maximize, and center, with global ⌃⌥ shortcuts via the Accessibility
  API and multi‑display awareness.

### Changed
- Toolbox wiring is now driven by a single data‑driven `ToolboxCatalog`
  (dashboard, launcher, and packaging in lockstep); `package_app.sh` became
  table‑driven.
- Replaced the deprecated `NSStatusItem.view` with a shared status‑bar helper,
  clearing the macOS 10.14 deprecation warnings.

### Fixed
- Code‑review fixes: a Maintenance shell‑pipe deadlock, a Duplicate Finder scan
  race, Clipboard HTML‑only hashing and file‑paste self‑capture, and a release
  build data race.

## [0.5.0] — 2026-05-29

### Added
- **Eleven new tools**: Dev Tools, QR Studio, Keep Awake, Image Converter,
  Maintenance, Color Picker, Grab Text (OCR), Focus Timer, Duplicate Finder,
  Audio Switcher, and Calendar — each with a tested, pure‑logic core.

## [0.4.0] — 2026-05-29

### Added
- **Clipboard History** — searchable clipboard with text/rich‑text/link/image/
  file capture, pinning, quick‑paste (⌘1–9), paste‑as‑plain, and a ⇧⌘V global
  hotkey. Honors password‑manager/transient markers.

### Fixed
- The Tool Box search field is now focusable and clickable.

## [0.3.0] — 2026-05-29

### Changed
- **Clean Drive** now permanently frees space (instead of moving to Trash),
  runs asynchronously with a draining progress gauge, reports why anything was
  skipped, and tracks the macOS display scale.

## [0.2.0] — earlier

### Added
- Disk Usage Analyzer, Uninstall Apps, and Download Video tools; the tool box
  dashboard and Sparkle‑based auto‑updates.

## [0.1.x] — initial

### Added
- The menu bar tool box shell and the first tool, System Monitor (live CPU,
  memory, disk, network, and temperature metrics).

[0.8.5]: https://github.com/havokentity/MacTools/releases/tag/v0.8.5
[0.8.4]: https://github.com/havokentity/MacTools/releases/tag/v0.8.4
[0.8.3]: https://github.com/havokentity/MacTools/releases/tag/v0.8.3
[0.8.2]: https://github.com/havokentity/MacTools/releases/tag/v0.8.2
[0.8.1]: https://github.com/havokentity/MacTools/releases/tag/v0.8.1
[0.8.0]: https://github.com/havokentity/MacTools/releases/tag/v0.8.0
[0.7.1]: https://github.com/havokentity/MacTools/releases/tag/v0.7.1
[0.7.0]: https://github.com/havokentity/MacTools/releases/tag/v0.7.0
[0.6.1]: https://github.com/havokentity/MacTools/releases/tag/v0.6.1
[0.6.0]: https://github.com/havokentity/MacTools/releases/tag/v0.6.0
[0.5.0]: https://github.com/havokentity/MacTools/releases/tag/v0.5.0
[0.4.0]: https://github.com/havokentity/MacTools/releases/tag/v0.4.0
[0.3.0]: https://github.com/havokentity/MacTools/releases/tag/v0.3.0
[0.2.0]: https://github.com/havokentity/MacTools/releases/tag/v0.2.0
