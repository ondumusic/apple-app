import SwiftUI

/// Says which side is behind when the app and the server disagree about the API.
///
/// Neither case is something the app can fix — it can't update itself, and it certainly
/// can't update the server — so this replaces the symptom (a sync that fails, a library
/// that stops changing) with the cause. It goes above the content rather than in front of
/// it: a library that's already downloaded still plays.
///
/// A tinted wash rather than a solid fill: white on saturated orange at caption size is
/// the hardest combination to read, and this one holds up in both appearances. The
/// session-expired strip it sits beside on iOS matches it for the same reason.
///
/// On macOS it sits under the player rather than across the window top, which is where
/// the traffic lights are.
struct ServerVersionNotice: View {
    let compatibility: ServerCompatibility
    let onDismiss: () -> Void

    var body: some View {
        if let message = compatibility.message {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                Spacer(minLength: 0)
                dismissButton
            }
            .font(Self.font)
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.16))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    #if os(macOS)
    private static let font: Font = .subheadline
    private static let horizontalPadding: CGFloat = 20
    private static let verticalPadding: CGFloat = 8
    #else
    private static let font: Font = .caption
    private static let horizontalPadding: CGFloat = 12
    private static let verticalPadding: CGFloat = 6
    #endif

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark").font(.caption.bold())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}
