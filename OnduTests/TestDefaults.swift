import Foundation

@testable import Ondu

/// A `UserDefaults` suite nobody else is using.
///
/// Swift Testing runs suites in parallel, every test that builds a `PlayerService` or a
/// `DownloadService` builds a `SettingsStore` with it, and `SettingsStoreTests` clears
/// keys outright — so on `UserDefaults.standard` the tests wrote each other's volume,
/// shuffle flag and repeat mode out from under themselves. Which ones failed varied per
/// run, which is what made it look like a regression rather than interference.
func isolatedDefaults() -> UserDefaults {
    let name = "ondu.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// A settings store that can't be seen by any other test.
func makeTestSettings() -> SettingsStore {
    SettingsStore(defaults: isolatedDefaults())
}
