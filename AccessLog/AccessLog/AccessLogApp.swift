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
                Button("Sync Pending to Google Sheet…") {
                    Task {
                        await appDelegate.syncPendingFromMenu()
                    }
                }
                Button("Run Setup Wizard…") {
                    SetupStore.resetCompletion()
                    NotificationCenter.default.post(name: .showAccessLogSetup, object: nil)
                }
                Button("Help & Troubleshooting…") {
                    NotificationCenter.default.post(name: .showAccessLogHelp, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let showAccessLogSetup = Notification.Name("showAccessLogSetup")
    static let showAccessLogHelp = Notification.Name("showAccessLogHelp")
    static let openMainWindowIfNeeded = Notification.Name("openMainWindowIfNeeded")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appModel = AppModel()
    private var unlockMonitor: UnlockMonitor?
    private var windowObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must happen before SwiftUI decides whether to create the window.
        // Login-item launches skip the window if this is still the default.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        SetupStore.importBundledSeedIfNeeded()
        LoginAutostart.install()

        // A login item can sit in the Dock with no window. Replace that
        // process with one started by `open`, which is allowed to show UI.
        if LoginAutostart.needsForegroundRelaunch, LoginAutostart.relaunchInForeground() {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
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

        Task {
            guard SetupStore.isComplete else { return }
            await appModel.syncPendingIfPossible()
        }

        showLaunchUI()
        scheduleShowRetries()
    }

    /// Keep raising the window until the desktop is ready. Do not start a
    /// second form after the user has already submitted this launch.
    private var didAutoPresent = false

    private func showLaunchUI() {
        if SetupStore.isComplete {
            if !didAutoPresent {
                didAutoPresent = true
                if appModel.isAwaitingSubmission {
                    appModel.bringFormToFront(allowFallback: true)
                } else {
                    appModel.presentAccessForm()
                }
            } else if appModel.isAwaitingSubmission {
                appModel.bringFormToFront(allowFallback: true)
            }
        } else {
            appModel.bringFormToFront(allowFallback: true)
        }
    }

    private func scheduleShowRetries() {
        let delays: [TimeInterval] = [0.3, 1.0, 2.5, 5.0, 10.0, 18.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showLaunchUI()
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
            appModel.bringFormToFront(allowFallback: true)
        } else {
            appModel.presentAccessForm()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard SetupStore.isComplete else {
            appModel.bringFormToFront(allowFallback: true)
            return
        }
        if appModel.isAwaitingSubmission || !didAutoPresent {
            showLaunchUI()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func syncPendingFromMenu() async {
        appModel.bringFormToFront()
        appModel.statusMessage = "Syncing pending rows…"
        let result = await appModel.syncPendingIfPossible()
        switch result {
        case .synced:
            appModel.statusMessage = "✓ Pending rows sent to Google Sheet."
            appModel.isSuccess = true
        case .failed(let message):
            appModel.statusMessage = "Sync failed: \(message)"
            appModel.isSuccess = false
        }
    }
}
