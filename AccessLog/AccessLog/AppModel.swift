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
        for window in NSApp.windows {
            window.level = .floating
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
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
                case .failed(let message):
                    statusMessage = "✓ Saved locally. Sync failed: \(message)"
                    isSuccess = false
                }
            } catch {
                statusMessage = "Could not save locally: \(error.localizedDescription)"
                isSuccess = false
            }

            isSubmitting = false
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
