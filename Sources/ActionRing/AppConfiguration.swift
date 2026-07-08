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

enum RingGroupDirection: String, Codable, CaseIterable, Identifiable, Sendable {
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

struct AppGroupConfiguration: Codable, Identifiable, Equatable, Sendable {
    static let maxItemCount = 3

    var direction: RingGroupDirection
    var items: [AppConfiguration]

    var id: RingGroupDirection {
        direction
    }

    init(direction: RingGroupDirection, items: [AppConfiguration] = []) {
        self.direction = direction
        self.items = Array(items.prefix(Self.maxItemCount))
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
            let items = groups.first(where: { $0.direction == direction })?.items ?? []
            return AppGroupConfiguration(direction: direction, items: items)
        }
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
