import SwiftUI

/// The private session, in the strip both platforms use for notices. The action ends the
/// session rather than hiding the strip: a bar you could dismiss and forget would bring
/// back the very thing the idle timeout exists to prevent.
struct PrivateSessionNotice: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if settings.isPrivateSession {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text("Private session — plays aren't counted.")
                Spacer(minLength: 0)
                Button("End") { settings.endPrivateSession() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(Self.font)
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
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
}
