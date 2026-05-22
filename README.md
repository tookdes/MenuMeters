# MenuMeters

This is a maintained personal fork of [yujitach/MenuMeters](https://github.com/yujitach/MenuMeters), built as a standalone macOS menu bar app.

The current fork release is `2.1.6.4`. It keeps the original MenuMeters behavior, improves Chinese localization, and adds Apple Silicon GPU/ANE monitoring.

## What's New In 2.1.6.4

- Fixed ANE power reading on M1 by subscribing to PMP energy counters. ANE energy data on M1 lives in the `PMP` group rather than `Energy Model`; the reader now merges `PMP` channels and parses `ANE`/`GPU`/`GPU SRAM` from `PMP` → `Energy Counters`.

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

Download the release zip, unzip it, and run `MenuMeters.app`.

The app is ad-hoc signed for local use. Depending on your Gatekeeper settings, macOS may require you to allow the app manually the first time it is opened.

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
