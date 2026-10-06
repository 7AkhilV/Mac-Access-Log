import AppKit
import Foundation
import ServiceManagement

/// Starts Access Log after login with a visible window.
///
/// `SMAppService` login items are launched in the background. The Dock icon
/// appears, but macOS will not show the window until the icon is clicked.
/// A LaunchAgent that runs `open` is a normal foreground launch, so the
/// window is allowed on screen.
enum LoginAutostart {
    static let label = "com.accesslog.autostart"
    static let foregroundArg = "--accesslog-foreground"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static var isForegroundLaunch: Bool {
        CommandLine.arguments.contains(foregroundArg)
    }

    /// Background login-item launches cannot present UI. Hand off to `open`.
    static var needsForegroundRelaunch: Bool {
        if isForegroundLaunch { return false }
        if CommandLine.arguments.contains("-NSDocumentRevisionsDebugMode") { return false }
        if launchedAsLoginItem { return true }
        return !NSApp.isActive
    }

    @discardableResult
    static func install() -> Bool {
        unregisterLoginItem()
        return installLaunchAgent()
    }

    /// Quits this process after a detached `open`, so the new process is a
    /// normal foreground launch and macOS will show its window.
    static func relaunchInForeground() -> Bool {
        let quoted = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "sleep 0.6; /usr/bin/open '\(quoted)' --args \(foregroundArg)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/zsh", "-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            print("Foreground relaunch failed: \(error.localizedDescription)")
            return false
        }
    }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    /// Classic login-item Apple Event. `SMAppService` does not always set this.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        guard event.eventID == AEEventID(0x6F617070) else { return false } // 'oapp'
        guard let prop = event.paramDescriptor(forKeyword: AEKeyword(0x70726474)) else { return false } // 'prdt'
        let code = prop.enumCodeValue
        return code == OSType(0x6C676974) || code == OSType(0x73766974) // 'lgit' / 'svit'
    }

    private static func unregisterLoginItem() {
        guard SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
    }

    @discardableResult
    private static func installLaunchAgent() -> Bool {
        let agents = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)

        let quoted = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        // Wait until the Dock exists so `open` lands in the graphical session.
        let script = """
        for _ in {1..40}; do
          if /usr/bin/pgrep -x Dock >/dev/null 2>&1; then
            sleep 2
            break
          fi
          sleep 1
        done
        /usr/bin/open '\(quoted)' --args \(foregroundArg)
        """
        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/bin/zsh",
                "-c",
                script
            ],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0) else {
            return false
        }

        let previous = try? Data(contentsOf: plistURL)
        let changed = previous != data
        if changed {
            try? data.write(to: plistURL, options: .atomic)
        }

        let uid = getuid()
        let domain = "gui/\(uid)/\(label)"
        if changed && isLoaded(domain) {
            runLaunchctl(["bootout", domain])
        }
        if !isLoaded(domain) {
            runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        }
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    private static func isLoaded(_ domain: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", domain]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
