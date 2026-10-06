import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var setupModel = SetupModel()
    @State private var showSetup: Bool = !SetupStore.isComplete
    @State private var showHelp = false

    var body: some View {
        Group {
            if showSetup {
                SetupWizardView(setup: setupModel) {
                    showSetup = false
                    appModel.presentAccessForm()
                }
            } else {
                AccessLogFormView()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 20))
                    .padding(14)
            }
            .buttonStyle(.plain)
            .help("Help & troubleshooting")
        }
        .sheet(isPresented: $showHelp) {
            HelpGuideView { showHelp = false }
        }
        .onAppear {
            SetupStore.importBundledSeedIfNeeded()
            if SetupStore.isComplete {
                // A second window appearing later must not wipe what was typed.
                if appModel.isAwaitingSubmission {
                    appModel.bringFormToFront(allowFallback: true)
                } else {
                    appModel.presentAccessForm()
                }
            } else {
                showSetup = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAccessLogSetup)) { _ in
            setupModel.refreshFromDisk()
            showSetup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindowIfNeeded)) { _ in
            if AppModel.mainContentWindows().isEmpty {
                openWindow(id: "main")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAccessLogHelp)) { _ in
            showHelp = true
        }
    }
}
