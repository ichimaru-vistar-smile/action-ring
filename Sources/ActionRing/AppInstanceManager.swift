import AppKit
import Darwin
import Foundation

@MainActor
final class AppInstanceManager {
    static let shared = AppInstanceManager()

    private var lockFileDescriptor: Int32 = -1

    private init() {}

    func acquirePrimaryInstance() -> Bool {
        guard lockFileDescriptor == -1 else {
            return true
        }

        let lockURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("action-ring.lock", isDirectory: false)

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor != -1 else {
            return true
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            lockFileDescriptor = descriptor
            return true
        }

        close(descriptor)
        activateExistingInstance()
        return false
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            NSSound.beep()
            return
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        runningApps
            .first(where: { $0.processIdentifier != currentProcessID })?
            .activate(options: [.activateAllWindows])
    }

    deinit {
        if lockFileDescriptor != -1 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
        }
    }
}
