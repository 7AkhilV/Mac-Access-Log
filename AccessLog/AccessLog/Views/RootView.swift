import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var setupModel = SetupModel()
    @State private var showSetup: Bool = !SetupStore.isComplete

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
        .onAppear {
            SetupStore.importBundledSeedIfNeeded()
            if SetupStore.isComplete {
                appModel.presentAccessForm()
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
    }
}
