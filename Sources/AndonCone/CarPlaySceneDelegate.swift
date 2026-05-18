#if os(iOS)
import CarPlay
import Combine
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var stationTemplate: CPListTemplate?
    private var cancellables: Set<AnyCancellable> = []

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        PlayerModel.shared.start()

        let template = makeStationTemplate()
        stationTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        observeMetadataChanges()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        cancellables.removeAll()
        stationTemplate = nil
        self.interfaceController = nil
    }

    /// Rebuild list items when metadata refreshes so the CarPlay UI doesn't
    /// stay frozen on whatever was current at scene-connect time.
    private func observeMetadataChanges() {
        let model = PlayerModel.shared
        Publishers.CombineLatest(model.$tracksByID, model.$detailsByID)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refreshStationItems()
            }
            .store(in: &cancellables)
    }

    private func refreshStationItems() {
        stationTemplate?.updateSections([makeStationSection()])
    }

    private func makeStationTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Andon FM", sections: [makeStationSection()])
        template.emptyViewTitleVariants = ["No stations"]
        template.emptyViewSubtitleVariants = ["Open the app once to refresh metadata."]
        return template
    }

    private func makeStationSection() -> CPListSection {
        let items = PlayerModel.stations.map { station -> CPListItem in
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
        return CPListSection(items: items)
    }

    private func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)
    }
}
#endif
