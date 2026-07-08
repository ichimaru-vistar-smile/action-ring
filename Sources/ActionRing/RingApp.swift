import AppKit

struct RingApp: Identifiable {
    let id: UUID
    let bundleIdentifier: String?
    let name: String
    let url: URL
    let icon: NSImage
}
