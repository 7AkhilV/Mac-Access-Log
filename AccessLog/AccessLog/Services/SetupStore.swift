import Foundation

enum SetupStore {
    private static let completedKey = "accessLog.setupCompleted"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: completedKey) && isSignedIn && hasSpreadsheetId
    }

    static var isSignedIn: Bool {
        GoogleOAuthService.isSignedIn || hasCredentials
    }

    static var hasCredentials: Bool {
        FileManager.default.fileExists(atPath: AppPaths.credentialsURL.path)
    }

    static var hasSpreadsheetId: Bool {
        guard let id = try? ConfigStore.load().spreadsheetId else { return false }
        return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    static func resetCompletion() {
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    static func importBundledSeedIfNeeded() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let seedDir = resourceURL.appendingPathComponent("Seed", isDirectory: true)

        let bundledCredentials = seedDir.appendingPathComponent("credentials.json")
        if !hasCredentials, FileManager.default.fileExists(atPath: bundledCredentials.path) {
            try? FileManager.default.copyItem(at: bundledCredentials, to: AppPaths.credentialsURL)
        }

        let bundledConfig = seedDir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: bundledConfig.path), !hasSpreadsheetId {
            try? FileManager.default.copyItem(at: bundledConfig, to: AppPaths.configURL)
        }
    }

    static func spreadsheetId(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "/d/") {
            let after = trimmed[range.upperBound...]
            if let end = after.firstIndex(of: "/") {
                return String(after[..<end])
            }
            return String(after)
        }
        return trimmed
    }
}
