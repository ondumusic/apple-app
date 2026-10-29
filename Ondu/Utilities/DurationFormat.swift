import Foundation

/// The one m:ss format for times in the app — the track list, both players, the mini
/// player. Each used to have its own, and some rounded where others truncated, so a
/// 125.6-second track read 2:05 in the list and 2:06 in the player.
nonisolated enum DurationFormat {
    /// Whole seconds, never rounded: elapsed time ticks over only after a full second has
    /// played, and finishes on the duration shown rather than a second short of it.
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Time left, rounded up: "-0:01" through the last second rather than "-0:00" with
    /// the music still going, and "-0:00" only once nothing is left.
    static func remaining(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "-0:00" }
        return "-" + string(seconds.rounded(.up))
    }
}
