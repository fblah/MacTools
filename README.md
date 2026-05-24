# D'Monte's Toolbox

D'Monte's Toolbox is a native macOS menu bar toolbox inspired by the convenience of Parallels Toolbox, built as a lightweight Swift app.

The first real tool is **System Monitor**. It can be enabled or disabled from the Library, shows live metrics in the menu bar when enabled, and opens into a compact monitor panel with CPU, memory, disk, network, and uptime metrics.

## Goals

- Native macOS menu bar experience
- A toolbox dashboard with enable/disable controls per tool
- Small, fast, and easy to extend
- Clean SwiftUI tool views hosted from AppKit
- Public MIT-licensed repository

## Requirements

- macOS 14 or newer
- Xcode 26 or a recent Swift toolchain

## Run

```bash
swift run MacTools
```

The app runs as a menu bar accessory. Click the switch icon in the macOS menu bar to open D'Monte's Toolbox.

## Build

```bash
swift build
```

## Package as a macOS App

```bash
Scripts/package_app.sh
open "dist/D'Monte's Toolbox.app"
```

## Release

D'Monte's Toolbox uses Sparkle for app updates and GitHub Releases for distribution.

To publish a release:

```bash
Scripts/bump_version.sh 0.2.0
git add VERSION
git commit -m "Bump version to 0.2.0"
git tag v0.2.0
git push origin main v0.2.0
```

The release workflow builds the app, zips it, signs the update archive for Sparkle, writes `appcast.xml`, and attaches both files to the GitHub release.

The app checks this feed:

```text
https://github.com/havokentity/MacTools/releases/latest/download/appcast.xml
```

## Roadmap

- Add more tools behind the Library
- Add preferences for menu bar display format
- Optional launch-at-login helper

## License

MIT
