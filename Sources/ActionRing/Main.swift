import AppKit

@MainActor
private let appDelegate = AppDelegate()

@main
enum ActionRingMain {
    @MainActor
    static func main() {
        guard AppInstanceManager.shared.acquirePrimaryInstance() else {
            return
        }

        let application = NSApplication.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
