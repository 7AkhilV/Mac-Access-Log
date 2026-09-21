import SwiftUI
import ServiceManagement

@main
struct AccessLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Access Log", id: "main") {
            RootView()
                .environmentObject(appDelegate.appModel)
                .frame(minWidth: 620, minHeight: 640)
        }
        .defaultSize(width: 620, height: 640)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Run Setup Wizard…") {
                    SetupStore.resetCompletion()
                    NotificationCenter.default.post(name: .showAccessLogSetup, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let showAccessLogSetup = Notification.Name("showAccessLogSetup")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appModel = AppModel()
    private var unlockMonitor: UnlockMonitor?
    private var windowObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var loginRetryWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        SetupStore.importBundledSeedIfNeeded()
        collapseExtraWindows()

        if SetupStore.isComplete {
            registerLoginItemIfNeeded()
        }

        unlockMonitor = UnlockMonitor { [weak self] in
            guard SetupStore.isComplete else { return }
            self?.appModel.presentAccessForm()
        }
        unlockMonitor?.start()

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow,
                  AppModel.isMainContentWindow(window) else { return }
            window.delegate = self
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, SetupStore.isComplete, self.appModel.isAwaitingSubmission else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.appModel.bringFormToFront()
            }
        }

        scheduleLoginRetries()

        Task {
            guard SetupStore.isComplete else { return }
            await appModel.syncPendingIfPossible()
        }
    }

    /// Login Items often start without focus. Keep forcing the form forward for a while after boot.
    private func scheduleLoginRetries() {
        loginRetryWork?.cancel()
        let delays: [TimeInterval] = [0.3, 1.0, 2.5, 5.0, 8.0, 12.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, SetupStore.isComplete else { return }
                self.collapseExtraWindows()
                if self.appModel.isAwaitingSubmission {
                    self.appModel.bringFormToFront()
                } else {
                    self.appModel.presentAccessForm()
                }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if appModel.isAwaitingSubmission {
            appModel.bringFormToFront()
        } else {
            sender.orderOut(nil)
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if appModel.isAwaitingSubmission {
            appModel.bringFormToFront()
        } else {
            appModel.presentAccessForm()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if SetupStore.isComplete, appModel.isAwaitingSubmission {
            appModel.bringFormToFront()
        }
    }

    private func collapseExtraWindows() {
        let windows = AppModel.mainContentWindows()
        guard windows.count > 1 else { return }
        for window in windows.dropFirst() {
            window.orderOut(nil)
            window.close()
        }
    }

    private func registerLoginItemIfNeeded() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Login item registration: \(error.localizedDescription)")
        }
    }
}
