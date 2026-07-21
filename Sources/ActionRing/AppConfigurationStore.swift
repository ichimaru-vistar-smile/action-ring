import AppKit
import Combine

@MainActor
final class AppConfigurationStore: ObservableObject {
    @Published private(set) var groups: [AppGroupConfiguration] = AppGroupConfiguration.emptyGroups()
    @Published private(set) var preferences: ActionRingPreferences = .default

    private let catalogService: AppCatalogService
    private let fileManager = FileManager.default

    init(catalogService: AppCatalogService) {
        self.catalogService = catalogService
        load()
    }

    var allItems: [AppConfiguration] {
        groups.flatMap(\.items)
    }

    var totalItemCount: Int {
        allItems.count
    }

    func ringGroups() -> [RingAppGroup] {
        groups.map { group in
            RingAppGroup(
                direction: group.direction,
                apps: catalogService.resolveApps(from: group.items),
                groupedAppIDs: group.groupedAppIDs
            )
        }
    }

    func group(for direction: RingGroupDirection) -> AppGroupConfiguration {
        groups.first(where: { $0.direction == direction }) ?? AppGroupConfiguration(direction: direction)
    }

    func items(for direction: RingGroupDirection) -> [AppConfiguration] {
        group(for: direction).items
    }

    func previewIcon(for item: AppConfiguration) -> NSImage {
        catalogService.previewIcon(for: item)
    }

    var shortcutDisplayString: String {
        preferences.hotKey.displayString
    }

    var overlayPositionMode: RingOverlayPositionMode {
        preferences.overlayPosition
    }

    var screenEdgeHoldKey: ScreenEdgeHoldKey {
        preferences.screenEdgeHoldKey
    }

    var configurationDirectoryURL: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("ActionRing", isDirectory: true)
    }

    func canAdd(to direction: RingGroupDirection) -> Bool {
        items(for: direction).count < AppGroupConfiguration.maxItemCount
    }

    @discardableResult
    func addApp(from url: URL, to direction: RingGroupDirection) -> Bool {
        guard canAdd(to: direction) else {
            NSSound.beep()
            return false
        }

        guard let configuration = catalogService.configuration(forApplicationAt: url) else {
            NSSound.beep()
            return false
        }

        let alreadyExists = allItems.contains { item in
            if let bundleIdentifier = configuration.bundleIdentifier,
               bundleIdentifier == item.bundleIdentifier {
                return true
            }

            return item.path == configuration.path
        }

        guard !alreadyExists else {
            NSSound.beep()
            return false
        }

        mutateGroup(direction) { group in
            group.items.append(configuration)
        }
        persist()
        return true
    }

    func remove(id: UUID, from direction: RingGroupDirection) {
        mutateGroup(direction) { group in
            group.items.removeAll { $0.id == id }
        }
        persist()
    }

    func setGroupedAppIDs(_ ids: [UUID], for direction: RingGroupDirection) {
        mutateGroup(direction) { group in
            group.groupedAppIDs = ids
        }
        persist()
    }

    func setDefaultTarget(_ target: DirectionDefaultTarget?, for direction: RingGroupDirection) {
        mutateGroup(direction) { group in
            group.defaultTarget = target
        }
        persist()
    }

    func moveUp(id: UUID, in direction: RingGroupDirection) {
        mutateGroup(direction) { group in
            guard let index = group.items.firstIndex(where: { $0.id == id }), index > 0 else {
                return
            }

            group.items.swapAt(index, index - 1)
        }
        persist()
    }

    func moveDown(id: UUID, in direction: RingGroupDirection) {
        mutateGroup(direction) { group in
            guard let index = group.items.firstIndex(where: { $0.id == id }), index < group.items.count - 1 else {
                return
            }

            group.items.swapAt(index, index + 1)
        }
        persist()
    }

    func canMoveUp(id: UUID, in direction: RingGroupDirection) -> Bool {
        guard let index = items(for: direction).firstIndex(where: { $0.id == id }) else {
            return false
        }

        return index > 0
    }

    func canMoveDown(id: UUID, in direction: RingGroupDirection) -> Bool {
        guard let index = items(for: direction).firstIndex(where: { $0.id == id }) else {
            return false
        }

        return index < items(for: direction).count - 1
    }

    func canMove(_ id: UUID, from source: RingGroupDirection, to destination: RingGroupDirection) -> Bool {
        guard source != destination else {
            return false
        }

        guard items(for: source).contains(where: { $0.id == id }) else {
            return false
        }

        return canAdd(to: destination)
    }

    func move(_ id: UUID, from source: RingGroupDirection, to destination: RingGroupDirection) {
        guard canMove(id, from: source, to: destination) else {
            NSSound.beep()
            return
        }

        guard let item = items(for: source).first(where: { $0.id == id }) else {
            return
        }

        mutateGroup(source) { group in
            group.items.removeAll { $0.id == id }
        }

        mutateGroup(destination) { group in
            group.items.append(item)
        }

        persist()
    }

    func resetToDefaults() {
        groups = AppGroupConfiguration.distributed(from: catalogService.defaultConfigurations())
        persist()
    }

    func updateHotKeyKeyCode(_ keyCode: UInt32) {
        preferences.hotKey = HotKeyConfiguration(
            keyCode: keyCode,
            modifiers: preferences.hotKey.modifiers
        )
        persist()
    }

    func updateOverlayPositionMode(_ mode: RingOverlayPositionMode) {
        guard preferences.overlayPosition != mode else {
            return
        }

        preferences.overlayPosition = mode
        persist()
    }

    func updateScreenEdgeHoldKey(_ key: ScreenEdgeHoldKey) {
        guard preferences.screenEdgeHoldKey != key else {
            return
        }

        preferences.screenEdgeHoldKey = key
        persist()
    }

    func setHotKeyModifier(_ modifier: HotKeyModifier, enabled: Bool) {
        var modifiers = preferences.hotKey.modifiers

        if enabled {
            modifiers = HotKeyModifier.normalized(modifiers + [modifier])
        } else {
            modifiers.removeAll { $0 == modifier }

            guard !modifiers.isEmpty else {
                NSSound.beep()
                return
            }

            modifiers = HotKeyModifier.normalized(modifiers)
        }

        preferences.hotKey = HotKeyConfiguration(
            keyCode: preferences.hotKey.keyCode,
            modifiers: modifiers
        )
        persist()
    }

    private func load() {
        let url = configurationFileURL()

        if let data = try? Data(contentsOf: url),
           let document = try? JSONDecoder().decode(AppConfigurationDocument.self, from: data) {
            preferences = document.preferences
            groups = AppGroupConfiguration.normalized(document.groups)

            if document.version != currentDocumentVersion {
                persist()
            }
            return
        }

        preferences = .default
        groups = AppGroupConfiguration.distributed(from: catalogService.defaultConfigurations())
        persist()
    }

    private func persist() {
        let directoryURL = configurationDirectoryURL

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let document = AppConfigurationDocument(
                version: currentDocumentVersion,
                preferences: preferences,
                groups: groups
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: configurationFileURL(), options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    private func configurationFileURL() -> URL {
        configurationDirectoryURL.appendingPathComponent("apps.json")
    }

    private var currentDocumentVersion: String {
        "v1.12.0"
    }

    private func mutateGroup(
        _ direction: RingGroupDirection,
        operation: (inout AppGroupConfiguration) -> Void
    ) {
        guard let index = groups.firstIndex(where: { $0.direction == direction }) else {
            return
        }

        var group = groups[index]
        operation(&group)
        group.items = Array(group.items.prefix(AppGroupConfiguration.maxItemCount))
        group.validate()
        groups[index] = group
    }
}
