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
        VStack(spacing: 0) {
            // Gate header
            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(red: 0.06, green: 0.46, blue: 0.43))

                Text("Access Log Required")
                    .font(.system(size: 28, weight: .bold))

                Text("Please record who you are and why you are using this Mac before continuing.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .padding(.top, 36)
            .padding(.horizontal, 40)
            .padding(.bottom, 28)

            Divider()

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.system(size: 15, weight: .semibold))
                    TextField("Your full name", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 16))
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .purpose }

                    if let nameError = model.nameError {
                        Text(nameError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Purpose of access")
                        .font(.system(size: 15, weight: .semibold))
                    TextEditor(text: $model.purpose)
                        .font(.system(size: 16))
                        .frame(minHeight: 140)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
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

                Button {
                    model.submit()
                } label: {
                    Text(model.isSubmitting ? "Submitting…" : "Submit & Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.06, green: 0.46, blue: 0.43))
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSubmitting)
                .padding(.top, 4)

                if let status = model.statusMessage {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(model.isSuccess ? Color.green : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(40)

            Spacer(minLength: 0)

            HStack(spacing: 20) {
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
            .foregroundStyle(.tertiary)
            .padding(.bottom, 20)
        }
        .frame(width: 620, height: 640)
        .onAppear {
            focusedField = .name
        }
    }
}
