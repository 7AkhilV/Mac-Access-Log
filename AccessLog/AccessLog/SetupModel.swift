import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case signIn = 1
        case spreadsheet = 2
        case test = 3
        case done = 4

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .signIn: return "Sign in with Google"
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
    @Published var signedInEmail: String = ""
    @Published var testPassed: Bool = false
    @Published var loginItemOK: Bool = false

    private let syncService = SheetsSyncService()

    init() {
        SetupStore.importBundledSeedIfNeeded()
        refreshFromDisk()
        if GoogleOAuthService.isSignedIn {
            step = SetupStore.hasSpreadsheetId ? .test : .spreadsheet
        }
    }

    func refreshFromDisk() {
        signedInEmail = GoogleOAuthService.signedInEmail ?? ""
        if let config = try? ConfigStore.load() {
            if sheetInput.isEmpty, !config.spreadsheetId.isEmpty {
                sheetInput = config.spreadsheetId
            }
            if !config.sheetName.isEmpty {
                sheetName = config.sheetName
            }
        }
        loginItemOK = SMAppService.mainApp.status == .enabled
    }

    func goNext() {
        statusMessage = nil
        switch step {
        case .welcome:
            step = .signIn
        case .signIn:
            guard GoogleOAuthService.isSignedIn || SetupStore.hasCredentials else {
                statusMessage = "Sign in with Google to continue."
                return
            }
            step = .spreadsheet
        case .spreadsheet:
            saveSpreadsheetConfig()
            guard SetupStore.hasSpreadsheetId else {
                statusMessage = "Create a sheet or paste your Sheet link."
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

    func signInWithGoogle() {
        isBusy = true
        statusMessage = "Browser opening for Google sign-in…"
        Task {
            do {
                let email = try await GoogleOAuthService.shared.signIn()
                signedInEmail = email
                statusMessage = "Signed in as \(email)"
            } catch {
                statusMessage = "Sign-in failed: \(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func signOut() {
        Task {
            await GoogleOAuthService.shared.signOut()
            signedInEmail = ""
            testPassed = false
            SetupStore.resetCompletion()
            statusMessage = "Signed out."
        }
    }

    func createSpreadsheet() {
        isBusy = true
        statusMessage = "Creating Google Sheet…"
        Task {
            do {
                let config = try await syncService.createAccessLogSpreadsheet()
                sheetInput = config.spreadsheetId
                sheetName = config.sheetName
                statusMessage = "Created sheet. ID saved."
                if let url = URL(string: "https://docs.google.com/spreadsheets/d/\(config.spreadsheetId)/edit") {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                statusMessage = "Could not create sheet: \(error.localizedDescription)"
            }
            isBusy = false
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
        LoginAutostart.install()
        loginItemOK = SMAppService.mainApp.status == .enabled
        statusMessage = loginItemOK
            ? "Open at Login enabled."
            : "Login startup installed. Check System Settings → Login Items if needed."
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
