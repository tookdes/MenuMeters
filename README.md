# MenuMeters

This is a maintained personal fork of [yujitach/MenuMeters](https://github.com/yujitach/MenuMeters), built as a standalone macOS menu bar app.

The current fork release is `2.1.6.8`. It keeps the original MenuMeters behavior, improves Chinese localization, and adds Apple Silicon GPU/ANE monitoring.

## What's New In 2.1.6.8

- Added Top Memory and Top Network process lists in the Memory and Network menus.
- Added a public IOAccelerator GPU fallback so usage and memory still work when IOReport is missing, including Intel/AMD.
- Hardened process sampling: private temp dir, complete UTF-8 line buffering, no leftover `top`/`nettop`, and Memory rows on first open.
- Intel GPU preferences now expose Percentage, Graph, and GPU Memory; Apple Silicon-only meters stay marked as such.

## What's New In 2.1.6.7

- Added GPU memory bandwidth, media engine load, and GPU memory stats, with broader M1–M5 temperature sensor coverage.
- Fixed GPU graph freeze, menubar extra width jitter, and a disappearing network status item.
- Restored disk arrow styles, made the disk picker show the current selection, and color-coded disk read/write throughput.
- Moved the ANE power toggle onto the GPU preferences pane and fixed the memory update-interval display.
- Removed Sparkle from the default `MenuMeters` scheme. Local releases use ad-hoc signing.

## What's New In 2.1.6.6

- Added disk throughput display with per-physical-disk selection.
- Fixed a crash in hidden status item detection.
- Redesigned the disk settings pane to match the network page.

## What's New In 2.1.6.5

- Added CPU power display from IOReport Energy Model, effective on M1/M2 chips. Refactored Apple Silicon power sampling to prefer Energy Model with PMP fallback, fixing zero readings on some chips. Fixed hidden status item detection.

## What's New In 2.1.6.3

- Added a GPU menu meter for Apple Silicon Macs.
- Added GPU usage, GPU frequency, GPU power, and ANE power readings.
- Added a GPU preferences pane with display toggles, graph width, update interval, colors, and menu bar padding.
- Added an ANE power toggle to the CPU preferences pane.
- Added a shared menu bar horizontal padding preference to reduce uneven left/right spacing.
- Improved Chinese Simplified localization across preferences and menu items.
- Added memory text unit handling and related Chinese localization fixes.
- Added standard menu items for opening preferences, launch-at-login, and quitting the app.
- Bumped the app version to `2.1.6.3`.

## Apple Silicon GPU And ANE Notes

The GPU and ANE readings use private Apple system interfaces, mainly `IOReport` channels:

- GPU usage is derived from GPU performance-state residency.
- GPU and ANE power are derived from Energy Model counters.
- ANE usage percentage is not implemented, because there is no stable public counter comparable to the GPU residency data.

This is similar in spirit to tools such as `mactop`, but the code here is implemented directly for MenuMeters rather than embedding that project.

These interfaces are not public API. They may change across macOS releases or Apple Silicon generations. On machines where the relevant `IOReport` channels are unavailable or blocked, the GPU/ANE meter may show unavailable values.

## Installation

Download the release zip from GitHub Releases, unzip it, and run `MenuMeters.app`.

The app is ad-hoc signed for local use and is not distributed through the Mac App Store. Depending on your Gatekeeper settings, macOS may require you to allow the app manually the first time it is opened.

## Building

Open `MenuMeters.xcodeproj` in Xcode and build the `MenuMeters` scheme, or use:

```sh
xcodebuild \
  -project MenuMeters.xcodeproj \
  -scheme MenuMeters \
  -configuration Release \
  -derivedDataPath /tmp/MenuMetersReleaseDerivedDataAdhoc \
  build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=
```

Default local builds use ad-hoc signing (`CODE_SIGN_IDENTITY=-`, empty `DEVELOPMENT_TEAM`).

The local release packaging used for this fork places these generated files in the project root:

- `MenuMeters.app`
- `MenuMeters-Release.zip`

Those files are build artifacts and are intentionally ignored by git.

## Repository Background

MenuMeters was originally developed by Raging Menace:

<http://www.ragingmenace.com/software/menumeters/>

The original Menu Extra model stopped working on El Capitan and later because SystemUIServer no longer loads non-Apple-signed Menu Extras. The yujitach fork converted MenuMeters into a standalone faceless app using `NSStatusItem`. Later versions moved it out of System Preferences into a standalone application because preference panes became increasingly constrained by macOS security changes.

This fork continues from that standalone-app codebase.

## Related Projects

Modern alternatives with broader feature sets include:

- [Stats](https://github.com/exelban/stats)
- [iGlance](https://iglance.github.io)
- [eul](https://github.com/gao-sun/eul)

Related MenuMeters forks:

- [emcrisostomo/MenuMeters](https://github.com/emcrisostomo/MenuMeters)
- [axet/MenuMeters](https://gitlab.com/axet/MenuMeters)

## License

MenuMeters is distributed under the GPL. See [LICENSE](LICENSE).
