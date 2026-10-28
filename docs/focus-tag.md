# Focus Tag prototype

Focus Tag restricts **selected iPhone apps** until you use your paired tag to unlock. After the one-time setup, **Start Focus** in BrewFocus works wherever you are, without scanning. The tag also remains an on/off switch: scan while inactive to start, or while active to unlock. Unlike a timed coffee, there is no automatic finish time.

The first enclosure fits a confirmed 20 mm NTAG213 sticker and is intended for the Bambu Lab A1. [Print files and assembly instructions](../hardware/focus-tag/README.md).

## Build and pair

1. Follow [Development signing](development-signing.md) for the iPhone app and extensions.
2. On the `BrewFocusiOS` target, enable **Near Field Communication Tag Reading** as well as Family Controls and the App Group. Regenerate/update provisioning for your team. Only the main app needs NFC; the extensions do not.
3. Build the `BrewFocusiOS` scheme on a physical iPhone with Core NFC support.
4. Grant Screen Time access, then open **Set Up Focus** or the gear button (**Focus Settings**) and tap **Pair a tag**. Hold the top of the phone near just one sticker. Pairing does not start a session.
5. Choose **Apps to block**. Select 1–50 individual apps, not categories or websites. This is a block-list: unselected apps remain available unless another mode restricts them.
6. Tap **Start Focus** on the app's home card or in Focus Settings. No scan is required. Alternatively, use **Scan to focus** in settings with the paired tag. Try opening a selected app to verify Apple's shield.
7. Later, tap **Scan tag to unlock** directly on the home card and scan the paired tag. The scanner in Focus Settings remains available too.

App choices are locked while a tag session is active. **Emergency unlock** asks for confirmation and clears the tag's restrictions without needing the tag. **Forget tag** becomes available after unlocking. Keep BrewFocus accessible when selecting apps.

## Elapsed time on the home screen

The Focus Tag home card shows a count-up timer for the current session. Starting again while already active does not unlock or reset it. The start timestamp is saved, so the elapsed time continues across app backgrounding and relaunches. Time spent with the app closed is included; this measures the duration of blocking, not verified attention or app usage.

The elapsed timer appears inside BrewFocus on the home card, centered under Time in focus. A coffee symbol and selected-app count give the session context. After 24 hours, days (and after seven days, weeks) appear above the remaining hours/minutes/seconds clock. The duration is not capped. An open-ended timeline shows the start time, recent elapsed milestones, and Now; milestones scale from quarter-hours to hours, days and weeks as the session grows. It does not imply a target duration or fill toward a goal. There is no separate Focus Tag Home Screen widget; the existing coffee widgets are unchanged.

## Personal best: longest block

The home screen includes **Longest block**, the longest uninterrupted Focus Tag session on this device. It is not a sum across sessions or a coffee score. A longer active session is shown live as Personal best · still running. The elapsed value is checkpointed when an authorized active session is refreshed and saved on normal tag/Shortcut unlocking or explicit emergency unlock. Reopening the app also reconstructs current elapsed time from the saved start timestamp.

The record is stored as `longestBlockingDuration` in the existing local configuration. Older configurations default to zero without losing pairing, app choices or active start time. Shorter sessions, replacing or forgetting a tag do not erase the personal record. Automatic recovery after lost authorization does not award elapsed time since an unknown revocation moment. Deleting the app removes this local data.

Previously finished tag sessions cannot be backfilled: their durations were not persisted. An existing active session is eligible using its saved start time. This feature stores one personal best, not a full history of tag sessions or proof that attention was maintained for the recorded time.

## Daily navigation and completion

The home screen focuses on the active session, with Cup Shelf and the coffee heatmap visible immediately below the session instead of only behind a navigation link. View all opens the separate shelf page. Without an active session the home screen also offers Start Focus, Timed coffee, Morning Quarantine, and Help. During a tag session, the focus card and direct scanner are prominent; links for starting other modes are hidden. Already active coffee/morning sessions remain accessible under Also running. When only a timed coffee or morning session is active, that session's controls take the main position.

The gear button opens Focus Settings. Tag diagnostics and Shortcuts setup instructions are expandable. Emergency unlock is under Lost your tag? and still asks for confirmation. Help contains day-to-day tag instructions and the coffee-widget guide.

Normal tag unlocking produces a dismissible completion card with the session's elapsed duration. Shortcut completion uses its actual invocation time. The result explains when other coffee/morning restrictions may still apply. This completion feedback is temporary in-app state, not saved history; Cup Shelf is still explicitly labeled as coffee history. Starting a new session clears the feedback. An explicit Scan tag to unlock action is idempotent: if another action has already unlocked, it cannot accidentally restart blocking.

The ordinary in-app control starts only. To keep physical-scan unlocking, leave **Allow Shortcut Control** off and scan inside BrewFocus to stop. With optional Shortcut control enabled, the previously described convenience tradeoff still applies: the action can be run manually without the tag. Emergency unlock is always retained for lost tags.

## Easy tap: Shortcuts NFC automation

After pairing and choosing apps, enable **Allow Shortcut Control** in Focus Tag and accept the explanation. It is off by default, including when upgrading an existing setup.

1. Open Apple's **Shortcuts** app → **Automation** → add an **NFC** trigger.
2. Scan the same physical sticker and give it a name, such as BrewFocus.
3. Choose **Run Immediately** (on older iOS versions, turn off **Ask Before Running**).
4. Add BrewFocus's **Toggle Focus Tag** action. Do not use **Open Focus Tag** for this route.
5. Save exactly one automation for this tag. You can add Shortcuts' vibration action for feedback.
6. With the screen awake, tap the top of the phone to the tag. Verify a selected app is blocked. Move away, wait at least three seconds, and tap again to unlock.

The action requests background execution without opening BrewFocus or asking for a second scan. iOS controls whether and when it runs. Background NFC is not always available: do not promise screen-off operation, operation before first unlock after a restart, or while the camera or Apple Pay is in use. Test on the recipient's actual phone.

**Convenience tradeoff:** Shortcuts identifies the tag for its automation, but does not supply a verified tag identifier to the app. Toggle Focus Tag therefore also works when run manually, via another automation, or another supported Shortcuts entry point. It allows execution while locked. Anyone able to run this action can unlock the tag session. Disable Allow Shortcut Control to restore in-app scan-only control (emergency unlock remains available). Replacing or forgetting a paired tag also disables Shortcut control; delete or update the old NFC automation yourself.

The action reloads saved state before toggling, saves before modifying shields, and ignores repeat calls within three seconds using a persisted timestamp. Both the view and intent use the same main-app manager. The file remains protected until the first device unlock after reboot, then readable to the app while locked. This is not cryptographic proof of tag possession.

**Open Focus Tag** still opens the in-app scanner and requires local authentication. A `brewfocus://focus-tag` URL opens the screen only; it cannot unlock a session. No data needs to be written to the sticker for either route.

## Giving a tag to another iPhone user

The printed tag is not a standalone blocker. Each recipient needs BrewFocus installed, Screen Time permission, their own app selection, a paired tag, and their own NFC automation. Personal automations are device-specific; handing someone your tag or sharing a normal Shortcut does not install this setup for them.

For now, this feature is a development build. A nontechnical installation path needs a TestFlight or App Store release with the required Family Controls distribution approval for the app and monitor extension. No invitation or store link is provided until that distribution is actually available. Do not share development certificates, Apple account credentials, or provisioning profiles with recipients.

For a handover: install an approved release, follow the Easy tap steps together, test one nonessential app in both directions, and show the owner emergency unlock and how to disable the automation. Keep BrewFocus and Shortcuts accessible.

## Behavior, persistence, and limits

- The tag has no executable code or battery. The code runs in BrewFocus.
- Core NFC reads the identifier from a connected MIFARE Ultralight-family tag or a compatible ISO14443-A tag reported with an unspecified (`unknown`) family. An empty identifier is rejected. NTAG213/215/216 are the intended tags; the app does not authenticate the silicon model or a manufacturer signature. The setup screen shows the last detected technology/family without displaying its UID.
- A UID comparison is a focus cue, **not a cryptographic security boundary**. Identifiers can be copied. The owner can also revoke Screen Time access, remove the app, or use emergency unlock.
- The paired UID, private app tokens, and session state are stored locally in the app's Application Support directory as an atomically written property list. Nothing is stored in the repository or uploaded.
- The manager saves the new active state before applying shields. Write failure prevents starting. On restart it reapplies a valid active state; missing/corrupt state clears only the tag's shields.
- Revoked authorization clears the active state on the next app refresh. Emergency unlock clears shields even if storage is failing and reports when it cannot save that change.
- Tag restrictions use their own named Managed Settings store. Coffee and Morning Quarantine use different stores; unlocking any one mode does not clear the others.
- Managed Settings performs shielding, not force-quitting applications. There is no Mac-reader/pairing integration in this prototype.
- The Lock Screen Coffee Status widget and Cup Shelf still describe timed coffees. Indefinite tag sessions appear on the app's home card and the Focus Tag screen; they are not counted as completed cups.

## Verification

Automated tests cover pairing without activation, a matching scan's start/stop transition, rejection of another tag, prohibited setup changes during a session, authorization and selection guards, persistence round-trip, corrupt storage, write failures, and emergency unlock. Explicit unlock is tested against repeated reads and failed persistence, and completion duration uses the actual unlock/Shortcut invocation time. Native component captures check ready/active cards on a narrow iPhone in light/dark mode and active mode at an accessibility text size. Simulator tests and unsigned device compilation cannot establish NFC radio behavior, full VoiceOver operation, or Screen Time entitlement approval.

Physical checks are still **pending**:

| Check | Expected result |
| --- | --- |
| Pair loose 20 mm NTAG213 | Setup saved; no apps blocked |
| Select two individual distractions | Only those apps are selected for blocking |
| Start Focus without bringing the tag | Selected apps blocked; elapsed timer starts |
| Start again while active / relaunch app | Same start time, no unlock or reset |
| BrewFocus home card | Elapsed time continues from the same saved start timestamp |
| Home scan completes after a Shortcut already unlocked | No restart of blocking |
| Tag unlock with an overlapping timed session | Completion reports remaining session restrictions |
| Scan paired tag | Selected apps show shields; other apps remain usable |
| Cancel scan, time out, or present multiple tags | No state change |
| Scan another tag while blocked | Remains blocked; wrong-tag message |
| Repeated reads within one scan sheet | One transition only |
| Scan matching tag to unlock | Tag shields removed |
| Force-quit/relaunch and reboot during a session | Session retained; verify shield persistence and reapplication |
| Revoke Screen Time access | No trapping; inactive state after refresh |
| Emergency unlock | Tag shields removed without NFC |
| Overlap with coffee / Morning Quarantine | Ending either mode leaves the other's restrictions intact |
| Open Focus Tag / custom URL | Opens tag screen; never unlocks by itself |
| Toggle Focus Tag with control disabled | Refuses without changing restrictions |
| NFC automation / manual Toggle Focus Tag | Toggles once without a second scan when control is enabled |
| Two Toggle calls within three seconds / after app relaunch | Second call ignored |
| Locked with screen awake / screen off / after restart | Record actual iOS behavior; no promise of always-on scanning |
| Disable control, replace or forget tag | Old automation can no longer toggle until explicitly re-enabled |
| Ten scans through printed case with phone cover | Consistent reads; no pressure on tag/chip |

Stop testing if an unselected essential app is inaccessible or any unexpected restriction remains. Use emergency unlock and end any separately active coffee or morning session.

## Primary references

- [Apple: NFCTagReaderSession](https://developer.apple.com/documentation/corenfc/nfctagreadersession)
- [Apple: NFC Tag Reading entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats)
- [Apple: shielded applications and the 50-token limit](https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property)
- [Apple: Shortcuts NFC triggers](https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios)
- [Apple: personal automations are device-specific](https://support.apple.com/guide/shortcuts/intro-to-personal-automation-apd690170742/ios)
- [Apple: App Intent authentication policy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)
- [Apple: background tag reading](https://developer.apple.com/documentation/corenfc/adding-support-for-background-tag-reading)
- [NXP: NTAG213/215/216 data sheet](https://www.nxp.com/docs/en/data-sheet/NTAG213_215_216.pdf)
