#if os(iOS)
import CarPlay
import Combine
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var stationTemplate: CPListTemplate?
    private let library = MusicLibraryService()
    private var cancellables: Set<AnyCancellable> = []
    private var isConnected = false
    private var nowPlayingButtons: [CPNowPlayingButton] = []

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        connect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        connect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        disconnect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        disconnect(interfaceController)
    }

    private func connect(_ interfaceController: CPInterfaceController) {
        isConnected = true
        self.interfaceController = interfaceController
        PlayerModel.shared.start()

        let template = makeStationTemplate()
        stationTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        configureNowPlayingTemplate()
        observeMetadataChanges()
    }

    private func disconnect(_ interfaceController: CPInterfaceController) {
        isConnected = false
        cancellables.removeAll()
        updateNowPlayingButtons([])
        stationTemplate = nil
        self.interfaceController = nil
    }

    /// Rebuild list items when metadata refreshes so the CarPlay UI doesn't
    /// stay frozen on whatever was current at scene-connect time.
    private func observeMetadataChanges() {
        let model = PlayerModel.shared
        Publishers.CombineLatest3(model.$tracksByID, model.$detailsByID, library.$statuses)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refreshStationItems()
                self?.configureNowPlayingTemplate()
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
        configureNowPlayingTemplate()
        interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)
    }

    private func configureNowPlayingTemplate() {
        guard isConnected else { return }

        let nowPlaying = CPNowPlayingTemplate.shared

        if #available(iOS 18.4, *) {
            nowPlaying.nowPlayingMode = .default
        }

        guard let trackID = currentAppleMusicTrackID else {
            updateNowPlayingButtons([])
            return
        }

        if library.status(for: trackID) == .unknown {
            library.refreshStatus(for: trackID)
        }

        let status = library.status(for: trackID)
        let addButton = CPNowPlayingAddToLibraryButton { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isConnected else { return }
                self.library.addToLibrary(trackID: trackID)
                self.configureNowPlayingTemplate()
            }
        }
        addButton.isSelected = status == .inLibrary
        addButton.isEnabled = status != .inLibrary && status != .adding && status != .checking

        updateNowPlayingButtons([addButton])
    }

    private func updateNowPlayingButtons(_ buttons: [CPNowPlayingButton]) {
        nowPlayingButtons = buttons
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(nowPlayingButtons)
    }

    private var currentAppleMusicTrackID: String? {
        guard
            let track = PlayerModel.shared.currentTrack,
            let enriched = MusicMetadataClient.shared.enriched(for: track)
        else {
            return nil
        }

        return enriched.trackID
    }
}
#endif
