# Architecture

BrewFocus contains native macOS and iPhone applications. Both are local-first and have no server or third-party runtime dependencies.

## Responsibilities

```text
BrewFocusShared/CoffeeKind
    ├── macOS app
    │   └── SessionManager
    │       ├── JSONSessionStore
    │       ├── NSWorkspace app catalog
    │       └── reversible AppKit restriction monitor
    │
    └── iPhone app
        └── IPhoneFocusManager
            ├── Family Controls authorization and picker
            ├── four coffee-specific Managed Settings stores
            ├── one-shot and repeating Device Activity schedules
            ├── Quick Coffee and Morning App Intents
            └── App Group state shared with monitor and widget extensions
                └── Lock Screen status widget and iOS 18 control
```

### Domain

`CoffeeKind` and the restriction vocabulary live in `BrewFocusShared` and compile into both apps. macOS additionally owns `FocusSession`, `FocusSnapshot`, and `AllowedApplication`. Each coffee owns a fixed duration, selection range, and application restriction mode.

### SessionManager

This is the lifecycle authority. It validates each coffee’s selection invariant, schedules its fixed duration, persists transitions, starts and stops restrictions, and repairs persisted state after relaunch.

The manager persists every app BrewFocus hides. On pause, abort, completion, or expired-session recovery, those apps are unhidden before the session is archived.

### macOS integration

`WorkspaceApplicationCatalog` exposes only currently running regular GUI apps. `WorkspaceRestrictionMonitor` consumes one explicit policy: no restriction, a block-list, or an allow-list. Bundle identifiers keep the policy stable when an app relaunches.

The monitor ignores non-regular/background processes and BrewFocus itself. It only restores apps it successfully hid, avoiding changes to apps the user had already hidden.

### Storage

`JSONSessionStore` writes one versioned snapshot atomically beneath the user Application Support directory. There is no migration framework yet; unsupported future versions fail explicitly instead of silently corrupting history.

### iPhone integration

The iPhone app implements Latte, Cappuccino, Americano, Espresso, and a one-hour Morning Quarantine. `IPhoneFocusManager` requests individual Family Controls authorization and receives opaque application tokens through `FamilyActivityPicker`. Latte applies no shield, Cappuccino shields the selected block-list, and Americano and Espresso shield all application categories except their allow-lists.

The main app, `BrewFocusDeviceActivityMonitor`, and `BrewFocusWidgets` share only opaque selections, recipe names, schedules, and end dates through `group.app.brewfocus.shared`. The main app applies a shield immediately. The monitor extension reapplies it when an interval starts and clears it when the interval ends. Every coffee and each morning source use separate named stores so one interval cannot accidentally clear another.

`BrewFocusWidgets` resolves a minimal state from the App Group: active title, start and end dates, and the saved Quick Coffee name. Its inline, circular, and rectangular accessory families use a system timer so the countdown remains useful without per-second timeline reloads. The provider schedules one transition at the end date, while the main app and monitor also request reloads after state changes.

`StartQuickCoffeeIntent` requires local-device authentication and executes in the main app process. That keeps Family Controls authority out of the widget extension. On a locked device, iOS requires Face ID, Touch ID, or the passcode before the action can run. iOS 18 additionally exposes the same action as a WidgetKit control for the Lock Screen and Control Center.

`StartMorningQuarantineIntent` exposes one background-capable action to Shortcuts. It never requests permission or invents a configuration in the background: authorization and zero-to-four app exceptions must first be saved in the BrewFocus UI. A manual early end suppresses only the current recurring interval; the next daily interval remains scheduled.

## Design constraints

- Keep all Cocoa interaction behind small protocols so lifecycle tests stay deterministic.
- Do not add a database while one small JSON document is sufficient.
- Keep coffee contracts fixed until their manual restriction matrix is validated.
- Never terminate another app.
- Never describe iPhone opaque activity tokens as app-usage data BrewFocus can inspect.
- Keep Shortcuts responsible for system triggers and Focus mode; BrewFocus owns only its Screen Time shields.
- Do not add Mac/iPhone synchronization until each standalone lifecycle is reliable.
