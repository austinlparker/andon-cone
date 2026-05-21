import SwiftUI

struct RadioAppView: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var appChrome: AppChromeModel
    @EnvironmentObject private var artworkCache: ArtworkCache
    @EnvironmentObject private var metadata: MusicMetadataClient
    @EnvironmentObject private var library: MusicLibraryService
    @StateObject private var tipStore = TipStore()
    @State private var selectedTab: DetailTab = .schedule
    @State private var selectedStationID: Station.ID? = PlayerModel.stations[0].id
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            StationSourceList(
                selectedStationID: $selectedStationID,
                onSelectStation: collapseSidebarAfterSelection
            )
                .navigationSplitViewColumnWidth(min: 230, ideal: 276, max: 330)
        } detail: {
            StationDetailView(
                tabPicker: { tabPicker },
                tabContent: { tabContent }
            )
            .navigationTitle(model.currentStation.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 980, minHeight: 520, idealHeight: 680)
        #endif
        .sheet(isPresented: $appChrome.isShowingAbout) {
            AboutView(store: tipStore)
        }
        .task {
            await tipStore.loadProducts()
        }
        .onChange(of: model.currentStation.id) { stationID in
            selectedStationID = stationID
        }
        .onChange(of: model.detailsByID) { details in
            // Prefetch every station's artwork as soon as we know the URLs so switching
            // stations becomes an instant memory-cache hit, no network round trip.
            for detail in details.values {
                if let url = detail.imageURL {
                    artworkCache.prefetch(url)
                }
            }
        }
        .onChange(of: model.tracksByID) { tracks in
            // Enrich every station's track in the background so a station switch shows
            // album art / metadata immediately. Lookups dedupe internally.
            for track in tracks.values {
                metadata.enrich(track)
            }
        }
        .onChange(of: metadata.version) { _ in
            // Whenever an enriched track lands, kick the artwork cache so the high-res
            // album art is hot by the time the view next reads it.
            for track in model.tracksByID.values {
                if let enriched = metadata.enriched(for: track), let url = enriched.artworkURL {
                    artworkCache.prefetch(url)
                }
            }
        }
        .alert("Apple Music", isPresented: Binding(
            get: { library.pendingMessage != nil },
            set: { if !$0 { library.dismissMessage() } }
        ), actions: {
            Button("OK", role: .cancel) { library.dismissMessage() }
        }, message: {
            Text(library.pendingMessage ?? "")
        })
        #if os(iOS)
        .onAppear {
            // Land on Now Playing in compact mode so the listener-facing surface is the first thing
            // a user sees. The navigation bar provides a sidebar toggle to reach the station list.
            if horizontalSizeClass == .compact {
                columnVisibility = .detailOnly
            }
        }
        #endif
    }

    private var tabPicker: some View {
        GlassSegmentedPicker(selection: $selectedTab)
    }

    private func collapseSidebarAfterSelection() {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            columnVisibility = .detailOnly
        }
        #endif
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .schedule:
            SchedulePanel()
        case .topTracks:
            TopTracksPanel()
        case .buzz:
            BuzzPanel()
        }
    }
}

private struct StationDetailView<TabPicker: View, TabContent: View>: View {
    @EnvironmentObject private var model: PlayerModel
    let tabPicker: () -> TabPicker
    let tabContent: () -> TabContent

    var body: some View {
        let backdrop = StationTintBackdrop(
            accent: model.currentStation.accentColor,
            imageURL: model.currentDetail?.imageURL
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(macOS)
                MacNowPlayingHero()
                #else
                NowPlayingPanel()
                #endif
                Divider()
                tabPicker()
                tabContent()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backdrop.ignoresSafeArea())
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }
}
