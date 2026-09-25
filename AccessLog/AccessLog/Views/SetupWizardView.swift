import SwiftUI
import AppKit

struct SetupWizardView: View {
    @ObservedObject var setup: SetupModel
    var onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let status = setup.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(setup.testPassed && setup.step == .test ? Color.green : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(24)
        .frame(width: 620, height: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Access Log Setup")
                .font(.system(size: 22, weight: .semibold))
            Text("Step \(setup.step.rawValue + 1) of \(SetupModel.Step.allCases.count): \(setup.step.title)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(setup.step.rawValue + 1), total: Double(SetupModel.Step.allCases.count))
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch setup.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 10) {
                Text("After Mac login/unlock, Access Log asks for Name + Purpose and syncs to your Google Sheet.")
                Text("You’ll:")
                    .fontWeight(.medium)
                labeled("1", SetupStore.hasCredentials
                    ? "Use the bundled service account (does not expire)"
                    : "Sign in with your Google account")
                labeled("2", "Create a new Sheet (or paste an existing Sheet link)")
                labeled("3", "Run a quick connection test")
            }

        case .signIn:
            VStack(alignment: .leading, spacing: 12) {
                if SetupStore.hasCredentials {
                    Label("Using the company service account. This login does not expire.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Google sign-in is optional. The service account writes to the shared Sheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sign in so Access Log can write to your spreadsheet only.")
                    if setup.signedInEmail.isEmpty {
                        Button(setup.isBusy ? "Waiting for Google…" : "Sign in with Google") {
                            setup.signInWithGoogle()
                        }
                        .disabled(setup.isBusy)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Label("Signed in as \(setup.signedInEmail)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Sign out") { setup.signOut() }
                            .disabled(setup.isBusy)
                    }
                    Text("A browser window will open. Approve Sheets access, then return here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .spreadsheet:
            VStack(alignment: .leading, spacing: 12) {
                Text("Use your own Google Sheet.")

                Button(setup.isBusy ? "Creating…" : "Create a new Access Log sheet") {
                    setup.createSpreadsheet()
                }
                .disabled(setup.isBusy)

                Text("Or paste an existing Sheet link / ID:")
                TextField("https://docs.google.com/spreadsheets/d/…", text: $setup.sheetInput)
                    .textFieldStyle(.roundedBorder)

                Text("Tab name")
                TextField("Access Logs", text: $setup.sheetName)
                    .textFieldStyle(.roundedBorder)

                if !setup.sheetInput.isEmpty {
                    Button("Open Sheet") { setup.openSheetIfPossible() }
                }

                Text("Existing sheets should have headers: ID | Name | Purpose | Date | Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .test:
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirms Google access and enables Open at Login.")
                Button(setup.isBusy ? "Testing…" : "Run connection test") {
                    setup.runConnectionTest()
                }
                .disabled(setup.isBusy)
                .keyboardShortcut(.defaultAction)

                if setup.testPassed {
                    Label("Connection OK", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if setup.loginItemOK {
                    Label("Open at Login enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

        case .done:
            VStack(alignment: .leading, spacing: 12) {
                Label("You’re ready", systemImage: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Text("Keep Access Log running. It opens after each Mac unlock.")
                Text("Closing the window hides it; Quit only when you want to stop.")
                    .foregroundStyle(.secondary)
                Button("Start using Access Log") { onFinished() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var footer: some View {
        HStack {
            if setup.step != .welcome && setup.step != .done {
                Button("Back") { setup.goBack() }
            }
            Spacer()
            if setup.step != .done {
                Button(setup.step == .test ? "Finish" : "Continue") {
                    setup.goNext()
                }
                .disabled(setup.isBusy)
            }
        }
    }

    private func labeled(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number + ".")
                .fontWeight(.semibold)
                .frame(width: 18, alignment: .trailing)
            Text(text)
        }
    }
}
