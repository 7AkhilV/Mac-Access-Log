import AppKit
import Foundation

/// Observes unlock, wake, and session-active so the access form can be shown.
final class UnlockMonitor {
    private let onUnlock: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let dnc = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter

        let unlocked = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onUnlock()
        }

        let sessionActive = workspace.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onUnlock()
        }

        let wake = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onUnlock()
        }

        let screensWake = workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onUnlock()
        }

        observers = [unlocked, sessionActive, wake, screensWake]
    }

    func stop() {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}
