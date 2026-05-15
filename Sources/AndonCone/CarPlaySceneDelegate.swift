#if os(iOS)
import CarPlay
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        PlayerModel.shared.start()
        interfaceController.setRootTemplate(makeStationTemplate(), animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
    }

    private func makeStationTemplate() -> CPListTemplate {
        let items = PlayerModel.stations.map { station in
            let track = PlayerModel.shared.tracksByID[station.id]
            let listeners = PlayerModel.shared.detailsByID[station.id]?.stats?.currentListeners
            let detailText = [
                track?.displayTitle ?? station.host,
                listeners.map { "\($0) listeners" }
            ]
            .compactMap { $0 }
            .joined(separator: " - ")

            let item = CPListItem(text: station.name, detailText: detailText)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    PlayerModel.shared.play(station)
                    self?.showNowPlaying()
                    completion()
                }
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Andon FM", sections: [section])
        template.emptyViewTitleVariants = ["No stations"]
        template.emptyViewSubtitleVariants = ["Open the app once to refresh metadata."]
        return template
    }

    private func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)
    }
}
#endif
