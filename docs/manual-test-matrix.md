# Manual coffee restriction matrix

Run this matrix on a physical Mac from a normally signed Debug or Release build. Use apps with saved documents first; repeat with unsaved work only after the safe-hide behavior is established.

Status as of 27 August 2026:

| Scenario | Expected result | Status |
| --- | --- | --- |
| Build and launch sandboxed app | Cup process remains running without a Dock icon | Passed on macOS 26.5.2 |
| Open menu-bar popover | “What can I get you?” appears | Pending manual click |
| Complete onboarding | Product promise is clear and onboarding stays dismissed | Pending manual click |
| Start Latte | 25-minute timer starts and no app is hidden | Lifecycle covered by automated test; UI pending |
| Pause/abort Latte | Timer pauses or ends without restriction restore attempts | Lifecycle covered by automated test; UI pending |
| Configure Cappuccino | Counter allows 1–4 selected distractions | Selection covered by automated test; UI pending |
| Activate a Cappuccino-blocked app | Selected app hides; an unselected app remains available | Policy covered by automated test; UI pending |
| Configure Americano | Counter allows 1–8 essential apps | Selection covered by automated test; UI pending |
| Start Americano | Non-selected regular apps hide for a 45-minute session | Policy covered by automated test; UI pending |
| Configure Espresso | Real app icons appear and counter allows 1–4 selections | Pending manual click |
| Start Espresso | Other visible regular apps hide; selected app activates | Pending manual click |
| Activate an app outside the Espresso allow-list | App hides, selected app returns, notice appears | Pending manual click |
| App refuses `hide()` | Warning says BrewFocus could not hide the app | Pending suitable app |
| Pause | Hidden apps restore and timer freezes | Pending manual click |
| Resume | Restrictions return and timer continues | Pending manual click |
| Abort | All apps hidden by BrewFocus restore; no completed cup appears | Pending manual click |
| Natural completion | Apps restore and one completed cup appears | Lifecycle covered by automated test; UI pending |
| Force-quit and relaunch mid-session | Active session and restrictions recover | Persistence covered by automated test; UI pending |
| Relaunch selected app | Bundle identifier remains allowed | Pending manual click |
| Separate Space | Blocked app is redirected without trapping the user | Pending |
| Full-screen app | Notice and return behavior remain usable | Pending |

## Procedure

1. Run BrewFocus from Xcode with the `BrewFocus` scheme and “My Mac” destination.
2. Save work in all open apps.
3. Open the cup in the menu bar and complete onboarding.
4. Start with Latte and confirm no apps hide.
5. Select one low-risk distraction for Cappuccino and confirm only that app hides.
6. Select one permitted app, such as Finder or TextEdit, and test Americano and Espresso.
7. Work down the table, recording the macOS version and any app-specific behavior.
8. Abort each restrictive session and confirm every app hidden by BrewFocus is visible again.

Stop immediately if an app is terminated, unsaved work is affected, the user cannot return to an allowed app, or apps remain hidden after abort. Those are release blockers.
