import AppIntents

/// Shortcuts and Focus automations. Running in the app's own process is the point: the
/// session is a date in `SettingsStore`, and the shared store is the one the player
/// checks.
nonisolated struct StartPrivateSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Private Session"
    static let description = IntentDescription(
        "Stops counting plays on this device. Ends on its own half an hour after the music stops.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SettingsStore.shared.startPrivateSession()
        return .result(dialog: "Private session started.")
    }
}

nonisolated struct EndPrivateSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Private Session"
    static let description = IntentDescription("Counts plays on this device again.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SettingsStore.shared.endPrivateSession()
        return .result(dialog: "Private session ended.")
    }
}
