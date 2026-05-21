import SwiftUI
import StoreKit

struct AboutView: View {
    @ObservedObject var store: TipStore
    @Environment(\.dismiss) private var dismiss

    private let blogURL = URL(string: "https://andonlabs.com/blog/andon-fm")!

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("About")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 16)
            content
        }
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 520, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text("About")
                        .font(.headline)

                    Text("Andon Cone is a native player for the andon.fm live streams, an experiment run by Andon Labs to have LLMs manage a radio station.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: blogURL) {
                        Label("Read about Andon FM", systemImage: "safari")
                    }
                    .font(.callout)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("About Me")
                        .font(.headline)

                    (
                        Text("I'm ")
                        + Text("[@aparker.io](https://bsky.app/profile/aparker.io)")
                        + Text(", a developer and tinkerer. This application is free, but if you enjoyed it, feel free to leave a tip.")
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .tint(.accentColor)
                    .fixedSize(horizontal: false, vertical: true)

                    TipMenu(store: store)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("What does the name mean?")
                        .font(.headline)

                    Text("It is a little bit of wordplay: Andon Labs, light cones, and the fact that a speaker is, physically enough, a cone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = store.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                versionFooter
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Andon Cone")
                    .font(.title2.weight(.bold))
                Text("Native radio for Andon FM")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var versionFooter: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Text("Version \(version) (\(build))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TipMenu: View {
    @ObservedObject var store: TipStore

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.products.isEmpty {
                Text("Tips are not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(store.products) { product in
                        Button {
                            Task {
                                await store.purchase(product)
                            }
                        } label: {
                            Text("\(product.displayName) - \(product.displayPrice)")
                        }
                    }
                } label: {
                    Label("Leave a Tip", systemImage: "heart.fill")
                        .font(.callout.weight(.semibold))
                }
                .disabled(store.purchaseInProgressProductID != nil)
            }
        }
    }
}
