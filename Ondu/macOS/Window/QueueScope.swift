#if os(macOS)
import SwiftUI

/// Which half of the queue a panel is showing.
///
/// iTunes 11 put this on a clock button beside Clear; Music.app now uses a segmented
/// control above the list. Both spend the panel's heading on the switcher — a segmented
/// control there reads as a control where a title should be, so the heading *is* the
/// switcher here: it names what you're looking at and opens a menu to change it.
nonisolated enum QueueScope: String, CaseIterable, Identifiable {
    case upNext
    case history

    nonisolated var id: String { rawValue }

    /// "Up Next" rather than Music's "Playing Next" — it's what the player row's toggle
    /// and the View menu already call it.
    var title: LocalizedStringKey {
        switch self {
        case .upNext: "Up Next"
        case .history: "History"
        }
    }
}

struct QueueScopeMenu: View {
    @Binding var scope: QueueScope
    /// The panel's heading font. The window's header is .headline, the mini player's is
    /// a bold caption.
    var font: Font = .headline

    var body: some View {
        Menu {
            Picker("", selection: $scope) {
                ForEach(QueueScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 3) {
                Text(scope.title)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(font)
        }
        // A plain button rather than .borderlessButton: that style draws its own
        // indicator ahead of the label and ignores .menuIndicator, which put a chevron
        // on the wrong side of the heading.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
#endif
