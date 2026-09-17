import SwiftUI
import AppKit

struct AccessLogFormView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case purpose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Access Log")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.headline)
                TextField("", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .purpose }

                if let nameError = model.nameError {
                    Text(nameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Purpose")
                    .font(.headline)
                TextEditor(text: $model.purpose)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .focused($focusedField, equals: .purpose)

                if let purposeError = model.purposeError {
                    Text(purposeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Submit") {
                    model.submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSubmitting)
                Spacer()
            }

            if let status = model.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(model.isSuccess ? Color.green : Color.red)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 16) {
                Button("Open config folder") {
                    NSWorkspace.shared.open(AppPaths.supportDirectory)
                }
                .buttonStyle(.plain)

                Button("Setup…") {
                    SetupStore.resetCompletion()
                    NotificationCenter.default.post(name: .showAccessLogSetup, object: nil)
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(28)
        .frame(width: 380)
        .onAppear {
            focusedField = .name
        }
    }
}
