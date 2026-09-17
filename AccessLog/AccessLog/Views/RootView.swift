import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
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
            if !SetupStore.isComplete {
                showSetup = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAccessLogSetup)) { _ in
            setupModel.refreshFromDisk()
            showSetup = true
        }
    }
}
