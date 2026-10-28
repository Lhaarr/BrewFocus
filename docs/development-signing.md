# Development signing

Unsigned macOS tests and generic iOS compilation do not require an Apple Developer account. Running the Screen Time features on a physical iPhone requires identifiers and capabilities owned by your development team.

## Contributors and forks

The checked-in identifiers describe the upstream BrewFocus app. A contributor cannot register the same identifiers in another Apple Developer team.

Before running a fork on a physical iPhone:

1. Choose a unique reverse-DNS prefix, such as `com.example.brewfocus`.
2. Replace the `app.brewfocus` bundle prefix in `project.yml`.
3. Replace `group.app.brewfocus.shared` in `project.yml` and the iPhone, widget, and Device Activity entitlements.
4. Run `xcodegen generate`.
5. Select your development team for `BrewFocusiOS`, `BrewFocusDeviceActivityMonitor`, and `BrewFocusWidgets`.
6. Enable Family Controls for the app and Device Activity Monitor identifiers.
7. Enable the App Group for all three identifiers.
8. Enable Near Field Communication Tag Reading for the main `BrewFocusiOS` identifier and refresh its provisioning profile. Focus Tag uses `NFCTagReaderSession` (`TAG` format); no NFC capability is needed on the extensions.
9. Build the `BrewFocusiOS` scheme on the physical device.

Do not commit personal team identifiers, provisioning profiles, certificates, or Xcode user data.

## Distribution

TestFlight and App Store distribution require Apple to grant the Family Controls distribution entitlement to both the iPhone app and Device Activity Monitor extension. The widget uses the shared App Group but does not receive Family Controls.
