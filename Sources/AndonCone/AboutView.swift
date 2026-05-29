import SwiftUI
import StoreKit

struct AboutView: View {
    @ObservedObject var store: TipStore
    @Environment(\.dismiss) private var dismiss
    @State private var celebration: TipCelebration?

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
        .tipCelebration(celebration)
        .onChange(of: store.completedPurchaseCount, triggerCelebration)
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
        .tipCelebration(celebration)
        .onChange(of: store.completedPurchaseCount, triggerCelebration)
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

    private func triggerCelebration(_ oldValue: Int, _ newValue: Int) {
        guard newValue > oldValue else { return }
        celebration = TipCelebration(seed: newValue)
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
        .task {
            await store.loadProducts()
        }
    }
}

private struct TipCelebration: Identifiable, Equatable {
    let id = UUID()
    let seed: Int
}

private extension View {
    func tipCelebration(_ celebration: TipCelebration?) -> some View {
        modifier(TipCelebrationModifier(celebration: celebration))
    }
}

private struct TipCelebrationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let celebration: TipCelebration?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let celebration {
                    TipCelebrationView(seed: celebration.seed, reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: celebration)
    }
}

private struct TipCelebrationView: View {
    let seed: Int
    let reduceMotion: Bool
    @State private var startDate = Date()
    @State private var isVisible = true

    private let duration: TimeInterval = 1.55

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let progress = min(1, timeline.date.timeIntervalSince(startDate) / duration)
                let opacity = 1 - max(0, progress - 0.72) / 0.28

                if reduceMotion {
                    drawReducedMotionBurst(in: context, size: size, opacity: opacity)
                } else {
                    drawConfetti(in: context, size: size, progress: progress, opacity: opacity)
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            startDate = Date()
            isVisible = true

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration))
                isVisible = false
            }
        }
    }

    private func drawConfetti(in context: GraphicsContext, size: CGSize, progress: Double, opacity: Double) {
        guard size.width > 0, size.height > 0 else { return }

        let colors: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .purple]
        let origin = CGPoint(x: size.width * 0.5, y: size.height * 0.38)

        for index in 0..<44 {
            let angle = seededDouble(index, salt: 11) * .pi * 2
            let speed = 78 + seededDouble(index, salt: 23) * 145
            let drift = CGFloat(cos(angle) * speed * progress)
            let lift = CGFloat(sin(angle) * speed * progress)
            let fall = CGFloat(210 * progress * progress)
            let point = CGPoint(x: origin.x + drift, y: origin.y + lift + fall)
            let side = CGFloat(5 + seededDouble(index, salt: 31) * 8)
            let rotation = Angle.radians((seededDouble(index, salt: 43) * 8 - 4) * progress)

            var particleContext = context
            particleContext.opacity = opacity
            particleContext.translateBy(x: point.x, y: point.y)
            particleContext.rotate(by: rotation)

            let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side * 0.62)
            let color = colors[index % colors.count]
            particleContext.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
        }
    }

    private func drawReducedMotionBurst(in context: GraphicsContext, size: CGSize, opacity: Double) {
        guard size.width > 0, size.height > 0 else { return }

        var symbolContext = context
        symbolContext.opacity = opacity

        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.38)
        let radius = min(size.width, size.height) * 0.12
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        symbolContext.fill(Path(ellipseIn: rect), with: .color(.pink.opacity(0.18)))

        let heartRect = CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
        symbolContext.draw(Image(systemName: "heart.fill"), in: heartRect)
    }

    private func seededDouble(_ index: Int, salt: Int) -> Double {
        var value = UInt64(seed &* 1_103_515_245 &+ index &* 12_345 &+ salt)
        value ^= value >> 33
        value &*= 0xff51afd7ed558ccd
        value ^= value >> 33
        value &*= 0xc4ceb9fe1a85ec53
        value ^= value >> 33
        return Double(value % 10_000) / 10_000
    }
}
