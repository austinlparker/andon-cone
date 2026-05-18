#if os(iOS)
import EmbraceIO
#endif
import Foundation
import SwiftUI

@main
struct AndonConeApp: App {
    @StateObject private var model = PlayerModel.shared
    @StateObject private var appChrome = AppChromeModel()
    @StateObject private var artworkCache = ArtworkCache()
    @StateObject private var metadata = MusicMetadataClient()
    @StateObject private var library = MusicLibraryService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        configureCrashReporting()
    }

    var body: some Scene {
        mainWindow
    }

    private var mainWindow: some Scene {
        WindowGroup {
            RadioAppView()
                .environmentObject(model)
                .environmentObject(appChrome)
                .environmentObject(artworkCache)
                .environmentObject(metadata)
                .environmentObject(library)
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

private func configureCrashReporting() {
    #if os(iOS)
    let options = Embrace.Options(appId: "7fxwh")

    do {
        try Embrace.setup(options: options).start()
    } catch {
        NSLog("Andon Cone Embrace setup failed: %@", error.localizedDescription)
    }
    #endif
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
    // ObservedObject so button labels (Play/Pause, Mute/Unmute, disabled state)
    // refresh as model state changes.
    @ObservedObject var model: PlayerModel

    var body: some Commands {
        CommandMenu("Player") {
            Button(model.isPlaying ? "Pause" : "Play") {
                model.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button(model.isMuted ? "Unmute" : "Mute") {
                model.toggleMute()
            }
            .keyboardShortcut("m", modifiers: .command)

            Button("Reconnect Stream") {
                model.reconnect()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.isPlaying)

            Divider()

            Button("Next Station") {
                model.nextStation()
            }
            .keyboardShortcut("]", modifiers: [.command, .option])

            Button("Previous Station") {
                model.previousStation()
            }
            .keyboardShortcut("[", modifiers: [.command, .option])
        }
    }
}
#endif
