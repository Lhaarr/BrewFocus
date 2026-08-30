import DeviceActivity
import Foundation

final class BrewFocusDeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if ScreenTimeShared.coffee(for: activity) != nil {
            ScreenTimeShared.reapplyActiveCoffee(for: activity)
            return
        }

        switch activity {
        case .brewFocusMorningDaily:
            startDailyMorningQuarantine()
        case .brewFocusMorningShortcut:
            startShortcutMorningQuarantine()
        default:
            return
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if ScreenTimeShared.coffee(for: activity) != nil {
            ScreenTimeShared.finishCoffeeInterval(for: activity)
            return
        }

        switch activity {
        case .brewFocusMorningDaily:
            ScreenTimeShared.clearMorningRestriction(source: .daily)
        case .brewFocusMorningShortcut:
            ScreenTimeShared.clearMorningRestriction(source: .shortcut)
        default:
            return
        }
    }

    private func startDailyMorningQuarantine() {
        let selection = ScreenTimeShared.loadMorningSelection()
        guard
            ScreenTimeShared.isMorningPrepared,
            ScreenTimeShared.isValidMorningSelection(selection),
            let schedule = ScreenTimeShared.loadMorningSchedule(),
            let endsAt = schedule.activeEndDate(at: Date()),
            !ScreenTimeShared.isDailyMorningQuarantineSuppressed(at: Date())
        else {
            ScreenTimeShared.clearMorningRestriction(source: .daily)
            return
        }

        do {
            try ScreenTimeShared.saveMorningEndsAt(endsAt, source: .daily)
            ScreenTimeShared.applyMorningShield(using: selection, source: .daily)
        } catch {
            ScreenTimeShared.clearMorningRestriction(source: .daily)
        }
    }

    private func startShortcutMorningQuarantine() {
        let selection = ScreenTimeShared.loadMorningSelection()
        guard
            ScreenTimeShared.isMorningPrepared,
            ScreenTimeShared.isValidMorningSelection(selection),
            let endsAt = ScreenTimeShared.loadMorningEndsAt(source: .shortcut),
            endsAt > Date()
        else {
            ScreenTimeShared.clearMorningRestriction(source: .shortcut)
            return
        }

        ScreenTimeShared.applyMorningShield(using: selection, source: .shortcut)
    }
}
