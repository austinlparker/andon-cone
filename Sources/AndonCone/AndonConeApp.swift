import SwiftUI

@main
struct AndonConeApp: App {
    @StateObject private var model = PlayerModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        mainWindow
    }

    private var mainWindow: some Scene {
        WindowGroup {
            RadioAppView()
                .environmentObject(model)
                .task {
                    model.start()
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        model.refreshAllMetadata()
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 680)
        .commands {
            PlayerCommands(model: model)
        }
        #endif
    }

}

#if os(macOS)
private struct PlayerCommands: Commands {
    let model: PlayerModel

    var body: some Commands {
        CommandMenu("Player") {
            Button(model.isPlaying ? "Pause" : "Play") {
                model.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
        }
    }
}
#endif
