import Foundation
import ServiceManagement

/// Starts Access Log after a reboot.
///
/// `SMAppService` login items often launch hidden. A LaunchAgent that
/// runs `open` is treated more like a user launch and gets a visible window.
enum LoginAutostart {
    static let label = "com.accesslog.autostart"

    static func install() {
        registerLoginItem()
        installLaunchAgent()
    }

    private static func registerLoginItem() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Login item registration: \(error.localizedDescription)")
        }
    }

    private static func installLaunchAgent() {
        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)

        let plistURL = agents.appendingPathComponent("\(label).plist")
        let appPath = Bundle.main.bundleURL.path
        let quoted = appPath.replacingOccurrences(of: "'", with: "'\\''")
        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/bin/zsh",
                "-c",
                "sleep 5; /usr/bin/open '\(quoted)'"
            ],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0) else {
            return
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
