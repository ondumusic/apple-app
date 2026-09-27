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

    /// The level playback is scaled toward — the streaming convention, and what this
    /// library's own distribution asks for.
    ///
    /// Started at -18 (ReplayGain 2.0's reference) on the theory that a lower target
    /// leaves fewer tracks below it and so uncorrected. Measured against a real 4,500
    /// track library that turned out to be paying for almost nothing: its 10th percentile
    /// sat at -16.5 LUFS, so -18 bought about half a dB of extra evenness and charged
    /// 3.4 dB of level for it, running a typical track at 45% of full scale.
    ///
    /// Because we can only attenuate, target level and evenness are the same dial: every
    /// dB the target rises is a dB of residual spread against the tracks already below
    /// it, which can't be lifted. -14 leaves roughly the quietest tenth uncorrected by at
    /// most a couple of dB, which is the better end of that trade on a phone at full
    /// volume. Boosting is what removes the trade rather than repositioning it.
    static let targetLUFS: Double = -14

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
