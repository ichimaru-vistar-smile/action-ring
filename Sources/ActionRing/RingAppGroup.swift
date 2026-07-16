struct RingAppGroup: Identifiable {
    let direction: RingGroupDirection
    let apps: [RingApp]
    let groupedAppIDs: [RingApp.ID]

    var id: RingGroupDirection {
        direction
    }

    var groupedApps: [RingApp] {
        apps.filter { groupedAppIDs.contains($0.id) }
    }
}
