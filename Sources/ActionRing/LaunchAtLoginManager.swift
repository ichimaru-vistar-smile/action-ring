import AppKit
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isSupported = false
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusDescription = "Available in a bundled .app."
    @Published private(set) var installDescription = ""
    @Published private(set) var installButtonTitle = "Install to Applications"
    @Published private(set) var shouldOfferInstall = false

    init() {
        refresh()
    }

    func refresh() {
        refreshInstallState()

        guard supportsLaunchAtLogin else {
            isSupported = false
            isEnabled = false
            requiresApproval = false
            statusDescription = "Available after packaging Action Ring as a .app."
            return
        }

        isSupported = true

        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
            statusDescription = "Action Ring will launch automatically when you log in."
        case .notRegistered:
            isEnabled = false
            requiresApproval = false
            statusDescription = "Action Ring will stay manual until you enable launch at login."
        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
            statusDescription = "Login item needs approval in System Settings."
        case .notFound:
            isSupported = true
            isEnabled = false
            requiresApproval = false
            statusDescription = "Action Ring is installed, but launch at login is not registered yet. You can enable it from this window."
        @unknown default:
            isEnabled = false
            requiresApproval = false
            statusDescription = "Launch at login status is unavailable right now."
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard supportsLaunchAtLogin else {
            NSSound.beep()
            refresh()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }

        refresh()

        if requiresApproval {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        guard supportsLaunchAtLogin else {
            NSSound.beep()
            return
        }

        SMAppService.openSystemSettingsLoginItems()
    }

    func installToApplications() {
        guard let sourceURL = appBundleURL, let destinationURL = preferredInstallURL else {
            NSSound.beep()
            return
        }

        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                if destinationURL.standardizedFileURL != sourceURL.standardizedFileURL {
                    var trashedURL: NSURL?
                    try fileManager.trashItem(at: destinationURL, resultingItemURL: &trashedURL)
                } else {
                    refresh()
                    return
                }
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            relaunchInstalledCopy(at: destinationURL)
        } catch {
            NSSound.beep()
            refresh()
        }
    }

    private var supportsLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var appBundleURL: URL? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }

        return Bundle.main.bundleURL.standardizedFileURL
    }

    private var preferredInstallURL: URL? {
        guard let appBundleURL else {
            return nil
        }

        return userApplicationsDirectory.appendingPathComponent(appBundleURL.lastPathComponent)
    }

    private var userApplicationsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
    }

    private var isInstalledInApplications: Bool {
        guard let appBundleURL else {
            return false
        }

        let currentPath = appBundleURL.path
        let userApplicationsPath = userApplicationsDirectory.standardizedFileURL.path
        return currentPath.hasPrefix("/Applications/") || currentPath.hasPrefix(userApplicationsPath + "/")
    }

    private func refreshInstallState() {
        guard supportsLaunchAtLogin else {
            installDescription = ""
            installButtonTitle = "Install to Applications"
            shouldOfferInstall = false
            return
        }

        if isInstalledInApplications {
            installDescription = "Action Ring is running from Applications."
            installButtonTitle = "Install to Applications"
            shouldOfferInstall = false
            return
        }

        installDescription = "Install a copy in Applications for a more stable launch-at-login setup."
        installButtonTitle = "Install to Applications"
        shouldOfferInstall = true
    }

    private func relaunchInstalledCopy(at destinationURL: URL) {
        let escapedPath = destinationURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let command = "sleep 0.3; open \"\(escapedPath)\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            NSSound.beep()
            refresh()
        }
    }
}
