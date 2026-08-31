# Contributing to BrewFocus

Thank you for helping make focus simpler on Apple platforms.

## Before you start

- Use an issue to discuss new behavior or changes to a coffee contract.
- Keep bug fixes and documentation improvements narrowly scoped.
- Read the current milestone in [the roadmap](docs/roadmap.md).
- Follow [Development signing](docs/development-signing.md) for physical iPhone work.

## Development workflow

1. Fork the repository and create a focused branch.
2. Make the smallest change that solves the issue.
3. Regenerate `BrewFocus.xcodeproj` with `xcodegen generate` after editing `project.yml` or changing file layout.
4. Run the relevant automated checks.
5. Complete the applicable manual test matrix for behavior that interacts with other apps, Screen Time, widgets, or device restart.
6. Open a pull request describing the behavior change and verification performed.

## Review and merge

- All changes to `main` go through a pull request.
- The macOS tests, iOS tests, and generic iOS build must pass before merge.
- The maintainer reviews product behavior, safety, privacy, and Apple API usage.
- Contributors should respond to review feedback with focused follow-up commits.
- Only a maintainer merges pull requests. Please do not request direct write access for a contribution.

### Automated checks

```sh
xcodebuild \
  -project BrewFocus.xcodeproj \
  -scheme BrewFocus \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/BrewFocusMacTests \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project BrewFocus.xcodeproj \
  -scheme BrewFocusiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -derivedDataPath /tmp/BrewFocusiOSTests \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project BrewFocus.xcodeproj \
  -scheme BrewFocusiOS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/BrewFocusiOSBuild \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Product and safety principles

- Keep the coffee metaphor functional and restrained.
- Use documented Apple APIs and state platform limits clearly.
- Never terminate another Mac app or risk unsaved work.
- Keep data local unless a reviewed proposal changes that contract.
- Preserve accessibility, light mode, and dark mode.
- Avoid dependencies unless they materially reduce maintained complexity.
- Do not commit signing certificates, provisioning profiles, personal team identifiers, build products, or Xcode user state.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
