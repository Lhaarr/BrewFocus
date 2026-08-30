import AppKit
import Foundation

struct RestrictedApplication: Equatable, Sendable {
    let bundleIdentifier: String
    let name: String
}

@MainActor
protocol FocusRestricting: AnyObject {
    func start(
        restriction: ApplicationRestriction,
        onHidden: @escaping (RestrictedApplication) -> Void,
        onBlockedAttempt: @escaping (RestrictedApplication) -> Void,
        onRestrictionFailure: @escaping (RestrictedApplication) -> Void
    )

    func stop(restoring bundleIdentifiers: Set<String>)
    func restore(bundleIdentifiers: Set<String>)
}

@MainActor
final class WorkspaceRestrictionMonitor: FocusRestricting {
    private let workspace: NSWorkspace
    private let ownBundleIdentifier: String?
    private var activationObserver: NSObjectProtocol?
    private var restriction = ApplicationRestriction(mode: .none, bundleIdentifiers: [])
    private var onHidden: ((RestrictedApplication) -> Void)?
    private var onBlockedAttempt: ((RestrictedApplication) -> Void)?
    private var onRestrictionFailure: ((RestrictedApplication) -> Void)?
    private weak var lastAllowedApplication: NSRunningApplication?

    init(
        workspace: NSWorkspace = .shared,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.workspace = workspace
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    func start(
        restriction: ApplicationRestriction,
        onHidden: @escaping (RestrictedApplication) -> Void,
        onBlockedAttempt: @escaping (RestrictedApplication) -> Void,
        onRestrictionFailure: @escaping (RestrictedApplication) -> Void
    ) {
        removeObserver()
        self.restriction = restriction
        self.onHidden = onHidden
        self.onBlockedAttempt = onBlockedAttempt
        self.onRestrictionFailure = onRestrictionFailure

        guard restriction.mode != .none else { return }

        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleActivation(notification)
            }
        }

        hideCurrentlyRunningDisallowedApps()
        activateFirstPermittedAppIfNeeded()
    }

    func stop(restoring bundleIdentifiers: Set<String>) {
        removeObserver()
        restore(bundleIdentifiers: bundleIdentifiers)
        restriction = ApplicationRestriction(mode: .none, bundleIdentifiers: [])
        onHidden = nil
        onBlockedAttempt = nil
        onRestrictionFailure = nil
        lastAllowedApplication = nil
    }

    func restore(bundleIdentifiers: Set<String>) {
        guard !bundleIdentifiers.isEmpty else { return }

        for application in workspace.runningApplications {
            guard
                let bundleIdentifier = application.bundleIdentifier,
                bundleIdentifiers.contains(bundleIdentifier),
                application.isHidden
            else {
                continue
            }

            _ = application.unhide()
        }
    }

    private func handleActivation(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            shouldConsider(application)
        else {
            return
        }

        if isPermitted(application) {
            lastAllowedApplication = application
            return
        }

        let restrictedApplication = descriptor(for: application)
        if application.hide() {
            onHidden?(restrictedApplication)
            onBlockedAttempt?(restrictedApplication)
        } else {
            onRestrictionFailure?(restrictedApplication)
        }
        returnToPermittedApplication()
    }

    private func hideCurrentlyRunningDisallowedApps() {
        for application in workspace.runningApplications {
            guard
                shouldConsider(application),
                !isPermitted(application),
                !application.isHidden
            else {
                continue
            }

            if application.hide() {
                onHidden?(descriptor(for: application))
            } else {
                onRestrictionFailure?(descriptor(for: application))
            }
        }
    }

    private func activateFirstPermittedAppIfNeeded() {
        if let frontmostApplication = workspace.frontmostApplication,
           isPermittedDestination(frontmostApplication) {
            lastAllowedApplication = frontmostApplication
            return
        }

        lastAllowedApplication = workspace.runningApplications.first(where: isPermittedDestination)
        returnToPermittedApplication()
    }

    private func returnToPermittedApplication() {
        if lastAllowedApplication?.isTerminated != false {
            lastAllowedApplication = workspace.runningApplications.first(where: isPermittedDestination)
        }

        _ = lastAllowedApplication?.activate(options: [.activateAllWindows])
    }

    private func shouldConsider(_ application: NSRunningApplication) -> Bool {
        guard
            application.activationPolicy == .regular,
            !application.isTerminated,
            let bundleIdentifier = application.bundleIdentifier
        else {
            return false
        }

        return bundleIdentifier != ownBundleIdentifier
    }

    private func isPermitted(_ application: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = application.bundleIdentifier else {
            return true
        }
        guard bundleIdentifier != ownBundleIdentifier else { return true }

        return !restriction.restricts(bundleIdentifier: bundleIdentifier)
    }

    private func isPermittedDestination(_ application: NSRunningApplication) -> Bool {
        shouldConsider(application) && isPermitted(application)
    }

    private func descriptor(for application: NSRunningApplication) -> RestrictedApplication {
        let bundleIdentifier = application.bundleIdentifier ?? "unknown"
        return RestrictedApplication(
            bundleIdentifier: bundleIdentifier,
            name: application.localizedName ?? bundleIdentifier
        )
    }

    private func removeObserver() {
        if let activationObserver {
            workspace.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    deinit {
        if let activationObserver {
            workspace.notificationCenter.removeObserver(activationObserver)
        }
    }
}
