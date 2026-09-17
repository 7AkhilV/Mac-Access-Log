import SwiftUI
import ServiceManagement

@main
struct AccessLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Single window (not WindowGroup) — avoids multiple Access Log windows.
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.collapseExtraWindows()
            guard SetupStore.isComplete else { return }
            self?.appModel.presentAccessForm()
        }

        Task {
            guard SetupStore.isComplete else { return }
            await appModel.syncPendingIfPossible()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if SetupStore.isComplete {
            appModel.presentAccessForm()
        } else {
            appModel.presentAccessForm()
        }
        return true
    }

    /// Keep only one Access Log content window.
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
