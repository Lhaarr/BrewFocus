import AppKit
import Foundation

protocol ApplicationCataloging {
    func runningApplications() -> [AllowedApplication]
}
struct WorkspaceApplicationCatalog: ApplicationCataloging {
    private let workspace: NSWorkspace
    private let ownBundleIdentifier: String?

    init(
        workspace: NSWorkspace = .shared,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.workspace = workspace
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    func runningApplications() -> [AllowedApplication] {
        var applicationsByIdentifier: [String: AllowedApplication] = [:]

        for application in workspace.runningApplications {
            guard
                application.activationPolicy == .regular,
                !application.isTerminated,
                let bundleIdentifier = application.bundleIdentifier,
                bundleIdentifier != ownBundleIdentifier
            else {
                continue
            }

            applicationsByIdentifier[bundleIdentifier] = AllowedApplication(
                bundleIdentifier: bundleIdentifier,
                name: application.localizedName ?? bundleIdentifier,
                bundleURLPath: application.bundleURL?.path
            )
        }

        return applicationsByIdentifier.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
