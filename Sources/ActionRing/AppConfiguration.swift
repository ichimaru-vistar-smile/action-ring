import Foundation

enum RingOverlayPositionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case screenCenter
    case followsMouse

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenCenter:
            "Screen Center"
        case .followsMouse:
            "Follow Mouse"
        }
    }

    var description: String {
        switch self {
        case .screenCenter:
            "Always show the ring in the center of the current screen."
        case .followsMouse:
            "Show the ring around the current pointer position."
        }
    }
}

enum RingGroupDirection: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case up
    case right
    case down
    case left

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .up:
            "Up"
        case .right:
            "Right"
        case .down:
            "Down"
        case .left:
            "Left"
        }
    }

    var symbol: String {
        switch self {
        case .up:
            "↑"
        case .right:
            "→"
        case .down:
            "↓"
        case .left:
            "←"
        }
    }
}

struct AppConfiguration: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var bundleIdentifier: String?
    var name: String
    var path: String

    init(
        id: UUID = UUID(),
        bundleIdentifier: String?,
        name: String,
        path: String
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }
}

enum DirectionDefaultTarget: Codable, Equatable, Hashable, Sendable {
    case app(UUID)
    case group

    private enum TargetType: String, Codable {
        case app
        case group
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case appID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(TargetType.self, forKey: .type) {
        case .app:
            self = .app(try container.decode(UUID.self, forKey: .appID))
        case .group:
            self = .group
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .app(appID):
            try container.encode(TargetType.app, forKey: .type)
            try container.encode(appID, forKey: .appID)
        case .group:
            try container.encode(TargetType.group, forKey: .type)
        }
    }
}

struct AppGroupConfiguration: Codable, Identifiable, Equatable, Sendable {
    static let maxItemCount = 3

    var direction: RingGroupDirection
    var items: [AppConfiguration]
    var groupedAppIDs: [UUID]
    var defaultTarget: DirectionDefaultTarget?

    var id: RingGroupDirection {
        direction
    }

    init(
        direction: RingGroupDirection,
        items: [AppConfiguration] = [],
        groupedAppIDs: [UUID] = [],
        defaultTarget: DirectionDefaultTarget? = nil
    ) {
        self.direction = direction
        self.items = Array(items.prefix(Self.maxItemCount))
        self.groupedAppIDs = Self.validatedGroupIDs(groupedAppIDs, in: self.items)
        self.defaultTarget = Self.validatedDefaultTarget(
            defaultTarget,
            items: self.items,
            groupedAppIDs: self.groupedAppIDs
        )
    }

    static func emptyGroups() -> [AppGroupConfiguration] {
        RingGroupDirection.allCases.map { AppGroupConfiguration(direction: $0) }
    }

    static func distributed(from items: [AppConfiguration]) -> [AppGroupConfiguration] {
        var result = emptyGroups()

        for (index, item) in items.enumerated() {
            let directionIndex = min(index / maxItemCount, RingGroupDirection.allCases.count - 1)
            result[directionIndex].items.append(item)
        }

        return result
    }

    static func normalized(_ groups: [AppGroupConfiguration]) -> [AppGroupConfiguration] {
        RingGroupDirection.allCases.map { direction in
            let group = groups.first(where: { $0.direction == direction })
            return AppGroupConfiguration(
                direction: direction,
                items: group?.items ?? [],
                groupedAppIDs: group?.groupedAppIDs ?? [],
                defaultTarget: group?.defaultTarget
            )
        }
    }

    mutating func validate() {
        groupedAppIDs = Self.validatedGroupIDs(groupedAppIDs, in: items)
        defaultTarget = Self.validatedDefaultTarget(
            defaultTarget,
            items: items,
            groupedAppIDs: groupedAppIDs
        )
    }

    private static func validatedGroupIDs(_ ids: [UUID], in items: [AppConfiguration]) -> [UUID] {
        let selectedIndexes = items.indices.filter { ids.contains(items[$0].id) }
        guard selectedIndexes.count >= 2,
              selectedIndexes.count == ids.count,
              selectedIndexes.last! - selectedIndexes.first! + 1 == selectedIndexes.count else {
            return []
        }

        return selectedIndexes.map { items[$0].id }
    }

    private static func validatedDefaultTarget(
        _ target: DirectionDefaultTarget?,
        items: [AppConfiguration],
        groupedAppIDs: [UUID]
    ) -> DirectionDefaultTarget? {
        switch target {
        case let .app(appID):
            return items.contains(where: { $0.id == appID }) ? target : nil
        case .group:
            return groupedAppIDs.count >= 2 ? target : nil
        case nil:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case items
        case groupedAppIDs
        case defaultTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decode(RingGroupDirection.self, forKey: .direction)
        items = Array(try container.decodeIfPresent([AppConfiguration].self, forKey: .items)?.prefix(Self.maxItemCount) ?? [])
        let decodedGroupIDs = try container.decodeIfPresent([UUID].self, forKey: .groupedAppIDs) ?? []
        groupedAppIDs = Self.validatedGroupIDs(decodedGroupIDs, in: items)
        defaultTarget = Self.validatedDefaultTarget(
            try container.decodeIfPresent(DirectionDefaultTarget.self, forKey: .defaultTarget),
            items: items,
            groupedAppIDs: groupedAppIDs
        )
    }
}

struct AppConfigurationDocument: Codable, Sendable {
    var version: String
    var preferences: ActionRingPreferences
    var groups: [AppGroupConfiguration]

    init(
        version: String,
        preferences: ActionRingPreferences = .default,
        groups: [AppGroupConfiguration]
    ) {
        self.version = version
        self.preferences = preferences
        self.groups = AppGroupConfiguration.normalized(groups)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case preferences
        case groups
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "v1.2.0"
        preferences = try container.decodeIfPresent(ActionRingPreferences.self, forKey: .preferences) ?? .default

        if let groups = try container.decodeIfPresent([AppGroupConfiguration].self, forKey: .groups) {
            self.groups = AppGroupConfiguration.normalized(groups)
        } else {
            let legacyItems = try container.decodeIfPresent([AppConfiguration].self, forKey: .items) ?? []
            groups = AppGroupConfiguration.distributed(from: legacyItems)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(groups, forKey: .groups)
    }
}
