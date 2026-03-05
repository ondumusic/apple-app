import SwiftUI

@Observable
final class SettingsStore {
    @ObservationIgnored
    @AppStorage("crossfadeDuration") var crossfadeDuration: Double = 5.0

    @ObservationIgnored
    @AppStorage("maxConcurrentDownloads") var maxConcurrentDownloads: Int = 3
}
