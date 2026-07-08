import AppKit
import Combine

@MainActor
final class InstalledAppPickerViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published private(set) var isLoading = false
    @Published var selectedAppID: DiscoveredApp.ID?

    private let existingItems: [AppConfiguration]
    private let discoveryService: InstalledAppDiscoveryService
    private let onAdd: @MainActor (URL) -> Bool

    init(
        existingItems: [AppConfiguration],
        discoveryService: InstalledAppDiscoveryService,
        onAdd: @escaping @MainActor (URL) -> Bool
    ) {
        self.existingItems = existingItems
        self.discoveryService = discoveryService
        self.onAdd = onAdd
    }

    var filteredApps: [DiscoveredApp] {
        guard !searchText.isEmpty else {
            return apps
        }

        let normalized = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return apps
        }

        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(normalized)
                || app.path.localizedCaseInsensitiveContains(normalized)
                || (app.bundleIdentifier?.localizedCaseInsensitiveContains(normalized) ?? false)
        }
    }

    var selectedApp: DiscoveredApp? {
        if let selectedAppID {
            return filteredApps.first(where: { $0.id == selectedAppID })
                ?? apps.first(where: { $0.id == selectedAppID })
        }

        return filteredApps.first
    }

    func loadIfNeeded() {
        guard apps.isEmpty, !isLoading else {
            return
        }

        isLoading = true
        let discoveryService = discoveryService
        let existingItems = existingItems

        Task {
            let discoveredApps = await Task.detached(priority: .userInitiated) {
                discoveryService.discoverInstalledApps(excluding: existingItems)
            }.value

            apps = discoveredApps
            isLoading = false
            selectedAppID = discoveredApps.first?.id
        }
    }

    func select(_ app: DiscoveredApp) {
        selectedAppID = app.id
    }

    @discardableResult
    func addSelectedApp() -> Bool {
        guard let selectedApp else {
            NSSound.beep()
            return false
        }

        return onAdd(selectedApp.url)
    }
}
