struct RingAppGroup: Identifiable {
    let direction: RingGroupDirection
    let apps: [RingApp]

    var id: RingGroupDirection {
        direction
    }
}
