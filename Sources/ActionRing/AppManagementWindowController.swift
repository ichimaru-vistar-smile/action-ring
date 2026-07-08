import AppKit
import SwiftUI

@MainActor
final class AppManagementWindowController: NSWindowController, NSWindowDelegate {
    private let store: AppConfigurationStore
    private let launchAtLoginManager: LaunchAtLoginManager
    private let onAddApp: @MainActor (RingGroupDirection) -> Void

    init(
        store: AppConfigurationStore,
        launchAtLoginManager: LaunchAtLoginManager,
        onAddApp: @MainActor @escaping (RingGroupDirection) -> Void
    ) {
        self.store = store
        self.launchAtLoginManager = launchAtLoginManager
        self.onAddApp = onAddApp

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Manage Apps"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        if !window.setFrameAutosaveName("ActionRingManageAppsWindow") {
            window.center()
        }

        window.contentView = NSHostingView(
            rootView: AppManagementView(
                store: store,
                launchAtLoginManager: launchAtLoginManager,
                onAddApp: onAddApp
            )
        )

        super.init(window: window)
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
