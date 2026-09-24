import Foundation

/// Playing every track at a similar loudness.
///
/// The server measures each track's integrated loudness (EBU R128, reported in LUFS) and
/// we scale playback toward a common target, so a loudness-war master and a dynamic one
/// don't jump 10 dB apart when they follow each other.
///
/// **We can only attenuate.** `AVPlayer.volume` documents 1.0 as "the full volume of the
/// current item", so there is no headroom above unity to boost a quiet track into —
/// getting one would mean putting an `AVAudioEngine` in the playback path. The gain is
/// therefore clamped at 0 dB: loud masters come down to the target, anything already
/// quieter is left where it is.
nonisolated enum LoudnessNormalization {

    /// ReplayGain 2.0's reference level.
    ///
    /// Apple Music targets -16 and the streaming services -14. Lower is better for us
    /// precisely because we can't boost: the further down the target sits, the fewer
    /// tracks fall below it and get left uncorrected. The cost is that everything plays
    /// a couple of dB quieter, which is one adjustment of the system volume.
    static let targetLUFS: Double = -18

    /// A linear multiplier for `AVPlayer.volume`.
    ///
    /// An unmeasured track gets 1.0 and plays as-is. That makes a partly-measured library
    /// uneven — the unmeasured tracks are the loud ones — but it is honest, and it fixes
    /// itself as the server finishes measuring.
    static func gain(forLUFS lufs: Double?) -> Float {
        guard let lufs else { return 1 }
        return Float(pow(10, min(0, targetLUFS - lufs) / 20))
    }

    /// One album's loudness, derived from its tracks.
    ///
    /// The server measures per track, so this is the duration-weighted mean of their
    /// energy rather than a true whole-programme measurement. It lands within a few
    /// tenths of a dB; the difference is R128's gating, which can't be reproduced from
    /// per-track summaries. If the server ever reports album loudness itself, this goes.
    ///
    /// Unmeasured tracks sit out of the mean but still take the album's gain, so a
    /// partly-measured album keeps its internal dynamics intact.
    static func albumLUFS<S: Sequence>(_ tracks: S) -> Double?
    where S.Element == (lufs: Double?, duration: Double) {
        var energy = 0.0
        var seconds = 0.0
        for track in tracks {
            guard let lufs = track.lufs, track.duration > 0 else { continue }
            energy += track.duration * pow(10, lufs / 10)
            seconds += track.duration
        }
        guard seconds > 0, energy > 0 else { return nil }
        return 10 * log10(energy / seconds)
    }
}
