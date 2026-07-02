# Repository Hygiene

Small checklist for this personal fork.

## Before committing

```sh
git status --short
xcodebuild -project MenuMeters.xcodeproj -scheme MenuMeters -configuration Debug -derivedDataPath /tmp/MenuMetersDerivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

## Before releasing

1. Update `MM_VERSION` in `InfoPlistPreprocessor.h`.
2. Update the current release version/changelog in `README.md`.
3. Build Release with ad-hoc signing.
4. Zip `MenuMeters.app` for GitHub Releases.
5. Note that the app is not notarized unless a release explicitly says so.

## Things intentionally not added

- Mac App Store support
- App Sandbox
- Analytics
- SwiftLint
- XcodeGen
- Full CI/notarization pipeline
