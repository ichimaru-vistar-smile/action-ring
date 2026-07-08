import AppKit
import SwiftUI

@MainActor
final class InstalledAppPickerWindowController: NSWindowController, NSWindowDelegate {
    private let onCloseRequest: @MainActor () -> Void

    init(
        direction: RingGroupDirection,
        existingItems: [AppConfiguration],
        catalogService: AppCatalogService,
        onAdd: @escaping @MainActor (URL) -> Bool,
        onCloseRequest: @escaping @MainActor () -> Void
    ) {
        self.onCloseRequest = onCloseRequest

        let viewModel = InstalledAppPickerViewModel(
            existingItems: existingItems,
            discoveryService: InstalledAppDiscoveryService(),
            onAdd: onAdd
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Add App to \(direction.title)"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        window.contentView = NSHostingView(
            rootView: InstalledAppPickerView(
                direction: direction,
                viewModel: viewModel,
                catalogService: catalogService,
                onClose: { [weak window] in
                    window?.close()
                }
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
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onCloseRequest()
    }
}
