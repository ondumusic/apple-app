#if os(macOS)
import SwiftUI

/// One toolbar control carrying both what the view shows and how it's ordered, the way
/// the iOS list views present it. Two separate controls — a segmented filter plus a sort
/// menu — competed for the same corner and read as unrelated when they aren't: both
/// answer "which records, in what order".
struct LibraryOptionsMenu<Sort: View>: View {
    @Binding var filter: LibraryFilter
    @ViewBuilder var sort: Sort

    var body: some View {
        Menu {
            Picker("Show", selection: $filter) {
                Text("All Music").tag(LibraryFilter.all)
                Text("Downloaded").tag(LibraryFilter.downloaded)
            }
            .pickerStyle(.inline)

            sort
        } label: {
            // Filled when a filter is narrowing what you see, so the menu says whether
            // it's doing anything without being opened. Mail and Finder both do this.
            Label(
                "View Options",
                systemImage: filter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        // Outside a toolbar a Menu draws itself bordered and stretches to fill, which
        // made it a full-width "View Options" bar across the header. Music's is a bare
        // glyph at the trailing edge.
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .menuIndicator(.hidden)
        .help("Filter and sort")
    }
}

extension LibraryOptionsMenu where Sort == EmptyView {
    init(filter: Binding<LibraryFilter>) {
        self.init(filter: filter, sort: { EmptyView() })
    }
}

/// The sort half. One row per field rather than a field list plus a separate
/// ascending/descending pair: direction only ever applies to the field you picked, so
/// splitting them made you set two things to express one. Choosing the current field
/// again reverses it, and the arrow on that row says which way it's pointing.
struct SortOptionsSection<Option: Hashable & CaseIterable & RawRepresentable>: View
where Option.AllCases: RandomAccessCollection, Option.RawValue == String {
    @Binding var selection: Option
    @Binding var ascending: Bool

    var body: some View {
        Section("Sort By") {
            ForEach(Option.allCases, id: \.self) { option in
                // A Toggle rather than a Button: in a menu that also holds a Picker,
                // SwiftUI drops a Button's Label image, so the direction arrow never
                // drew. A Toggle gets the real checkmark column, and re-picking the
                // active field still calls set — which is the reverse gesture.
                Toggle(isOn: Binding(
                    get: { selection == option },
                    set: { isOn in
                        if isOn {
                            selection = option
                            ascending = true
                        } else {
                            ascending.toggle()
                        }
                    }
                )) {
                    Text(label(for: option))
                }
            }
        }
    }

    private func label(for option: Option) -> String {
        guard option == selection else { return option.rawValue }
        return "\(option.rawValue)  \(ascending ? "\u{2191}" : "\u{2193}")"
    }
}

#endif
