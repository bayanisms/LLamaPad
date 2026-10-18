import SwiftUI

@main
struct LlamaPadApp: App {
    @StateObject private var model = ServiceModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.observeRuntime() }
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .background { model.enterBackground() }
                    if newPhase == .active && model.canEdit { model.refreshModels() }
                }
        }
    }
}
