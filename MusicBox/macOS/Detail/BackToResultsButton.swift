#if os(macOS)
import SwiftUI

/// Back bar for pushed detail views. NavigationStack puts its own back button in the
/// toolbar's `.navigation` region — the same region PlayerToolbar's transport occupies —
/// so it lands beside the repeat button and reads as a player control. Pushed views hide
/// that one and carry this strip instead.
///
/// It names where it returns to rather than repeating the page's own title, which the
/// header underneath already shows.
struct BackBar: View {
    let destination: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.backward")
                .font(.subheadline.weight(.semibold))
            Text(destination)
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement()
        .accessibilityLabel("Back to \(destination)")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
