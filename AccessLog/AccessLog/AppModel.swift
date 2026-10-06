import AppKit
import Combine
import Foundation
import SwiftUI

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
    private var fallbackWindow: NSWindow?

    /// Don't start a brand-new empty form more than once every 2s.
    private let newSessionCooldown: TimeInterval = 2

    static func isMainContentWindow(_ window: NSWindow) -> Bool {
        let name = String(describing: type(of: window))
        if name.contains("NSStatusBar") || name.contains("NSMenu") || name.contains("NSPopup") || name.contains("NSPanel") {
            return false
        }
        if window.title.contains("Access Log") { return true }
        guard window.contentView != nil else { return false }
        return window.frame.width >= 200 || window.frame.height >= 200
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

        bringFormToFront(allowFallback: true)
        startFrontmostGuard()
    }

    /// Raise the existing form without wiping what the user already typed.
    func bringFormToFront(allowFallback: Bool = false) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        activateApp()

        let swiftUIWindows = Self.mainContentWindows().filter { $0 !== fallbackWindow }
        if let window = swiftUIWindows.first {
            reveal(window)
        }

        if swiftUIWindows.contains(where: \.isVisible) {
            fallbackWindow?.orderOut(nil)
            return
        }

        NotificationCenter.default.post(name: .openMainWindowIfNeeded, object: nil)
        if allowFallback {
            showFallbackWindowIfNeeded()
        } else if swiftUIWindows.isEmpty {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func reveal(_ window: NSWindow) {
        window.isRestorable = false
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        configureGateWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func startFrontmostGuard() {
        frontmostTimer?.invalidate()
        frontmostTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isAwaitingSubmission, !self.isSubmitting else { return }
                self.bringFormToFront(allowFallback: true)
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

    /// SwiftUI often skips `Window("main")` when the app was started at login.
    /// This AppKit window does not depend on that scene already existing.
    private func showFallbackWindowIfNeeded() {
        if Self.mainContentWindows().contains(where: { $0 !== fallbackWindow && $0.isVisible }) {
            fallbackWindow?.orderOut(nil)
            return
        }
        if let fallbackWindow {
            reveal(fallbackWindow)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Access Log"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: RootView().environmentObject(self))
        fallbackWindow = window
        reveal(window)
    }

    private func configureGateWindow(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.hidesOnDeactivate = false
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
                    dismissFormSoon(after: 10)
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
