import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case credentials = 1
        case spreadsheet = 2
        case test = 3
        case done = 4

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .credentials: return "Service account"
            case .spreadsheet: return "Your spreadsheet"
            case .test: return "Test connection"
            case .done: return "Done"
            }
        }
    }

    @Published var step: Step = .welcome
    @Published var sheetInput: String = ""
    @Published var sheetName: String = "Access Logs"
    @Published var statusMessage: String?
    @Published var isBusy: Bool = false
    @Published var serviceAccountEmail: String = ""
    @Published var testPassed: Bool = false
    @Published var loginItemOK: Bool = false

    private let syncService = SheetsSyncService()

    init() {
        SetupStore.importBundledSeedIfNeeded()
        refreshFromDisk()
    }

    func refreshFromDisk() {
        serviceAccountEmail = SetupStore.serviceAccountEmail ?? ""
        if let config = try? ConfigStore.load() {
            if sheetInput.isEmpty, !config.spreadsheetId.isEmpty {
                sheetInput = config.spreadsheetId
            }
            if !config.sheetName.isEmpty {
                sheetName = config.sheetName
            }
        }
        loginItemOK = LoginAutostart.isInstalled
    }

    func goNext() {
        statusMessage = nil
        switch step {
        case .welcome:
            step = .credentials
        case .credentials:
            guard SetupStore.hasCredentials else {
                statusMessage = "Choose a service-account JSON to continue."
                return
            }
            step = .spreadsheet
        case .spreadsheet:
            saveSpreadsheetConfig()
            guard SetupStore.hasSpreadsheetId else {
                statusMessage = "Paste your Sheet link to continue."
                return
            }
            step = .test
        case .test:
            guard testPassed else {
                statusMessage = "Run the connection test successfully before continuing."
                return
            }
            finishSetup()
            step = .done
        case .done:
            break
        }
    }

    func goBack() {
        statusMessage = nil
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
        }
    }

    func importCredentials() {
        let panel = NSOpenPanel()
        panel.title = "Choose service-account JSON"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "service_account",
                  let email = json["client_email"] as? String,
                  !email.isEmpty else {
                statusMessage = "That file is not a Google service-account JSON."
                return
            }
            if FileManager.default.fileExists(atPath: AppPaths.credentialsURL.path) {
                try FileManager.default.removeItem(at: AppPaths.credentialsURL)
            }
            try data.write(to: AppPaths.credentialsURL, options: .atomic)
            serviceAccountEmail = email
            testPassed = false
            statusMessage = "Saved service account \(email)"
        } catch {
            statusMessage = "Could not save credentials: \(error.localizedDescription)"
        }
    }

    func saveSpreadsheetConfig() {
        let id = SetupStore.spreadsheetId(from: sheetInput)
        guard !id.isEmpty else { return }
        var config = (try? ConfigStore.load()) ?? .default
        config.spreadsheetId = id
        config.sheetName = sheetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Access Logs"
            : sheetName.trimmingCharacters(in: .whitespacesAndNewlines)
        try? ConfigStore.save(config)
        sheetInput = id
    }

    func openSheetIfPossible() {
        let id = SetupStore.spreadsheetId(from: sheetInput)
        guard !id.isEmpty,
              let url = URL(string: "https://docs.google.com/spreadsheets/d/\(id)/edit") else { return }
        NSWorkspace.shared.open(url)
    }

    func registerLoginItem() {
        loginItemOK = LoginAutostart.install()
        statusMessage = loginItemOK
            ? "Opens automatically at login."
            : "Could not install login startup. Open the app once, then check System Settings → Login Items."
    }

    func runConnectionTest() {
        saveSpreadsheetConfig()
        isBusy = true
        statusMessage = "Testing Google Sheets connection…"
        testPassed = false

        Task {
            do {
                let message = try await syncService.testConnection()
                testPassed = true
                statusMessage = message
                registerLoginItem()
            } catch {
                testPassed = false
                statusMessage = "Test failed: \(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func finishSetup() {
        saveSpreadsheetConfig()
        registerLoginItem()
        SetupStore.markComplete()
    }
}
