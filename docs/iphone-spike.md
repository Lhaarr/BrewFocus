# iPhone app and physical test guide

Status: simulator tests and generic arm64 device compilation pass. Physical Screen Time enforcement, Lock Screen authentication, and widget refresh behavior are not yet verified.

## Current iPhone outcome

The standalone iPhone app requests individual Family Controls authorization only after explaining why it is needed. It supports the same fixed coffee contracts as macOS:

| Coffee | Duration | iPhone behavior |
| --- | ---: | --- |
| Latte | 25 min | Timer and put-the-phone-down cue; no apps are shielded |
| Cappuccino | 30 min | One to four selected distracting apps are shielded |
| Americano | 45 min | One to eight selected essential apps stay available |
| Espresso | 30 min | One to four selected essential apps stay available |

Every Screen Time recipe uses Apple’s private activity picker. BrewFocus stores opaque tokens locally and cannot identify the selected applications. Device Activity schedules satisfy Apple’s fifteen-minute minimum and let the monitor extension clear restrictions after the interval.

The same app includes **Morning Quarantine**. It shields all Screen Time-manageable apps for one hour, with zero to four optional exceptions. The user can schedule one fixed daily time or run BrewFocus’s `Start Morning Quarantine` action from a Shortcuts Sleep or Alarm automation.

## Lock Screen coffee

The user can save any valid coffee setup as **Quick Coffee**. `BrewFocusWidgets` then provides:

- an inline Lock Screen widget;
- a circular Lock Screen widget;
- a rectangular Lock Screen widget;
- an iOS 18 Quick Coffee control for the Lock Screen and Control Center.

When idle, the widget shows the saved coffee and starts it through `StartQuickCoffeeIntent`. When a coffee or Morning Quarantine is active, it shows the mode and a system countdown. The widget schedules a timeline transition for the end date, and the app and Device Activity monitor request reloads when shared state changes.

iOS does not allow an arbitrary action to run silently from a truly locked device. BrewFocus requires local-device authentication, so Face ID, Touch ID, or the passcode must succeed before Quick Coffee starts. The intent then runs in the main app process, where the Family Controls entitlement belongs; the widget extension only receives the App Group entitlement.

Add the widget on iPhone:

1. In BrewFocus, configure a coffee and tap `Save as Quick Coffee`.
2. Hold the Lock Screen and choose `Customize`.
3. Choose `Lock Screen`, tap the widget area, and select BrewFocus.
4. Add the inline, circular, or rectangular Coffee Status widget.
5. On iOS 18 or later, the Quick Coffee control can also be added to the bottom Lock Screen controls or Control Center.

## Wake-up automation

BrewFocus cannot read an arbitrary moment when a person physically gets out of bed. Apple’s Sleep `Waking Up` trigger runs when the configured wake-up alarm goes off and requires a sleep schedule in Health. Set it up on the same iPhone:

1. In BrewFocus, allow Screen Time access.
2. Under Morning Quarantine, choose zero to four app exceptions. Zero means maximum app quarantine.
3. Tap `Save for Shortcuts`.
4. Open Shortcuts, then choose `Automation` → `+` → `Sleep` → `Waking Up`.
5. Add BrewFocus’s `Start Morning Quarantine` action.
6. Configure the automation to run automatically without asking.

For an ordinary Clock alarm, use an Alarm trigger instead. Screen Time shields do not silence calls or notification banners. Add Apple’s `Set Focus` action to the same personal automation if the first hour should also use Do Not Disturb. System and emergency functions can remain available.

Personal automations are device-specific. The standalone iPhone app does not depend on proximity to the Mac, iCloud sync, or a backend.

## Targets

```text
BrewFocusiOS
├── authorization and private app picker
├── four-coffee order and active-session UI
├── Quick Coffee editor and deep-link handling
├── recurring Morning Quarantine editor
├── Quick Coffee and Morning Quarantine App Intents
└── local focus notifications

BrewFocusDeviceActivityMonitor
└── reapplies and removes coffee and morning named shields

BrewFocusWidgets
├── three Lock Screen accessory families
└── iOS 18 Quick Coffee control

BrewFocusiOSShared + BrewFocusWidgetShared
└── App Group state, schedules, widget state, and activity names
```

The iPhone app shares only the platform-neutral coffee contract with macOS. It does not share the AppKit restriction engine or macOS session storage.

## Provisioning

Before running on a physical iPhone:

1. Select a development team for `BrewFocusiOS`, `BrewFocusDeviceActivityMonitor`, and `BrewFocusWidgets`.
2. Register `app.brewfocus.ios`, `app.brewfocus.ios.device-activity-monitor`, and `app.brewfocus.ios.widgets`.
3. Enable Family Controls for the app and Device Activity Monitor identifiers. Do not add it to the widget identifier.
4. Register `group.app.brewfocus.shared` and enable it for all three identifiers.
5. Regenerate or refresh the provisioning profiles.
6. Use the `BrewFocusiOS` scheme with the physical iPhone destination.

App Store or TestFlight distribution additionally requires Apple’s Family Controls distribution entitlement for the app and Device Activity Monitor extension.

## Physical test matrix

| Scenario | Expected result | Status |
| --- | --- | --- |
| First launch | No permission appears before the explanatory screen | Pending physical iPhone |
| Allow Screen Time Access | Face ID/system authorization approves the owner’s device | Pending physical iPhone |
| Deny access | App stays on the explanation and offers Settings | Pending physical iPhone |
| Start Latte | Countdown runs for 25 minutes and no app is shielded | Pending physical iPhone |
| Start Cappuccino | Only the selected one to four distractions are shielded | Pending physical iPhone |
| Start Americano | Selected essentials remain available; another app is shielded | Pending physical iPhone |
| Start Espresso | Up to four essentials remain available; another app is shielded | Pending physical iPhone |
| Invalid picker selection | Start and Quick Coffee actions remain disabled with clear guidance | Covered by tests/UI; physical pass pending |
| Save Quick Coffee | Selected recipe remains after relaunch and appears in the widget | Pending physical iPhone |
| Add inline widget | Idle recipe or active mode appears on the Lock Screen | Pending physical iPhone |
| Add circular widget | Cup/start affordance changes to active countdown | Pending physical iPhone |
| Add rectangular widget | Coffee name and countdown fit at default and large text sizes | Pending physical iPhone |
| Start while phone is locked | iOS authenticates, opens BrewFocus, and starts exactly one session | Pending physical iPhone |
| Start with no Quick Coffee | BrewFocus opens and explains that setup is required | Pending physical iPhone |
| iOS 18 Quick Coffee control | Control is addable on Lock Screen and Control Center and starts after authentication | Pending physical iPhone |
| Active widget reaches zero | Widget returns to the idle Quick Coffee state | Pending physical iPhone |
| End coffee early | Shield, notifications, and active widget state clear immediately | Pending physical iPhone |
| Force-quit main app | Shield and widget status remain until the registered interval ends | Pending physical iPhone |
| Relaunch during session | Timer and shield recover from App Group state | Pending physical iPhone |
| Schedule Morning Quarantine | Daily one-hour schedule persists after leaving the app | Pending physical iPhone |
| Morning mode with zero exceptions | Every Screen Time-manageable app is shielded | Pending physical iPhone |
| Morning mode with one to four exceptions | Exceptions remain available; another app is shielded | Pending physical iPhone |
| Morning widget status | Lock Screen shows Morning Quarantine and remaining time | Pending physical iPhone |
| End today’s quarantine | Current shields clear; the next daily interval remains scheduled | Pending physical iPhone |
| Shortcuts manual action | `Start Morning Quarantine` runs for one hour without opening BrewFocus | Pending physical iPhone |
| Sleep → Waking Up automation | Wake-up alarm starts the BrewFocus action automatically | Pending physical iPhone |
| Device restarts during a session | Monitor and widget recover or clear safely at the correct end | Pending physical iPhone |

Stop testing if any shield remains after `End coffee`, `End today’s quarantine`, or relaunching BrewFocus beyond the interval. End active restrictions before removing the development build.

## Documented platform behavior

- Family Controls supports individual authorization on the owner’s device.
- `FamilyActivityPicker` returns privacy-preserving opaque tokens.
- Managed Settings can shield selected applications or all application categories except selected tokens.
- Device Activity invokes interval callbacks only when the device is in use, so end cleanup must be tested after waking and using the phone.
- A Device Activity interval shorter than fifteen minutes is invalid.
- WidgetKit accessory widgets support inline, circular, and rectangular Lock Screen families.
- Interactive widget buttons use App Intents; locked-device actions require authentication before they run.
- WidgetKit controls are available on iOS 18 and later.
- A Shortcuts Sleep `Waking Up` automation fires from the configured wake-up alarm, not physical movement or proximity sensing.

Apple references:

- [Family Controls](https://developer.apple.com/documentation/familycontrols)
- [FamilyActivityPicker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker)
- [Managed Settings shield policies](https://developer.apple.com/documentation/managedsettings/shieldsettings/activitycategorypolicy)
- [DeviceActivityCenter](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter)
- [DeviceActivitySchedule](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule)
- [Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [Accessory rectangular widgets](https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular)
- [Adding interactivity to widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [WidgetKit controls](https://developer.apple.com/documentation/widgetkit/controls-collection)
- [App Intents](https://developer.apple.com/documentation/appintents/app-intents)
- [Event triggers in Shortcuts](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios)
- [Run personal automations automatically](https://support.apple.com/guide/shortcuts/enable-or-disable-a-personal-automation-apd602971e63/ios)
