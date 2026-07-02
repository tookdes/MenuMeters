# AGENTS.md

MenuMeters is a legacy Objective-C/AppKit menu bar utility. Keep changes small.

## Build

```sh
xcodebuild \
  -project MenuMeters.xcodeproj \
  -scheme MenuMeters \
  -configuration Release \
  -derivedDataPath /tmp/MenuMetersDerivedData \
  build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=
```

The `MenuMeters` scheme intentionally points at the no-Sparkle target.

## Project rules

- Do not migrate to Swift, SwiftUI, XcodeGen, or sandboxing unless explicitly asked.
- Do not add analytics.
- This fork is not targeting the Mac App Store.
- Default signing is ad-hoc (`CODE_SIGN_IDENTITY=-`, empty `DEVELOPMENT_TEAM`).
- Keep deployment-target changes deliberate; this project still carries old macOS compatibility code.
- GPU/ANE readings use private Apple interfaces (`IOReport`, SMC/libSMC). Expect OS/hardware drift.
- Prefer fixing one shared Objective-C path over adding per-call-site guards.

## Release hygiene

Before a release:

```sh
git status --short
xcodebuild -list -project MenuMeters.xcodeproj
xcodebuild -project MenuMeters.xcodeproj -scheme MenuMeters -configuration Release -derivedDataPath /tmp/MenuMetersDerivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

Version source is `InfoPlistPreprocessor.h`; keep README release text in sync.
