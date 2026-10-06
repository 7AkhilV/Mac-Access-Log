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
                Text("After each Mac unlock you enter Name + Purpose. That row is saved to YOUR Google Sheet.")
                Text("Do this once:")
                    .fontWeight(.medium)
                labeled("1", "Create a Google Sheet (or use one you already have)")
                labeled("2", "First row: ID | Name | Purpose | Date | Time")
                labeled("3", "Share that Sheet as Editor with the service-account email shown next")
                labeled("4", "Paste your Sheet link here and run the connection test")
                Text("You do not sign in with Google. Each Mac keeps its own Sheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

        case .credentials:
            VStack(alignment: .leading, spacing: 12) {
                if !setup.serviceAccountEmail.isEmpty {
                    Text("Service account is already installed. Share YOUR Sheet as Editor with this email:")
                    Text(setup.serviceAccountEmail)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Open the Sheet in a browser → Share → add the email → Editor → Send.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Choose a different credentials.json") {
                        setup.importCredentials()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Choose the service-account JSON so Access Log can write to Sheets without Google sign-in.")
                    Button("Choose credentials.json") {
                        setup.importCredentials()
                    }
                    .keyboardShortcut(.defaultAction)
                    Text("Google Cloud → IAM → Service accounts → Keys → Add JSON key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .spreadsheet:
            VStack(alignment: .leading, spacing: 12) {
                Text("Use the Google Sheet for THIS Mac — not someone else’s.")
                if !setup.serviceAccountEmail.isEmpty {
                    Text("Share that Sheet as Editor with:")
                    Text(setup.serviceAccountEmail)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                Text("Paste Sheet link or ID")
                    .font(.headline)
                TextField("https://docs.google.com/spreadsheets/d/…", text: $setup.sheetInput)
                    .textFieldStyle(.roundedBorder)

                Text("Tab name")
                TextField("Access Logs", text: $setup.sheetName)
                    .textFieldStyle(.roundedBorder)

                if !setup.sheetInput.isEmpty {
                    Button("Open this Sheet") { setup.openSheetIfPossible() }
                }

                Text("First row must be: ID | Name | Purpose | Date | Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .test:
            VStack(alignment: .leading, spacing: 12) {
                Text("This checks that the service account can write to the Sheet you pasted. If it fails, the Sheet is not shared as Editor with the email on the previous step.")
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
