import AppKit
import Foundation

/// Observes macOS screen unlock and session activation so the access form can be shown.
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

        // Undocumented but widely used unlock signal
        let unlocked = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onUnlock()
        }

        let sessionActive = NotificationCenter.default.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onUnlock()
        }

        observers = [unlocked, sessionActive]
    }

    func stop() {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
