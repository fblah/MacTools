# MacTools

MacTools is a native macOS menu bar toolbox inspired by the convenience of Parallels Toolbox, built as a lightweight Swift app.

The first included tool is **System Monitor**: a live menu bar strip showing network, CPU, RAM, and SSD availability. Clicking it opens a compact popover under the tray icon with CPU, memory, disk, network, and uptime metrics.

## Goals

- Native macOS menu bar experience
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

The app runs as a menu bar accessory. Click the waveform icon in the macOS menu bar to open the toolbox popover.

## Build

```bash
swift build
```

## Package as a macOS App

```bash
Scripts/package_app.sh
open dist/MacTools.app
```

## Release

MacTools uses Sparkle for app updates and GitHub Releases for distribution.

To publish a release:

```bash
Scripts/bump_version.sh 0.2.0
git add VERSION
git commit -m "Bump version to 0.2.0"
git tag v0.2.0
git push origin main v0.2.0
```

The release workflow builds `MacTools.app`, zips it, signs the update archive for Sparkle, writes `appcast.xml`, and attaches both files to the GitHub release.

The app checks this feed:

```text
https://github.com/havokentity/MacTools/releases/latest/download/appcast.xml
```

## Roadmap

- Add more toolbox apps behind the sidebar
- Add preferences for menu bar display format
- Optional launch-at-login helper

## License

MIT
