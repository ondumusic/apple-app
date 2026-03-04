import SwiftUI

@Observable
final class SettingsStore {
    @ObservationIgnored
    @AppStorage("crossfadeDuration") var crossfadeDuration: Double = 5.0
}
