import Foundation

// Cached: re-creating a formatter on every SwiftUI render is wasteful and shows up
// in scrolling. RelativeDateTimeFormatter isn't documented thread-safe (Foundation
// formatters historically aren't), so we confine both the formatter and the helper
// to @MainActor — every SwiftUI caller is already on the main actor anyway.
@MainActor
private let sharedRelativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

/// Relative date in a SwiftUI-friendly form. Treats anything under five seconds as
/// "just now" — RelativeDateTimeFormatter renders the very recent past as "in 0 sec." /
/// "0 sec. ago", which reads strangely right after a refresh.
@MainActor
func relativeText(for date: Date, now: Date = Date()) -> String {
    let interval = abs(now.timeIntervalSince(date))
    if interval < 5 { return "just now" }
    return sharedRelativeDateFormatter.localizedString(for: date, relativeTo: now)
}
