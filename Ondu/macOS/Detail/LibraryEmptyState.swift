#if os(macOS)
import SwiftUI

/// What a library view shows when it has nothing to list.
///
/// There are two reasons for that and they need different answers: the library itself is
/// empty, which the next sync may fix and the user can do nothing about; or the
/// downloaded-only filter is hiding everything, which is one click to undo. A view that
/// just goes blank tells you neither.
struct LibraryEmptyState: View {
    enum Subject {
        case artists
        case albums
        case songs
        case playlist

        var noun: LocalizedStringResource {
            switch self {
            case .artists: "artists"
            case .albums: "albums"
            case .songs: "songs"
            case .playlist: "songs"
            }
        }
    }

    let subject: Subject
    /// Whether the downloaded-only filter is what emptied it.
    let isFiltered: Bool
    /// Clears the filter. Nil when the view can't — a playlist that is simply empty.
    var clearFilter: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if isFiltered, let clearFilter {
                Button("Show All Music", action: clearFilter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        if isFiltered { return "arrow.down.circle" }
        switch subject {
        case .artists: return "music.mic"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .playlist: return "music.note.list"
        }
    }

    private var title: LocalizedStringResource {
        guard !isFiltered else { return "Nothing Downloaded" }
        switch subject {
        case .artists: return "No Artists"
        case .albums: return "No Albums"
        case .songs: return "No Songs"
        case .playlist: return "Playlist Is Empty"
        }
    }

    private var message: LocalizedStringResource {
        guard !isFiltered else {
            return
                "No \(String(localized: subject.noun)) are downloaded to this Mac. Download some to play them offline, or show all music."
        }
        switch subject {
        case .playlist: return "Drag songs here, or add them from anywhere in your library."
        default: return "Your library is empty. Anything added on the server appears here after the next sync."
        }
    }
}
#endif
