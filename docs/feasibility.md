# Application restriction technical feasibility

Status: initial spike, 26 August 2026.

## Product promise

BrewFocus is a **cooperative, reversible focus guard**. Cappuccino hides selected block-listed apps. Americano and Espresso hide regular GUI apps outside their allow-lists. Latte does not restrict apps. BrewFocus never quits or force-terminates another app. A determined user can quit BrewFocus or otherwise bypass it, so the app must not describe this behavior as an unbreakable lock.

## What documented macOS APIs support

- `NSWorkspace.runningApplications` provides the current running apps, and `frontmostApplication` identifies the app receiving key events.
- `NSWorkspace.didActivateApplicationNotification` reports application activation through the workspace notification center.
- `NSRunningApplication.hide()` attempts to hide another app and reports whether it succeeded. Apple explicitly notes that hidden state is race-prone and that an app may unhide itself.
- `NSRunningApplication.activate(options:)` can return the user to a permitted app.

These APIs are enough to test the coffee restriction interactions without Accessibility automation, private APIs, process termination, kernel components, or an external service.

Primary Apple references:

- [NSWorkspace activation notifications](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- [NSWorkspace running applications](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications)
- [NSWorkspace frontmost application](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication)
- [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication)
- [NSRunningApplication.hide()](https://developer.apple.com/documentation/appkit/nsrunningapplication/hide())

## What BrewFocus cannot promise cleanly

### An unbreakable application lock

The AppKit approach is cooperative. Some processes cannot be hidden, activation events can race, and the user remains in control of their Mac. Stronger enforcement would materially change distribution, permissions, safety, and trust.

### Turning Focus or Do Not Disturb on automatically

Apple documents `INFocusStatusCenter` for requesting permission to **read** whether the user can receive notifications. Focus Filters let an app adapt its own behavior when the user changes Focus. Neither API is a public switch for BrewFocus to enable a system Focus or suppress other apps’ notifications.

- [INFocusStatusCenter](https://developer.apple.com/documentation/intents/infocusstatuscenter)
- [Focus filters](https://developer.apple.com/documentation/appintents/focus)

The UI recommends that users configure a macOS Focus themselves instead of pretending BrewFocus controls it.

### Screen Time shields on macOS

Managed Settings can shield apps on supported platforms, but Apple’s current Family Controls configuration documentation lists the capability for iOS and visionOS, not macOS. BrewFocus therefore does not base its macOS promise on Screen Time APIs.

- [Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [Managed Settings](https://developer.apple.com/documentation/managedsettings)

### Website blocking

System-wide network filtering on macOS requires a Network Extension content-filter provider, its entitlement, signing/provisioning, system-extension lifecycle, and explicit user approval. This remains too large and permission-heavy for the current proof.

- [Content filter providers](https://developer.apple.com/documentation/networkextension/content-filter-providers)
- [Network Extension entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)

## Remaining manual proof

The signed, sandboxed application has been built and launched successfully through Xcode on macOS 26.5.2. The menu-bar flow still needs a complete manual pass because current automated tests do not cover `LSUIElement` status-item interaction. Use the [manual restriction matrix](manual-test-matrix.md) to verify multi-Space behavior, full-screen apps, relaunching a blocked app, apps that refuse hiding, pause/abort restoration, and recovery after force-quitting BrewFocus. Those observations should determine whether the app remains sandboxed and whether distribution starts with notarized Developer ID or the Mac App Store.
