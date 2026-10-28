import FamilyControls
import SwiftUI
import UIKit

struct IPhoneRootView: View {
    @ObservedObject var manager: IPhoneFocusManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var isActivityPickerPresented = false
    @State private var isMorningPickerPresented = false
    @StateObject private var focusTag = FocusTagManager.shared
    @State private var isFocusTagPresented = false
    @StateObject private var tagReader = FocusTagReader()

    private enum Destination: Hashable { case coffee, shelf, morning, help }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let completionMessage = manager.completionMessage {
                        completionBanner(completionMessage)
                    }

                    if manager.isAuthorized || focusTag.configuration.state.isActive {
                        if let duration = focusTag.lastCompletedDuration {
                            tagCompletion(duration)
                        }
                        if focusTag.configuration.state.isActive {
                            focusTagCard
                            if manager.session != nil || manager.isMorningQuarantineActive { otherSessions }
                        } else if manager.session != nil || manager.isMorningQuarantineActive {
                            if manager.session != nil { activeSession }
                            if manager.isMorningQuarantineActive { morningQuarantineActive }
                        } else {
                            focusTagCard
                        }
                        FocusLongestBlockCard(startedAt: focusTag.configuration.state.startedAt,
                                              savedRecord: focusTag.configuration.longestBlockingDuration)
                        homeCupShelf
                        homeDestinations
                    } else {
                        authorizationIntroduction
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("BrewFocus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isFocusTagPresented = true } label: {
                        Image(systemName: "gearshape")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Focus settings")
                    .disabled(tagReader.isScanning)
                }
            }
            .navigationDestination(isPresented: $isFocusTagPresented) {
                FocusTagView(manager: focusTag)
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .coffee:
                    destinationPage("Coffee Menu") {
                        if focusTag.configuration.state.isActive { overlappingSessionNotice }
                        if manager.session != nil { activeSession }
                        else { coffeeOrder }
                    }
                case .shelf:
                    destinationPage("Cup Shelf") {
                        coffeeRhythm
                        Text("Your completed coffees. Tag sessions are shown live on the focus screen and are not included here yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                case .morning:
                    destinationPage("Morning Quarantine") {
                        if focusTag.configuration.state.isActive { overlappingSessionNotice }
                        if manager.isMorningQuarantineActive { morningQuarantineActive }
                        morningQuarantineOrder
                    }
                case .help:
                    destinationPage("Help") {
                        tagHelp
                        lockScreenWidgetGuide
                    }
                }
            }
        }
        .tint(.primary)
        .familyActivityPicker(
            isPresented: $isActivityPickerPresented,
            selection: $manager.selection
        )
        .familyActivityPicker(
            isPresented: $isMorningPickerPresented,
            selection: $manager.morningSelection
        )
        .onOpenURL { url in
            if url.scheme == "brewfocus", url.host == "focus-tag" {
                isFocusTagPresented = true
            } else {
                manager.handle(url)
            }
        }
        .onChange(of: isMorningPickerPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                manager.prepareMorningQuarantine()
            }
        }
        .task {
            manager.bootstrap()
            focusTag.refresh(isAuthorized: manager.isAuthorized)
        }
        .onChange(of: focusTag.isAuthorized) { _, _ in manager.refreshAfterBecomingActive() }
        .onChange(of: manager.isAuthorized) { _, authorized in focusTag.refresh(isAuthorized: authorized) }
        .onChange(of: isFocusTagPresented) { _, presented in if presented { tagReader.cancel() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                manager.refreshAfterBecomingActive()
                focusTag.refresh(isAuthorized: manager.isAuthorized)
            }
        }
        .alert(
            "BrewFocus couldn’t continue",
            isPresented: Binding(
                get: { manager.lastError != nil || tagReader.errorMessage != nil
                    || (!isFocusTagPresented && focusTag.errorMessage != nil) },
                set: { isPresented in
                    if !isPresented {
                        manager.clearError()
                        focusTag.errorMessage = nil
                        tagReader.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                manager.clearError()
                focusTag.errorMessage = nil
                tagReader.errorMessage = nil
            }
        } message: {
            Text(manager.lastError ?? tagReader.errorMessage ?? focusTag.errorMessage ?? "Unknown error")
        }
    }

    private var focusTagCard: some View {
        FocusTagHomeCard(
            startedAt: focusTag.configuration.state.startedAt,
            applicationCount: focusTag.configuration.selection.applicationTokens.count,
            isReady: focusTag.isAuthorized && focusTag.configuration.state.isPaired && focusTag.configuration.isSelectionValid,
            isScanning: tagReader.isScanning,
            shortcutControlEnabled: focusTag.configuration.shortcutControlEnabled,
            onStart: {
                do {
                    try focusTag.start(isAuthorized: AuthorizationCenter.shared.authorizationStatus == .approved)
                } catch { focusTag.errorMessage = error.localizedDescription }
            },
            onScan: {
                tagReader.scan(message: "Scan your paired tag to unlock your apps.") { identifier in
                    try focusTag.unlock(scannedIdentifier: identifier)
                    return "Tag session ended. Other active sessions may still block apps."
                }
            },
            onSetup: { isFocusTagPresented = true }
        )
    }

    private var homeDestinations: some View {
        VStack(spacing: 0) {
            if !focusTag.configuration.state.isActive {
                NavigationLink(value: Destination.coffee) {
                    homeRow("Timed coffee", subtitle: "Choose a coffee and a finish time", symbol: "cup.and.saucer")
                }
                Divider()
            }
            if !focusTag.configuration.state.isActive {
                NavigationLink(value: Destination.morning) {
                    homeRow("Morning Quarantine", subtitle: "One protected hour, every day", symbol: "sunrise")
                }
            }
            Divider()
            NavigationLink(value: Destination.help) {
                homeRow("Help", subtitle: "Using your tag and Shortcuts", symbol: "questionmark.circle")
            }
        }
        .buttonStyle(.plain)
        .disabled(tagReader.isScanning)
    }

    private var homeCupShelf: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Cup Shelf", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
                NavigationLink("View all", value: Destination.shelf)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .disabled(tagReader.isScanning)
            }
            CoffeeHeatmapView(records: manager.coffeeHistory, referenceDate: manager.currentDate)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func homeRow(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func destinationPage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var otherSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALSO RUNNING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let session = manager.session {
                NavigationLink(value: Destination.coffee) {
                    homeRow(session.coffee.name, subtitle: "\(manager.remainingText) remaining", symbol: "cup.and.saucer.fill")
                }
            }
            if manager.isMorningQuarantineActive {
                NavigationLink(value: Destination.morning) {
                    homeRow("Morning Quarantine", subtitle: "\(manager.morningRemainingText) remaining", symbol: "sunrise.fill")
                }
            }
            Text("Each session has its own restrictions. Unlocking your tag does not end these sessions.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var overlappingSessionNotice: some View {
        Label("Focus Tag is also active. Ending this session will not unlock your tag's restrictions.", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func tagCompletion(_ duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Focus session ended").font(.headline)
                Spacer()
                Button { focusTag.clearCompletion() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Dismiss completed session")
            }
            Text(FocusTagDuration.compact(duration))
                .font(.title2.monospacedDigit())
            Text(manager.session != nil || manager.isMorningQuarantineActive
                 ? "Your other sessions are still running. Their restrictions may still apply."
                 : "Your tag's restrictions have been removed.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var tagHelp: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Using your tag").font(.title2.weight(.semibold))
            Text("Start Focus in BrewFocus from anywhere. To finish, choose Scan tag to unlock and hold the top of your iPhone near your paired tag.")
            Text("To tap without opening the app, allow Shortcut Control in Focus settings and create an NFC automation using Toggle Focus Tag. The Shortcuts action can also be run manually without a tag.")
            Text("Giving someone a tag? They need BrewFocus, Screen Time permission, their own app choices and their own NFC automation.")
            Text("Lost your tag? Open Focus settings for Emergency unlock. Other coffee and morning sessions have separate controls.")
            Button("Open Focus Settings") { isFocusTagPresented = true }
                .frame(minHeight: 44)
        }
    }

    private var coffeeRhythm: some View {
        CoffeeHeatmapView(
            records: manager.coffeeHistory,
            referenceDate: manager.currentDate
        )
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var authorizationIntroduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero(
                symbol: "lock.shield.fill",
                title: "Protect your attention",
                subtitle: "BrewFocus needs Screen Time access only when you choose to restrict apps."
            )

            VStack(alignment: .leading, spacing: 16) {
                permissionPoint(
                    symbol: "hand.tap.fill",
                    title: "You choose",
                    detail: "Apple’s private picker lets you select apps without exposing their identities to BrewFocus."
                )
                permissionPoint(
                    symbol: "iphone.gen3",
                    title: "This iPhone only",
                    detail: "Everything runs locally and does not require the Mac app, an account, or a server."
                )
                permissionPoint(
                    symbol: "arrow.uturn.backward.circle.fill",
                    title: "Always reversible",
                    detail: "End each session to remove its restrictions. Focus Tag also has an emergency unlock."
                )
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))

            Button {
                Task {
                    await manager.requestAuthorization()
                }
            } label: {
                if manager.isRequestingAuthorization {
                    ProgressView()
                        .tint(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Allow Screen Time Access", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(manager.isRequestingAuthorization)
            .accessibilityHint("Opens Apple’s authorization sheet")

            if manager.authorizationStatus == .denied {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Screen Time access is currently denied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        openURL(settingsURL)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private var morningQuarantineOrder: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero(
                symbol: "sunrise.fill",
                title: "Morning Quarantine",
                subtitle: "Start the day with one protected hour before distractions get a vote."
            )

            VStack(alignment: .leading, spacing: 14) {
                Text("ONE HOUR · EVERY DAY")
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                Button {
                    isMorningPickerPresented = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "apps.iphone")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Choose app exceptions")
                                .font(.headline)
                            Text(morningSelectionSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Apple’s private app picker")

                Divider()

                DatePicker(
                    "Start every day",
                    selection: $manager.morningStartTime,
                    displayedComponents: .hourAndMinute
                )
                .font(.headline)

                Label("Ends automatically after 1 hour", systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))

            morningValidationMessage

            if manager.isMorningScheduled, let schedule = manager.morningSchedule {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(
                        "Scheduled daily at \(scheduleTime(schedule))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.green)
                    Spacer()
                    Button("Remove") {
                        manager.removeMorningSchedule()
                    }
                    .frame(minHeight: 44)
                    .accessibilityHint("Turns off the recurring schedule")
                }
            }

            Button {
                manager.scheduleMorningQuarantine()
            } label: {
                Label(
                    manager.isMorningScheduled ? "Update daily schedule" : "Schedule Morning Quarantine",
                    systemImage: "calendar.badge.clock"
                )
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!manager.canPrepareMorningQuarantine)
            .accessibilityHint("Schedules a one-hour quarantine at this time every day")

            VStack(alignment: .leading, spacing: 14) {
                Label("Wake up at different times?", systemImage: "alarm.waves.left.and.right")
                    .font(.headline)
                Text("Save the exceptions here, then use BrewFocus’s Start Morning Quarantine action in a Shortcuts Sleep automation. Waking Up follows your Health sleep schedule and wake-up alarm.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    manager.prepareMorningQuarantine()
                } label: {
                    Label(
                        manager.isMorningPrepared ? "Saved for Shortcuts" : "Save for Shortcuts",
                        systemImage: manager.isMorningPrepared ? "checkmark.circle.fill" : "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!manager.canPrepareMorningQuarantine)

                Button {
                    manager.startMorningQuarantineNow()
                } label: {
                    Label("Start one hour now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!manager.canPrepareMorningQuarantine)

                Text("For calls and notifications, add Apple’s Set Focus action to the same automation. BrewFocus only shields apps that Screen Time permits it to shield.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private var morningValidationMessage: some View {
        if manager.hasUnsupportedMorningSelection {
            Label(
                "Choose individual apps only; remove category and website selections.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.red)
        } else if manager.morningSelectedApplicationCount > 4 {
            Label(
                "Remove \(manager.morningSelectedApplicationCount - 4) app selections to continue.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.red)
        }
    }

    private var morningQuarantineActive: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sunrise.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Morning Quarantine")
                        .font(.headline)
                    Text(manager.morningRemainingText)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .accessibilityLabel("Morning quarantine time remaining")
                        .accessibilityValue(manager.morningRemainingText)
                }
                Spacer()
            }

            Text("Your app exceptions remain available. System and emergency functions may still appear.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                manager.endMorningQuarantine()
            } label: {
                Text("End today’s quarantine")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Removes the current morning shields; tomorrow’s daily schedule stays on")
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var coffeeOrder: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero(
                symbol: "cup.and.saucer.fill",
                title: "What can I get you?",
                subtitle: "The coffee decides how much freedom you keep."
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(CoffeeKind.allCases) { coffee in
                    Button {
                        manager.selectCoffee(coffee)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "cup.and.saucer.fill")
                                Spacer()
                                if manager.selectedCoffee == coffee {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            Text(coffee.name)
                                .font(.headline)
                            Text("\(coffee.focusLabel) · \(Int(coffee.duration / 60)) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .padding(14)
                        .background(
                            manager.selectedCoffee == coffee
                                ? Color.primary.opacity(0.1)
                                : Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Selects \(coffee.name) for the next session")
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(coffeeSelectionHeading)
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                if manager.selectedCoffee.restrictionMode == .none {
                    Label(
                        "No apps are blocked. Latte is a quiet timer and a put-the-phone-down cue.",
                        systemImage: "hand.raised"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        isActivityPickerPresented = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "app.badge.checkmark")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(coffeeSelectionButtonTitle)
                                    .font(.headline)
                                Text(selectionSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Apple’s private app picker")
                }

                Divider()

                Label("\(Int(manager.selectedCoffee.duration / 60)) min", systemImage: "timer")
                    .font(.headline.monospacedDigit())
                Text(coffeeContractDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))

            if manager.hasUnsupportedSelection {
                Label(
                    "Choose individual apps only. Remove category and website selections.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.red)
            } else if manager.selectedApplicationCount > manager.selectedCoffee.applicationSelectionRange.upperBound {
                Label(
                    "Remove \(manager.selectedApplicationCount - manager.selectedCoffee.applicationSelectionRange.upperBound) app selections to continue.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.red)
            }

            Button {
                Task {
                    await manager.startCoffee()
                }
            } label: {
                Label("Order \(manager.selectedCoffee.name)", systemImage: "cup.and.saucer.fill")
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!manager.canStartCoffee)
            .accessibilityHint("Starts the selected focus session")

            Button {
                manager.saveQuickCoffee()
            } label: {
                Label(
                    manager.isSelectedCoffeeQuick ? "Saved as Quick Coffee" : "Save as Quick Coffee",
                    systemImage: manager.isSelectedCoffeeQuick ? "checkmark.circle.fill" : "lock.rectangle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!manager.canSaveQuickCoffee)
            .accessibilityHint("Makes this recipe available from the Lock Screen widget")
        }
    }

    private var lockScreenWidgetGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Lock Screen Coffee", systemImage: "rectangle.on.rectangle")
                .font(.headline)
            if let quickCoffee = manager.quickCoffee {
                Text("Quick Coffee is \(quickCoffee.name). The widget starts it after Face ID and shows the countdown while it runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Save a Quick Coffee above, then add BrewFocus to your Lock Screen widgets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Add it: hold the Lock Screen → Customize → Lock Screen → Add Widgets → BrewFocus.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var activeSession: some View {
        VStack(spacing: 24) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(manager.remainingText)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue(manager.remainingText)
                Text(manager.session?.coffee.name ?? "Coffee")
                    .font(.title2.weight(.semibold))
                if let session = manager.session {
                    Text(activeSelectionSummary(session))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label(activeRestrictionSummary, systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                Text("The Lock Screen widget keeps the remaining time visible. BrewFocus removes its restrictions when the coffee ends.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))

            Button(role: .destructive) {
                manager.abort()
            } label: {
                Text("End coffee")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Ends this coffee and removes its BrewFocus restrictions")
        }
    }

    private func hero(symbol: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.bold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionPoint(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func completionBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.headline)
            Spacer()
            Button {
                manager.clearCompletion()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss completion")
        }
        .padding(.leading, 16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectionSummary: String {
        let range = manager.selectedCoffee.applicationSelectionRange
        switch manager.selectedApplicationCount {
        case 0:
            return "Choose \(range.lowerBound) to \(range.upperBound)"
        case 1:
            return "1 app selected"
        default:
            return "\(manager.selectedApplicationCount) apps selected"
        }
    }

    private var coffeeSelectionHeading: String {
        switch manager.selectedCoffee.restrictionMode {
        case .none: "LIGHT FOCUS"
        case .blockList: "WHAT SHOULD STAY OUT?"
        case .allowList: "WHAT DO YOU NEED?"
        }
    }

    private var coffeeSelectionButtonTitle: String {
        manager.selectedCoffee.restrictionMode == .blockList
            ? "Choose apps to block"
            : "Choose allowed apps"
    }

    private var coffeeContractDescription: String {
        switch manager.selectedCoffee {
        case .latte:
            "A soft start. BrewFocus keeps time and asks you to put the phone down without shielding apps."
        case .cappuccino:
            "Your selected distractions receive a Screen Time shield. Everything else stays available."
        case .americano:
            "Only your selected essentials stay available for a longer, stronger session."
        case .espresso:
            "Deep work. Only up to four selected apps stay available."
        }
    }

    private var activeRestrictionSummary: String {
        switch manager.session?.coffee.restrictionMode {
        case .some(.none):
            "No apps are blocked."
        case .some(.blockList):
            "Your selected distractions are shielded."
        case .some(.allowList):
            "Everything outside your essentials is shielded."
        case nil:
            "Your focus session is active."
        }
    }

    private func activeSelectionSummary(_ session: IPhoneFocusSession) -> String {
        switch session.coffee.restrictionMode {
        case .none:
            "Quiet timer"
        case .blockList:
            "\(session.selectedApplicationCount) apps blocked"
        case .allowList:
            "\(session.selectedApplicationCount) apps available"
        }
    }

    private var morningSelectionSummary: String {
        switch manager.morningSelectedApplicationCount {
        case 0:
            return "No exceptions — maximum quarantine"
        case 1:
            return "1 app stays available"
        default:
            return "\(manager.morningSelectedApplicationCount) apps stay available"
        }
    }

    private func scheduleTime(_ schedule: MorningQuarantineSchedule) -> String {
        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        let date = Calendar.current.date(from: components) ?? manager.morningStartTime
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// The daily task: start without a scan, or scan to finish an active session.
struct FocusTagHomeCard: View {
    let startedAt: Date?
    let applicationCount: Int
    let isReady: Bool
    let isScanning: Bool
    let shortcutControlEnabled: Bool
    let onStart: () -> Void
    let onScan: () -> Void
    let onSetup: () -> Void
    var isScanAvailable = FocusTagReader.isAvailable

    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let startedAt {
                HStack(spacing: 14) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(.primary.opacity(0.06), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focus is on").font(.headline)
                        Text(blockedAppsLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 12) {
                    Text("TIME IN FOCUS")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    FocusElapsedClock(startedAt: startedAt, fontSize: timerSize)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                FocusSessionTimeline(startedAt: startedAt)
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onScan) {
                        Label {
                            Text(isScanning ? "Scanning…" : "Scan tag to unlock")
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                        } icon: {
                            Image(systemName: "wave.3.right")
                        }
                            .font(.headline)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isScanning || !isScanAvailable)
                    .accessibilityHint("Opens the scanner. Your paired tag is needed to remove this session's restrictions.")
                    Text(shortcutControlEnabled
                         ? "You can also tap your tag directly if you have set up its Shortcuts automation."
                         : "Tap Scan, then hold the top of your iPhone near your tag.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isReady {
                Image(systemName: "cup.and.saucer")
                    .font(.title)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ready to focus").font(.title.weight(.semibold))
                    Text("Start anywhere. Unlock with your tag.")
                        .font(.body).foregroundStyle(.secondary)
                    Text(applicationCount == 1 ? "1 app will be blocked" : "\(applicationCount) apps will be blocked")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button(action: onStart) {
                    Label {
                        Text("Start Focus")
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isScanning)
                .accessibilityHint("Starts blocking your selected apps without scanning your tag")
            } else {
                Image(systemName: "cup.and.saucer")
                    .font(.title)
                    .accessibilityHidden(true)
                Text("Make room for focus").font(.title.weight(.semibold))
                Text("Choose the apps you want to put away and pair your tag. Then start focus from anywhere.")
                    .foregroundStyle(.secondary)
                Button(action: onSetup) {
                    Text("Set Up Focus")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .tint(.primary)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var blockedAppsLabel: String {
        applicationCount == 1 ? "1 app blocked" : "\(applicationCount) apps blocked"
    }
}

/// An open-ended record of elapsed quarter-hours, with no target or countdown.
private struct FocusSessionTimeline: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 60)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let step: TimeInterval = elapsed >= 604800 ? 604800 : elapsed >= 86400 ? 86400 : elapsed >= 3600 ? 3600 : 900
            let completed = Int(elapsed / step)
            let marks = completed > 0 ? Array(max(1, completed - 1)...completed) : []
            let startLabel = elapsed >= 86400
                ? startedAt.formatted(.dateTime.day().month(.abbreviated))
                : startedAt.formatted(date: .omitted, time: .shortened)
            let labels = [startLabel] + marks.map { FocusTagDuration.compact(Double($0) * step) } + ["Now"]
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(labels.indices, id: \.self) { index in
                        Circle()
                            .fill(index == labels.count - 1 ? Color.primary : Color.secondary)
                            .frame(width: 7, height: 7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.secondary.opacity(0.25))
                            .frame(width: geometry.size.width * CGFloat(labels.count - 1) / CGFloat(labels.count), height: 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(labels.indices, id: \.self) { index in
                        Text(labels[index])
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(index == labels.count - 1 ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Session timeline. Started \(startedAt.formatted(date: .abbreviated, time: .shortened)). \(marks.map { FocusTagDuration.compact(Double($0) * step) }.joined(separator: ", ")). Now.")
        }
    }
}

private struct FocusElapsedClock: View {
    let startedAt: Date
    let fontSize: CGFloat

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let days = max(0, Int(context.date.timeIntervalSince(startedAt) / 86400))
            let dayStart = startedAt.addingTimeInterval(Double(days) * 86400)
            VStack(spacing: 8) {
                if days > 0 {
                    Text(days >= 7 ? "\(days / 7)w \(days % 7)d" : "\(days)d")
                        .font(.title2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(dayStart, style: .timer)
                    .font(.system(size: fontSize, weight: .medium, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                if days > 0 {
                    Text("Hours · minutes · seconds")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed focus time")
            .accessibilityValue(FocusTagDuration.compact(context.date.timeIntervalSince(startedAt)))
        }
    }
}

private struct FocusLongestBlockCard: View {
    let startedAt: Date?
    let savedRecord: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: startedAt ?? Date(), by: 1)) { context in
            let current = max(0, startedAt.map { context.date.timeIntervalSince($0) } ?? 0)
            let record = max(savedRecord, current)
            VStack(alignment: .leading, spacing: 10) {
                Label("Longest block", systemImage: "trophy")
                    .font(.headline)
                Text(record > 0 ? FocusTagDuration.compact(record) : "No record yet")
                    .font(.title2.weight(.medium).monospacedDigit())
                    .contentTransition(.numericText())
                Text(current > 0 && current >= savedRecord
                     ? "Personal best · still running" : "Your longest uninterrupted tag session")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
