import AppKit
import SwiftUI

struct HelpGuideView: View {
    var onClose: () -> Void

    private var email: String {
        SetupStore.serviceAccountEmail ?? "sheets-form-update@quega-dev.iam.gserviceaccount.com"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Help & troubleshooting")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { onClose() }
            }

            Text("For the app to write to Google Sheets, share YOUR Sheet as Editor with:")
            Text(email)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Copy email") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(email, forType: .string)
                }
                if SetupStore.hasSpreadsheetId {
                    Button("Open my Sheet") {
                        guard let id = try? ConfigStore.load().spreadsheetId,
                              let url = URL(string: "https://docs.google.com/spreadsheets/d/\(id)/edit") else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Divider()

            Text("If you see “Saved locally” or sync failed")
                .font(.headline)
            labeled("1", "Open the Sheet this Mac already uses (not another PC’s Sheet).")
            labeled("2", "Share → add the email above → Editor → Send.")
            labeled("3", "Tab name should match the wizard (usually Access Logs).")
            labeled("4", "First row: ID | Name | Purpose | Date | Time")
            labeled("5", "Check Wi‑Fi, then Access Log → Sync Pending to Google Sheet…")

            Text("You do not sign in with Google. Run Setup Wizard again if you need to change the Sheet link.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 520)
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
