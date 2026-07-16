import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class RingOverlayController: NSObject, NSWindowDelegate {
    private let panelSize = NSSize(width: 572, height: 320)
    private let ringCenterOffset = NSPoint(x: 160, y: 160)

    private var panel: RingPanel?
    private var keyMonitor: Any?
    private var previousActiveApplication: NSRunningApplication?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(
        groups: [RingAppGroup],
        appSearchIndex: AppSearchIndex,
        catalogService: AppCatalogService,
        shortcutLabel: String,
        positionMode: RingOverlayPositionMode,
        onSelect: @MainActor @escaping (RingApp) -> Void,
        onSelectGroup: @MainActor @escaping (RingAppGroup) -> Void,
        onSearchSelect: @MainActor @escaping (DiscoveredApp) -> Void
    ) {
        let panel = self.panel ?? makePanel()
        previousActiveApplication = NSWorkspace.shared.frontmostApplication

        panel.contentView = NSHostingView(
            rootView: RingView(
                groups: groups,
                appSearchIndex: appSearchIndex,
                catalogService: catalogService,
                shortcutLabel: shortcutLabel,
                onSelect: onSelect,
                onSelectGroup: onSelectGroup,
                onSearchSelect: onSearchSelect,
                onDismiss: { [weak self] in
                    self?.hide()
                }
            )
        )

        position(panel: panel, mode: positionMode)
        installKeyMonitor()
        KeyboardInputSourceManager.selectEnglishInputSource()

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide(restorePreviousApplication: Bool = true) {
        guard let panel, panel.isVisible else {
            return
        }

        let applicationToRestore = restorePreviousApplication ? previousActiveApplication : nil
        previousActiveApplication = nil
        removeKeyMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)

                if let applicationToRestore,
                   applicationToRestore.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    applicationToRestore.activate(options: [.activateAllWindows])
                }
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide(restorePreviousApplication: false)
    }

    private func makePanel() -> RingPanel {
        let panel = RingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true

        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, mode: RingOverlayPositionMode) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = screenForCurrentPointer() ?? NSScreen.main
        let fallbackFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenFrame = screen?.visibleFrame ?? fallbackFrame

        let centerPoint: NSPoint = switch mode {
        case .screenCenter:
            NSPoint(x: screenFrame.midX, y: screenFrame.midY)
        case .followsMouse:
            mouseLocation
        }

        let idealOrigin = NSPoint(
            x: centerPoint.x - ringCenterOffset.x,
            y: centerPoint.y - ringCenterOffset.y
        )

        let origin = NSPoint(
            x: min(max(idealOrigin.x, screenFrame.minX), screenFrame.maxX - panelSize.width),
            y: min(max(idealOrigin.y, screenFrame.minY), screenFrame.maxY - panelSize.height)
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func screenForCurrentPointer() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else {
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                self?.hide()
                return nil
            case kVK_DownArrow:
                NotificationCenter.default.post(name: .ringSearchMoveDown, object: nil)
                return nil
            case kVK_UpArrow:
                NotificationCenter.default.post(name: .ringSearchMoveUp, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private final class RingPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
