import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
func playHaptic() {
    #if os(iOS)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
}

enum HeroElevation {
    case compact
    case lifted
}

struct HeroCardBackground<S: Shape>: ViewModifier {
    let accent: Color
    let shape: S
    let reduceTransparency: Bool
    let colorScheme: ColorScheme
    let elevation: HeroElevation

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(AppSurface.elevated, in: shape)
                .overlay(shape.stroke(accent.opacity(0.5), lineWidth: 1.5))
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        radius: elevation == .lifted ? 18 : 12,
                        y: elevation == .lifted ? 10 : 6)
        } else {
            content
                .background(accent.opacity(colorScheme == .dark ? 0.14 : 0.08), in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1))
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.11),
                        radius: elevation == .lifted ? 24 : 18,
                        y: elevation == .lifted ? 14 : 10)
        }
    }
}

struct AppGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(AppSurface.elevated, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.18), lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            let baseGlass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            content.glassEffect(baseGlass.interactive(interactive), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.11), lineWidth: 1))
                .shadow(color: Color.primary.opacity(0.05), radius: 12, y: 6)
        }
    }
}

extension View {
    func panelStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func appGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(AppGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

enum AppSurface {
    static var primary: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    /// Solid surface used when Reduce Transparency is on.
    static var elevated: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

struct EmptyState: View {
    let text: String
    let systemImage: String

    var body: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            ContentUnavailableView(text, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        }
    }
}
