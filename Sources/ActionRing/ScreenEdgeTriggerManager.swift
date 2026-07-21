import AppKit
import CoreGraphics
import OSLog

@MainActor
final class ScreenEdgeTriggerManager: NSObject {
    var onTrigger: ((RingGroupDirection) -> Void)?

    private let pollingInterval: TimeInterval = 0.04
    private let edgeThreshold: CGFloat = 2.5
    private nonisolated static let logger = Logger(
        subsystem: "app.action-ring.desktop",
        category: "ScreenEdge"
    )

    private var timer: Timer?
    private var holdKey: ScreenEdgeHoldKey = .control
    private var isEnabled = false
    private var triggeredDirections = Set<RingGroupDirection>()

    func configure(holdKey: ScreenEdgeHoldKey, isEnabled: Bool) {
        let keyChanged = self.holdKey != holdKey
        self.holdKey = holdKey
        self.isEnabled = isEnabled

        if keyChanged || !isEnabled {
            triggeredDirections.removeAll()
        }

        if isEnabled {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    private func startPollingIfNeeded() {
        guard timer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: pollingInterval,
            target: self,
            selector: #selector(pollPointerAndKeyboard),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func pollPointerAndKeyboard() {
        guard isEnabled, isHoldKeyPressed else {
            triggeredDirections.removeAll()
            return
        }

        guard let direction = edgeDirection(at: NSEvent.mouseLocation),
              !triggeredDirections.contains(direction) else {
            return
        }

        triggeredDirections.insert(direction)
        Self.logger.notice("Screen edge action triggered: \(direction.rawValue, privacy: .public)")
        onTrigger?(direction)
    }

    private var isHoldKeyPressed: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(eventFlag(for: holdKey))
    }

    private func eventFlag(for key: ScreenEdgeHoldKey) -> CGEventFlags {
        switch key {
        case .control:
            .maskControl
        case .option:
            .maskAlternate
        case .command:
            .maskCommand
        case .shift:
            .maskShift
        }
    }

    private func edgeDirection(at point: NSPoint) -> RingGroupDirection? {
        guard let screen = screen(containing: point) else {
            return nil
        }

        let frame = screen.frame
        let candidates: [(direction: RingGroupDirection, distance: CGFloat)] = [
            (.up, abs(frame.maxY - point.y)),
            (.right, abs(frame.maxX - point.x)),
            (.down, abs(point.y - frame.minY)),
            (.left, abs(point.x - frame.minX))
        ]
        .filter { $0.distance <= edgeThreshold }
        .sorted { $0.distance < $1.distance }

        guard let closest = candidates.first else {
            return nil
        }

        // At an exact corner there is no unambiguous direction. Waiting until
        // the pointer moves slightly along one edge avoids launching two targets.
        if candidates.count > 1,
           abs(candidates[1].distance - closest.distance) < 0.5 {
            return nil
        }

        return closest.direction
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.insetBy(dx: -edgeThreshold, dy: -edgeThreshold).contains(point)
        }
    }
}
