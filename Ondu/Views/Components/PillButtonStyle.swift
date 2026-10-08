import SwiftUI

private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    @Environment(SettingsStore.self) private var settings

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .labelStyle(PillLabelStyle())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(settings.resolvedAccentColor.opacity(configuration.isPressed ? 0.2 : 0.12))
            .foregroundStyle(settings.resolvedAccentColor)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
