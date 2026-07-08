import AppKit
import Combine

@MainActor
final class ActionRingController {
    private let overlayController = RingOverlayController()
    private let catalogService: AppCatalogService
    private let appSearchIndex = AppSearchIndex()
    private let configurationStore: AppConfigurationStore
    private let launchAtLoginManager = LaunchAtLoginManager()
    private var cancellables = Set<AnyCancellable>()
    private var installedAppPickerWindowController: InstalledAppPickerWindowController?

    private lazy var appManagementWindowController = AppManagementWindowController(
        store: configurationStore,
        launchAtLoginManager: launchAtLoginManager,
        onAddApp: { [weak self] direction in
            self?.showInstalledAppPicker(for: direction)
        }
    )

    init() {
        let catalogService = AppCatalogService()
        self.catalogService = catalogService
        self.configurationStore = AppConfigurationStore(catalogService: catalogService)
    }

    func start() {
        launchAtLoginManager.refresh()
        appSearchIndex.loadIfNeeded()

        HotKeyManager.shared.onKeyDown = { [weak self] in
            self?.toggleRing()
        }

        configurationStore.$preferences
            .map(\.hotKey)
            .removeDuplicates()
            .sink { configuration in
                if !HotKeyManager.shared.register(configuration) {
                    _ = HotKeyManager.shared.register(.default)
                }
            }
            .store(in: &cancellables)
    }

    func showRing() {
        let groups = configurationStore.ringGroups()

        overlayController.show(
            groups: groups,
            appSearchIndex: appSearchIndex,
            catalogService: catalogService,
            shortcutLabel: configurationStore.shortcutDisplayString,
            positionMode: configurationStore.overlayPositionMode
        ) { [weak self] app in
            self?.catalogService.launchOrActivate(app)
            self?.overlayController.hide(restorePreviousApplication: false)
        } onSearchSelect: { [weak self] app in
            self?.catalogService.launchOrActivate(app)
            self?.overlayController.hide(restorePreviousApplication: false)
        }
    }

    func showAppManagement() {
        overlayController.hide(restorePreviousApplication: false)
        launchAtLoginManager.refresh()
        DispatchQueue.main.async { [weak self] in
            self?.appManagementWindowController.showWindow()
        }
    }

    var shortcutDisplayString: String {
        configurationStore.shortcutDisplayString
    }

    var totalAppCount: Int {
        configurationStore.totalItemCount
    }

    var loginItemManager: LaunchAtLoginManager {
        launchAtLoginManager
    }

    func refreshRuntimeStatus() {
        launchAtLoginManager.refresh()
    }

    func openConfigurationDirectory() {
        NSWorkspace.shared.open(configurationStore.configurationDirectoryURL)
    }

    private func toggleRing() {
        if overlayController.isVisible {
            overlayController.hide()
        } else {
            showRing()
        }
    }

    private func showInstalledAppPicker(for direction: RingGroupDirection) {
        overlayController.hide(restorePreviousApplication: false)
        appManagementWindowController.showWindow()

        installedAppPickerWindowController = InstalledAppPickerWindowController(
            direction: direction,
            existingItems: configurationStore.allItems,
            catalogService: catalogService,
            onAdd: { [weak self] url in
                self?.configurationStore.addApp(from: url, to: direction) ?? false
            },
            onCloseRequest: { [weak self] in
                self?.installedAppPickerWindowController = nil
            }
        )
        installedAppPickerWindowController?.showWindow()
    }
}
