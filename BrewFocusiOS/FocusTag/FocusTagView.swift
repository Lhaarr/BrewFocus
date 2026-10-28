import FamilyControls
import SwiftUI

struct FocusTagView: View {
    @ObservedObject var manager: FocusTagManager
    @StateObject private var reader = FocusTagReader()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = FamilyActivitySelection()
    @State private var isPickerPresented = false
    @State private var showEmergencyUnlock = false
    @State private var showForget = false
    @State private var showShortcutConsent = false

    var body: some View {
        List {
            Section {
                Label(manager.configuration.state.isActive ? "Focus is on" : "Your focus setup",
                      systemImage: manager.configuration.state.isActive ? "lock.fill" : "wave.3.right")
                    .font(.headline)
                if let start = manager.configuration.state.startedAt {
                    Text("Blocked since \(start.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                Text("Choose your distractions and register your tag once. Start from the home screen; scan your tag to finish. There is no time limit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !manager.isAuthorized {
                Section {
                    Button("Allow Screen Time Access") {
                        Task {
                            do {
                                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                                refresh()
                            } catch {
                                manager.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }

            Section("Your tag") {
                Button {
                    reader.scan(message: "Hold the top of your iPhone near your Focus Tag.") { identifier in
                        try manager.pair(identifier)
                        return "Focus Tag paired. Choose apps, then start focus in BrewFocus or with your tag."
                    }
                } label: {
                    Label(manager.configuration.state.isPaired ? "Replace paired tag" : "Pair a tag",
                          systemImage: "wave.3.right")
                }
                .disabled(manager.configuration.state.isActive || reader.isScanning || !FocusTagReader.isAvailable)

                if manager.configuration.state.isPaired {
                    Label("Tag registered", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                if let tagType = reader.lastDetectedTagType {
                    DisclosureGroup("Tag details") {
                        Text(tagType).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Apps to put away") {
                Button {
                    selection = manager.configuration.selection
                    isPickerPresented = true
                } label: {
                    HStack {
                        Text("Apps to block")
                        Spacer()
                        Text("\(manager.configuration.selection.applicationTokens.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(manager.configuration.state.isActive || !manager.isAuthorized || reader.isScanning)

                Text(manager.configuration.state.isActive
                     ? "App choices stay fixed during a session. Unlock with your tag before changing them."
                     : "Choose 1–50 individual apps to block. Unselected apps stay available.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                if !manager.configuration.state.isActive {
                    Button {
                        do {
                            try manager.start(isAuthorized: AuthorizationCenter.shared.authorizationStatus == .approved)
                        } catch { manager.errorMessage = error.localizedDescription }
                    } label: {
                        Label("Start Focus", systemImage: "lock.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!manager.isAuthorized || !manager.configuration.state.isPaired
                              || !manager.configuration.isSelectionValid || reader.isScanning)
                    Text("No tag needed to start. Bring your tag to unlock later.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    let isUnlocking = manager.configuration.state.isActive
                    reader.scan(message: isUnlocking
                                ? "Scan your paired tag to unlock your apps."
                                : "Scan your paired tag to block your selected apps.") { identifier in
                        if isUnlocking {
                            try manager.unlock(scannedIdentifier: identifier)
                        } else {
                            try manager.toggle(scannedIdentifier: identifier,
                                               isAuthorized: AuthorizationCenter.shared.authorizationStatus == .approved)
                        }
                        return manager.configuration.state.isActive ? "Selected apps blocked." : "Focus Tag unlocked."
                    }
                } label: {
                    Label(manager.configuration.state.isActive ? "Scan to unlock" : "Scan to focus",
                          systemImage: manager.configuration.state.isActive ? "lock.open" : "lock")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!canScan)
                .accessibilityHint("Opens the NFC scanner. Hold the top of your iPhone close to the paired tag.")

                if !FocusTagReader.isAvailable {
                    Text("NFC scanning requires a supported physical iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Tap without opening BrewFocus") {
                Toggle("Allow Shortcut Control", isOn: Binding(
                    get: { manager.configuration.shortcutControlEnabled },
                    set: { enabled in
                        if enabled { showShortcutConsent = true }
                        else { setShortcutControl(false) }
                    }
                ))
                .disabled(reader.isScanning || (!manager.configuration.shortcutControlEnabled
                    && (!manager.isAuthorized || !manager.configuration.state.isPaired || !manager.configuration.isSelectionValid)))
                Text("Optional. Lets a Shortcuts action turn focus on or off without a second scan. The action can also be run manually without the tag.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Set up NFC tapping") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. In Shortcuts, create an Automation with the NFC trigger and scan your tag.")
                        Text("2. Choose Run Immediately and add BrewFocus’s Toggle Focus Tag action.")
                        Text("3. Save one automation for this tag. Wake your screen, tap to start, wait three seconds, then tap again to test unlocking.")
                        Text("Turning this switch on does not create the automation. NFC may be unavailable while the camera or Apple Pay is in use.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .padding(.vertical, 8)
                }
            }

            Section {
                if manager.configuration.state.isActive || manager.needsUnlockRetry || manager.errorMessage != nil {
                    DisclosureGroup("Lost your tag?") {
                        Button("Emergency unlock", role: .destructive) { showEmergencyUnlock = true }
                    }
                } else if manager.configuration.state.isPaired {
                    Button("Forget tag", role: .destructive) { showForget = true }
                }
            }
        }
        .navigationTitle("Focus Settings")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onChange(of: isPickerPresented) { wasPresented, presented in
            if wasPresented && !presented {
                do { try manager.saveSelection(selection) }
                catch { manager.errorMessage = error.localizedDescription }
            }
        }
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onDisappear { reader.cancel() }
        .confirmationDialog("Allow control without scanning?", isPresented: $showShortcutConsent, titleVisibility: .visible) {
            Button("Allow Shortcut Control") { setShortcutControl(true) }
        } message: {
            Text("Shortcuts can turn blocking on or off without verifying your tag, including while the phone is locked. Anyone able to run this action can unlock Focus Tag. You can turn this off here at any time.")
        }
        .confirmationDialog("Unlock without your tag?", isPresented: $showEmergencyUnlock, titleVisibility: .visible) {
            Button("Unlock selected apps", role: .destructive) { manager.emergencyUnlock() }
        } message: {
            Text("Use this if your tag is lost or NFC is unavailable. Other BrewFocus sessions are not stopped.")
        }
        .confirmationDialog("Forget this tag?", isPresented: $showForget, titleVisibility: .visible) {
            Button("Forget tag", role: .destructive) {
                do { try manager.forget() }
                catch { manager.errorMessage = error.localizedDescription }
            }
        }
        .alert("Focus Tag", isPresented: Binding(
            get: { manager.errorMessage != nil || reader.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil; reader.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { manager.errorMessage = nil; reader.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? reader.errorMessage ?? "")
        }
    }

    private var canScan: Bool {
        FocusTagReader.isAvailable && !reader.isScanning && manager.configuration.state.isPaired
            && (manager.configuration.state.isActive || (manager.isAuthorized && manager.configuration.isSelectionValid))
    }

    private func refresh() {
        manager.refresh(isAuthorized: AuthorizationCenter.shared.authorizationStatus == .approved)
    }

    private func setShortcutControl(_ enabled: Bool) {
        do { try manager.setShortcutControlEnabled(enabled) }
        catch { manager.errorMessage = error.localizedDescription }
    }
}
