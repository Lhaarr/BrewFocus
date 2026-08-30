import FamilyControls
import SwiftUI
import UIKit

struct IPhoneRootView: View {
    @ObservedObject var manager: IPhoneFocusManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var isActivityPickerPresented = false
    @State private var isMorningPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let completionMessage = manager.completionMessage {
                        completionBanner(completionMessage)
                    }

                    if manager.isMorningQuarantineActive {
                        morningQuarantineActive
                    }

                    if manager.session != nil {
                        activeSession
                    } else if manager.isAuthorized {
                        authorizedHome
                    } else {
                        authorizationIntroduction
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("BrewFocus")
            .navigationBarTitleDisplayMode(.large)
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
            manager.handle(url)
        }
        .onChange(of: isMorningPickerPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                manager.prepareMorningQuarantine()
            }
        }
        .task {
            manager.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                manager.refreshAfterBecomingActive()
            }
        }
        .alert(
            "BrewFocus couldn’t continue",
            isPresented: Binding(
                get: { manager.lastError != nil },
                set: { isPresented in
                    if !isPresented {
                        manager.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                manager.clearError()
            }
        } message: {
            Text(manager.lastError ?? "Unknown error")
        }
    }

    private var authorizedHome: some View {
        VStack(spacing: 30) {
            coffeeRhythm
            coffeeOrder
            lockScreenWidgetGuide
            Divider()
            morningQuarantineOrder
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
                    detail: "Ending a coffee removes every shield BrewFocus applied."
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
