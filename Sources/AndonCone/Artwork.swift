import SwiftUI

struct StationArtwork: View {
    @EnvironmentObject private var cache: ArtworkCache
    let url: URL?
    /// Shown while `url` is still loading on first appearance — typically the station
    /// logo when `url` is an album-art URL. Prevents a placeholder flash during the
    /// brief window between metadata enrichment and the artwork bytes arriving.
    var fallbackURL: URL? = nil
    let size: CGFloat

    private var displayedImage: PlatformImage? {
        if let url, let image = cache.image(for: url) { return image }
        if let fallbackURL, let image = cache.image(for: fallbackURL) { return image }
        return nil
    }

    var body: some View {
        Group {
            if let image = displayedImage {
                cachedImage(image)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.12), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(8, size * 0.12), style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .task(id: url) {
            // Trigger fetch on miss. The cache dedupes, so re-asking is cheap.
            if let url { cache.prefetch(url) }
        }
        .task(id: fallbackURL) {
            if let fallbackURL { cache.prefetch(fallbackURL) }
        }
        .animation(.easeInOut(duration: 0.25), value: displayedImage != nil)
    }

    @ViewBuilder
    private func cachedImage(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #endif
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.18))
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.38))
                .foregroundStyle(.secondary)
        }
    }
}

struct LibraryButton: View {
    @EnvironmentObject private var library: MusicLibraryService
    let trackID: String

    var body: some View {
        let status = library.status(for: trackID)

        Button {
            switch status {
            case .inLibrary, .adding, .checking:
                break
            default:
                library.addToLibrary(trackID: trackID)
            }
        } label: {
            iconView(for: status)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(status == .adding || status == .checking)
        .help(helpText(for: status))
        .accessibilityLabel(accessibilityLabel(for: status))
        .task(id: trackID) {
            library.refreshStatus(for: trackID)
        }
    }

    private func iconView(for status: MusicLibraryService.LibraryStatus) -> some View {
        // ZStack with a Color.clear anchor keeps the icon's intrinsic size stable across
        // case swaps so flipping from the plus symbol to ProgressView doesn't resize the row.
        ZStack {
            Color.clear.frame(width: 22, height: 22)

            switch status {
            case .inLibrary:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            case .adding, .checking:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            default:
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func helpText(for status: MusicLibraryService.LibraryStatus) -> String {
        switch status {
        case .inLibrary: return "In your library"
        case .adding: return "Adding…"
        case .checking: return "Checking library…"
        case .notAuthorized: return "Tap to enable Apple Music access"
        case .noSubscription: return "Requires an Apple Music subscription"
        case .unavailable: return "Apple Music unavailable"
        case .error(let msg): return msg
        default: return "Add to your Apple Music library"
        }
    }

    private func accessibilityLabel(for status: MusicLibraryService.LibraryStatus) -> String {
        switch status {
        case .inLibrary: return "In your Apple Music library"
        case .adding: return "Adding to library"
        case .checking: return "Checking library"
        default: return "Add to Apple Music library"
        }
    }
}
