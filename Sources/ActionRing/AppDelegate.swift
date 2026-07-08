import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = ActionRingController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "circle.grid.2x2.fill",
                accessibilityDescription: "Action Ring"
            )
            button.imagePosition = .imageOnly
            button.toolTip = "Action Ring"
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Ring", action: #selector(showRing), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let manageItem = NSMenuItem(title: "Settings", action: #selector(showAppManagement), keyEquivalent: ",")
        manageItem.target = self
        menu.addItem(manageItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Action Ring", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func showRing() {
        controller.showRing()
    }

    @objc private func showAppManagement() {
        controller.showAppManagement()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.refreshRuntimeStatus()
    }
}
