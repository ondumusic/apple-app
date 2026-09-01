#if os(macOS)
import SwiftUI

/// Back control for pushed detail views. NavigationStack puts its own back button in the
/// toolbar's `.navigation` region — the same region PlayerToolbar's transport occupies —
/// so it lands beside the repeat button and reads as a player control. Pushed views hide
/// that one and carry this instead, next to the content it returns from.
struct BackToResultsButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.backward")
                .font(.body.weight(.medium))
        }
        .buttonStyle(.plain)
        .help("Back")
        .accessibilityLabel("Back")
    }
}
#endif
