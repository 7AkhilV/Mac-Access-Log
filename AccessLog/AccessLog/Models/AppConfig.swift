import Foundation

struct AppConfig: Codable {
    var spreadsheetId: String
    var sheetName: String

    static let `default` = AppConfig(
        spreadsheetId: "",
        sheetName: "Access Logs"
    )
}

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AccessLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var databaseURL: URL {
        supportDirectory.appendingPathComponent("access_logs.sqlite")
    }

    static var configURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    static var credentialsURL: URL {
        supportDirectory.appendingPathComponent("credentials.json")
    }
}
