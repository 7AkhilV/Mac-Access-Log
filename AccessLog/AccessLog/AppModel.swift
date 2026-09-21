import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var name: String = ""
    @Published var purpose: String = ""
    @Published var nameError: String?
    @Published var purposeError: String?
    @Published var statusMessage: String?
    @Published var isSuccess: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var isSyncing: Bool = false

    /// True from login/unlock until a successful submit. Used to keep the form in front.
    @Published private(set) var isAwaitingSubmission = false

    private let database = DatabaseService.shared
    private let syncService = SheetsSyncService()
    private var lastNewSessionAt: Date = .distantPast
    private var frontmostTimer: Timer?

    /// Don't start a brand-new empty form more than once every 2s.
    private let newSessionCooldown: TimeInterval = 2

    static func isMainContentWindow(_ window: NSWindow) -> Bool {
        guard window.frame.width >= 280, window.frame.height >= 280 else { return false }
        let name = String(describing: type(of: window))
        if name.contains("NSStatusBar") || name.contains("NSMenu") || name.contains("NSPopup") {
            return false
        }
        return window.contentView != nil
    }

    static func mainContentWindows() -> [NSWindow] {
        NSApp.windows.filter(isMainContentWindow)
    }

    /// New unlock/login session: reset fields and force the form on screen.
    func presentAccessForm() {
        let now = Date()
        if now.timeIntervalSince(lastNewSessionAt) < newSessionCooldown, isAwaitingSubmission {
            bringFormToFront()
            return
        }
        lastNewSessionAt = now

        name = ""
        purpose = ""
        nameError = nil
        purposeError = nil
        statusMessage = nil
        isSuccess = false
        isAwaitingSubmission = true

        bringFormToFront()
        startFrontmostGuard()
    }

    /// Raise the existing form without wiping what the user already typed.
    func bringFormToFront() {
        NSApp.activate(ignoringOtherApps: true)

        let all = Self.mainContentWindows()
        for window in all.dropFirst() {
            window.orderOut(nil)
            window.close()
        }

        let target = Self.mainContentWindows().first ?? NSApp.windows.first
        guard let window = target else { return }

        configureGateWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func startFrontmostGuard() {
        frontmostTimer?.invalidate()
        frontmostTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isAwaitingSubmission, !self.isSubmitting else { return }
                self.bringFormToFront()
            }
        }
        if let frontmostTimer {
            RunLoop.main.add(frontmostTimer, forMode: .common)
        }
    }

    private func stopFrontmostGuard() {
        frontmostTimer?.invalidate()
        frontmostTimer = nil
        isAwaitingSubmission = false
    }

    private func configureGateWindow(_ window: NSWindow) {
        window.level = .modalPanel
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary, .stationary])
        window.isMovable = true

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let width: CGFloat = 620
        let height: CGFloat = 640
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - width / 2
            let y = visible.midY - height / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        } else {
            window.setContentSize(NSSize(width: width, height: height))
            window.center()
        }
    }

    func submit() {
        nameError = nil
        purposeError = nil
        statusMessage = nil
        isSuccess = false

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)

        var valid = true
        if trimmedName.isEmpty {
            nameError = "Please enter your name."
            valid = false
        }
        if trimmedPurpose.isEmpty {
            purposeError = "Please enter the purpose of access."
            valid = false
        }
        guard valid else { return }

        isSubmitting = true
        statusMessage = "Getting accurate time…"

        Task {
            let trusted = await TrustedTimeService.now()

            do {
                _ = try database.insert(
                    name: trimmedName,
                    purpose: trimmedPurpose,
                    createdAt: trusted.date
                )
                name = ""
                purpose = ""

                let result = await syncPendingIfPossible()
                switch result {
                case .synced:
                    if trusted.fromNetwork {
                        statusMessage = "✓ Access recorded successfully (IST)"
                    } else {
                        statusMessage = "✓ Access recorded (device clock — Wi‑Fi time unavailable)"
                    }
                    isSuccess = true
                    dismissFormSoon()
                case .failed(let message):
                    statusMessage = "✓ Saved locally. Sync failed: \(message)"
                    isSuccess = false
                    dismissFormSoon()
                }
            } catch {
                statusMessage = "Could not save locally: \(error.localizedDescription)"
                isSuccess = false
            }

            isSubmitting = false
        }
    }

    /// Hides the form after a short success flash; app stays running for the next unlock.
    private func dismissFormSoon(after delay: TimeInterval = 0.9) {
        stopFrontmostGuard()
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            dismissForm()
        }
    }

    func dismissForm() {
        stopFrontmostGuard()
        for window in Self.mainContentWindows() where window.isVisible {
            window.orderOut(nil)
        }
    }

    enum SyncResult {
        case synced
        case failed(String)
    }

    @discardableResult
    func syncPendingIfPossible() async -> SyncResult {
        guard !isSyncing else { return .failed("Sync already in progress.") }
        isSyncing = true
        defer { isSyncing = false }

        do {
            _ = try await syncService.syncPending()
            return .synced
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
