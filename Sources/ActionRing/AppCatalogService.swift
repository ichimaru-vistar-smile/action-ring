import AppKit
import CoreGraphics
import OSLog

@MainActor
final class AppCatalogService {
    private let finderBundleIdentifier = "com.apple.finder"
    private let groupWakeVerificationAttempts = 8
    private let groupWakeVerificationInterval: TimeInterval = 0.15
    private nonisolated static let logger = Logger(
        subsystem: "app.action-ring.desktop",
        category: "AppLaunch"
    )

    private struct DefaultAppDescriptor {
        let bundleIdentifier: String
        let fallbackName: String
        let fallbackSymbol: String
    }

    private let defaultApps: [DefaultAppDescriptor] = [
        .init(bundleIdentifier: "com.apple.iCal", fallbackName: "Calendar", fallbackSymbol: "calendar"),
        .init(bundleIdentifier: "com.apple.mail", fallbackName: "Mail", fallbackSymbol: "envelope.fill"),
        .init(bundleIdentifier: "com.apple.Notes", fallbackName: "Notes", fallbackSymbol: "note.text"),
        .init(bundleIdentifier: "com.apple.systempreferences", fallbackName: "Settings", fallbackSymbol: "gearshape.fill"),
        .init(bundleIdentifier: "com.apple.Photos", fallbackName: "Photos", fallbackSymbol: "camera.fill"),
        .init(bundleIdentifier: "com.apple.Safari", fallbackName: "Safari", fallbackSymbol: "globe"),
        .init(bundleIdentifier: "com.apple.MobileSMS", fallbackName: "Messages", fallbackSymbol: "message.fill"),
        .init(bundleIdentifier: "com.apple.Music", fallbackName: "Music", fallbackSymbol: "music.note"),
        .init(bundleIdentifier: "com.apple.AppStore", fallbackName: "App Store", fallbackSymbol: "bag.fill"),
        .init(bundleIdentifier: "com.apple.Terminal", fallbackName: "Terminal", fallbackSymbol: "terminal.fill")
    ]

    func defaultConfigurations() -> [AppConfiguration] {
        defaultApps.compactMap { descriptor in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) else {
                return nil
            }

            return configuration(
                bundleIdentifier: descriptor.bundleIdentifier,
                fallbackName: descriptor.fallbackName,
                url: url
            )
        }
    }

    func resolveApps(from configurations: [AppConfiguration]) -> [RingApp] {
        configurations.map { configuration in
            RingApp(
                id: configuration.id,
                bundleIdentifier: configuration.bundleIdentifier,
                name: configuration.name,
                url: configuration.url,
                icon: previewIcon(for: configuration)
            )
        }
    }

    func configuration(forApplicationAt url: URL) -> AppConfiguration? {
        guard url.pathExtension.lowercased() == "app" else {
            return nil
        }

        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier
        let fallbackName = url.deletingPathExtension().lastPathComponent

        return configuration(
            bundleIdentifier: bundleIdentifier,
            fallbackName: fallbackName,
            url: url
        )
    }

    func previewIcon(for configuration: AppConfiguration) -> NSImage {
        resolveIcon(for: configuration.url, fallbackSymbol: "app.fill")
    }

    func previewIcon(forApplicationURL url: URL) -> NSImage {
        resolveIcon(for: url, fallbackSymbol: "app.fill")
    }

    func launchOrActivate(_ app: RingApp) {
        guard FileManager.default.fileExists(atPath: app.url.path) else {
            NSSound.beep()
            return
        }

        let runningApplication = runningApplication(for: app)

        if app.bundleIdentifier == finderBundleIdentifier {
            openApplication(at: app.url)
            return
        }

        if let runningApplication {
            if runningApplication.isHidden || hasVisibleWindow(for: runningApplication) {
                runningApplication.activate(options: [.activateAllWindows])
            } else {
                openApplication(at: app.url)
            }
            return
        }

        openApplication(at: app.url)
    }

    func launchOrActivate(_ app: DiscoveredApp) {
        launchOrActivate(
            RingApp(
                id: UUID(),
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                url: app.url,
                icon: previewIcon(forApplicationURL: app.url)
            )
        )
    }

    func launchGroup(_ apps: [RingApp]) {
        guard let first = apps.first else {
            return
        }

        let secondaryApps = Array(apps.dropFirst())
        Self.logger.notice("Launching app group with \(apps.count) members; final focus: \(first.name, privacy: .public)")

        wakeGroupMembers(secondaryApps, at: 0) { [weak self] in
            self?.launchOrActivate(first)
        }
    }

    private func wakeGroupMembers(
        _ apps: [RingApp],
        at index: Int,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard index < apps.count else {
            completion()
            return
        }

        wakeGroupMember(apps[index]) { [weak self] in
            self?.wakeGroupMembers(apps, at: index + 1, completion: completion) ?? completion()
        }
    }

    private func wakeGroupMember(
        _ app: RingApp,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard FileManager.default.fileExists(atPath: app.url.path) else {
            Self.logger.error("Cannot wake group member \(app.name, privacy: .public): application is missing at \(app.url.path, privacy: .public)")
            NSSound.beep()
            completion()
            return
        }

        requestGroupMemberWake(app) { [weak self] in
            guard let self else {
                completion()
                return
            }

            self.verifyGroupMemberWake(
                app,
                attemptsRemaining: self.groupWakeVerificationAttempts,
                allowsRetry: true,
                completion: completion
            )
        }
    }

    private func requestGroupMemberWake(
        _ app: RingApp,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard app.bundleIdentifier != finderBundleIdentifier else {
            openApplication(at: app.url) { _ in completion() }
            return
        }

        guard let runningApplication = runningApplication(for: app) else {
            openApplication(at: app.url) { _ in completion() }
            return
        }

        if runningApplication.isHidden || hasVisibleWindow(for: runningApplication) {
            if runningApplication.activate(options: [.activateAllWindows]) {
                completion()
            } else {
                openApplication(at: app.url) { _ in completion() }
            }
        } else {
            // A running application can have no on-screen window (for example,
            // after its last window was closed). Reopening it is more reliable
            // than treating a successful activation request as a completed wake.
            openApplication(at: app.url) { _ in completion() }
        }
    }

    private func verifyGroupMemberWake(
        _ app: RingApp,
        attemptsRemaining: Int,
        allowsRetry: Bool,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        if let runningApplication = runningApplication(for: app),
           runningApplication.isActive,
           hasVisibleWindow(for: runningApplication) {
            Self.logger.notice("Group member became active with a visible window: \(app.name, privacy: .public)")

            // Becoming active and presenting the window are separate AppKit
            // transitions. Give the member a brief turn before another app in
            // the group takes focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + groupWakeVerificationInterval) {
                completion()
            }
            return
        }

        guard attemptsRemaining > 0 else {
            if allowsRetry {
                Self.logger.notice("Retrying group member wake: \(app.name, privacy: .public)")
                requestGroupMemberWake(app) { [weak self] in
                    guard let self else {
                        completion()
                        return
                    }

                    self.verifyGroupMemberWake(
                        app,
                        attemptsRemaining: self.groupWakeVerificationAttempts,
                        allowsRetry: false,
                        completion: completion
                    )
                }
            } else {
                Self.logger.error("Group member did not become active with a visible window after retry: \(app.name, privacy: .public)")
                completion()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + groupWakeVerificationInterval) { [weak self] in
            self?.verifyGroupMemberWake(
                app,
                attemptsRemaining: attemptsRemaining - 1,
                allowsRetry: allowsRetry,
                completion: completion
            ) ?? completion()
        }
    }

    private func openApplication(
        at url: URL,
        activates: Bool = true,
        completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        let applicationPath = url.path

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            let succeeded = error == nil

            if let error {
                Self.logger.error("Failed to open \(applicationPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            DispatchQueue.main.async {
                if !succeeded {
                    NSSound.beep()
                }
                completion(succeeded)
            }
        }
    }

    private func configuration(
        bundleIdentifier: String?,
        fallbackName: String,
        url: URL
    ) -> AppConfiguration {
        let bundle = Bundle(url: url)
        let resolvedBundleIdentifier = bundle?.bundleIdentifier ?? bundleIdentifier
        let name = (
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ) ?? (
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        ) ?? fallbackName

        return AppConfiguration(
            bundleIdentifier: resolvedBundleIdentifier,
            name: name,
            path: url.path
        )
    }

    private func runningApplication(for app: RingApp) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first(where: {
            if let bundleIdentifier = app.bundleIdentifier {
                return $0.bundleIdentifier == bundleIdentifier
            }

            return $0.bundleURL?.path == app.url.path
        })
    }

    private func hasVisibleWindow(for app: NSRunningApplication) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let processIdentifier = app.processIdentifier

        return windowList.contains { windowInfo in
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == processIdentifier else {
                return false
            }

            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else {
                return false
            }

            let alpha = windowInfo[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.01 else {
                return false
            }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 40,
                  bounds.height >= 40 else {
                return false
            }

            return true
        }
    }

    private func resolveIcon(for url: URL, fallbackSymbol: String) -> NSImage {
        if FileManager.default.fileExists(atPath: url.path) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 64, height: 64)
            return icon
        }

        let icon = NSImage(
            systemSymbolName: fallbackSymbol,
            accessibilityDescription: nil
        ) ?? NSImage(size: NSSize(width: 64, height: 64))

        icon.size = NSSize(width: 64, height: 64)
        return icon
    }
}
