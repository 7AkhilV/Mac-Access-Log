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

    private let database = DatabaseService.shared
    private let syncService = SheetsSyncService()
    private var lastPresentedAt: Date = .distantPast

    /// Avoid hammering the form if multiple unlock notifications fire close together.
    private let presentCooldown: TimeInterval = 2

    static func isMainContentWindow(_ window: NSWindow) -> Bool {
        // Ignore menu / status / helper chrome; only real content panels.
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

    func presentAccessForm() {
        let now = Date()
        guard now.timeIntervalSince(lastPresentedAt) >= presentCooldown else { return }
        lastPresentedAt = now

        name = ""
        purpose = ""
        nameError = nil
        purposeError = nil
        statusMessage = nil
        isSuccess = false

        NSApp.activate(ignoringOtherApps: true)

        // Drop accidental duplicate windows first.
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

    private func configureGateWindow(_ window: NSWindow) {
        window.level = .modalPanel
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        window.isMovable = false

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let width: CGFloat = 620
        let height: CGFloat = 640
        window.setContentSize(NSSize(width: width, height: height))
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - width / 2
            let y = visible.midY - height / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        } else {
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
                    // Still saved locally — close so unlock flow isn't blocked.
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
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            dismissForm()
        }
    }

    func dismissForm() {
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
