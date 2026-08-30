# Roadmap

## v0.1 — Prove Espresso

- [x] Menu-bar shell and Espresso order flow
- [x] Select one to four currently running apps with native icons
- [x] Fixed 30-minute session
- [x] Reversible AppKit soft guard
- [x] Pause, resume, abort, completion, and local recovery
- [x] Minimal Cup Shelf
- [x] Replace the placeholder app icon
- [ ] Complete `manual-test-matrix.md`
- [ ] Add a polished Espresso animation
- [ ] Record the README workflow GIF
- [ ] Accessibility and VoiceOver pass
- [ ] Decide Developer ID versus Mac App Store distribution

## v0.2 — Four coffees, one clear model

- [x] Explain the safe, cooperative guard on first run
- [x] Surface apps that macOS refuses to hide
- [x] Add fixed Latte, Cappuccino, and Americano contracts
- [x] Add reusable no-restriction, block-list, and allow-list policies
- [x] Show the correct coffee and app rule throughout the timer and Cup Shelf
- [x] Preserve Espresso-only version 1 snapshots
- [ ] Complete the manual matrix for all four coffees
- [ ] Add deeper Cup Shelf details
- [ ] Add localization infrastructure
- [ ] Add opt-in launch at login

Defer the remaining v0.2 work until the manual restriction matrix passes.

## v0.3 — Standalone iPhone and Lock Screen

- [x] Add a native iPhone app target and shared coffee contract
- [x] Add just-in-time individual Family Controls authorization
- [x] Use Apple’s private picker for one to four allowed apps
- [x] Add an all-except allow-list shield through Managed Settings
- [x] Add a Device Activity Monitor extension and App Group recovery state
- [x] Add local focus and completion notifications
- [x] Add a fixed daily one-hour Morning Quarantine
- [x] Allow zero to four app exceptions for the strict morning mode
- [x] Expose Morning Quarantine as an App Intent for Shortcuts automation
- [x] Keep overlapping daily and Shortcuts restrictions independent
- [x] Add Latte, Cappuccino, Americano, and production-duration Espresso
- [x] Save one validated recipe as Quick Coffee
- [x] Add inline, circular, and rectangular Lock Screen widgets
- [x] Show active coffee or Morning Quarantine with a system countdown
- [x] Start Quick Coffee after lock-screen authentication
- [x] Add an iOS 18 Quick Coffee Lock Screen and Control Center control
- [x] Pass iOS simulator tests and generic arm64 device compilation
- [ ] Complete the coffee, widget, and Morning Quarantine physical matrix in `iphone-spike.md`
- [ ] Request Family Controls distribution entitlements if the spike passes

## Later

Evaluate website filtering as a separately permissioned subsystem. Add optional Mac pairing only after the standalone iPhone shield lifecycle is proven on physical hardware. Consider Cup Shelf sync, custom recipes, themes, and community extensions only after the fixed product behavior is stable.
