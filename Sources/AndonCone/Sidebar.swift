import SwiftUI

struct StationSourceList: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var appChrome: AppChromeModel
    @Environment(\.openURL) private var openURL
    @Binding var selectedStationID: Station.ID?
    let onSelectStation: () -> Void

    private var selection: Binding<Station.ID?> {
        Binding(
            get: { selectedStationID },
            set: { stationID in
                selectedStationID = stationID

                if let stationID, let station = model.station(id: stationID) {
                    model.selectStation(station)
                    onSelectStation()
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                ForEach(PlayerModel.stations) { station in
                    NavigationLink(value: station.id) {
                        StationSourceRow(
                            station: station,
                            detail: model.detailsByID[station.id],
                            track: model.tracksByID[station.id]
                        )
                    }
                }
            }

            #if os(iOS)
            // macOS reaches About through the application menu, so we don't duplicate
            // it (or the radio page link) into the sidebar.
            Section("App") {
                Button {
                    appChrome.isShowingAbout = true
                } label: {
                    Label("About Andon Cone", systemImage: "info.circle")
                }

                Button {
                    openURL(PlayerModel.radioPageURL)
                } label: {
                    Label("Open Andon FM", systemImage: "safari")
                }

                #if DEBUG && os(iOS)
                Button(role: .destructive) {
                    fatalError("Intentional Embrace crash test")
                } label: {
                    Label("Crash Test", systemImage: "exclamationmark.triangle")
                }
                #endif
            }
            #endif
        }
        .listStyle(.sidebar)
        .navigationTitle("Andon FM")
    }
}

struct StationSourceRow: View {
    let station: Station
    let detail: AndonStationDetail?
    let track: AndonTrack?

    var body: some View {
        HStack(spacing: 10) {
            StationArtwork(url: detail?.imageURL, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(track?.displayTitle ?? station.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
