import SwiftUI

@main
struct AndonConeApp: App {
    @StateObject private var model = PlayerModel.shared
    @StateObject private var appChrome = AppChromeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        mainWindow
    }

    private var mainWindow: some Scene {
        WindowGroup {
            RadioAppView()
                .environmentObject(model)
                .environmentObject(appChrome)
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
            AppInfoCommands(appChrome: appChrome)
        }
        #endif
    }

}

@MainActor
final class AppChromeModel: ObservableObject {
    @Published var isShowingAbout = false
}

#if os(macOS)
private struct AppInfoCommands: Commands {
    @ObservedObject var appChrome: AppChromeModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Andon Cone") {
                appChrome.isShowingAbout = true
            }
        }
    }
}

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
