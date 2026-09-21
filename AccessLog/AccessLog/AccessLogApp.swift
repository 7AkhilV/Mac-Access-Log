import SwiftUI

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
    static let openMainWindowIfNeeded = Notification.Name("openMainWindowIfNeeded")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appModel = AppModel()
    private var unlockMonitor: UnlockMonitor?
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        SetupStore.importBundledSeedIfNeeded()
        LoginAutostart.install()

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

        Task {
            guard SetupStore.isComplete else { return }
            await appModel.syncPendingIfPossible()
        }

        scheduleShowRetries()
    }

    /// Login Items start without focus. Keep raising the form until the desktop is ready.
    private func scheduleShowRetries() {
        let delays: [TimeInterval] = [0.3, 1.0, 2.5, 5.0, 10.0, 18.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                if SetupStore.isComplete {
                    if self.appModel.isAwaitingSubmission {
                        self.appModel.bringFormToFront(allowFallback: delay >= 2.5)
                    } else {
                        self.appModel.presentAccessForm()
                    }
                } else {
                    self.appModel.bringFormToFront(allowFallback: delay >= 2.5)
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

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
