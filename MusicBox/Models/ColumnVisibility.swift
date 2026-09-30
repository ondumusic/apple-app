import Foundation

/// Which of a table's optional columns are hidden, given what was stored and what the
/// stored preference knew about.
///
/// The rule exists because a column added in an update has never been decided on. Before
/// this, a stored preference was taken as the whole answer, so a new column appeared in
/// every table anyone had ever customised and stayed hidden only in the ones they hadn't.
nonisolated enum ColumnVisibility {
    static func hidden(stored: [String]?, known: [String]?, defaults: Set<String>) -> Set<String> {
        guard let stored else { return defaults }
        return Set(stored).union(defaults.subtracting(known ?? []))
    }
}
