import Foundation
import SwiftData
import Testing

@testable import Ondu

struct ServerInfoTests {

    private func makeLibrary() throws -> MusicLibrary {
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
            LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return MusicLibrary(container: container)
    }

    private func decode(_ json: String) throws -> APIService.ServerInfo {
        try JSONDecoder().decode(APIService.ServerInfo.self, from: Data(json.utf8))
    }

    @Test func readsThePresetsAServerLists() throws {
        let info = try decode(
            """
            {"version":"1.0.0-rc.5","apiVersion":2,"defaultPreset":"default_ogg","presets":[
              {"id":"default_ogg","name":"Default (192kbps)","codec":"opus","container":"ogg",
               "mimetype":"audio/ogg","extension":"opus","bitrate":192},
              {"id":"mobile_ogg","name":"Mobile (96kbps)","codec":"opus","container":"ogg",
               "mimetype":"audio/ogg","extension":"opus","bitrate":96}]}
            """)
        let list = try #require(info.presetList)
        #expect(list.defaultId == "default_ogg")
        #expect(list.presets.map(\.id) == ["default_ogg", "mobile_ogg"])
    }

    /// Servers from before presets were listed only send the two version fields.
    @Test func anOlderServerStillDecodes() throws {
        let info = try decode(#"{"version":"1.0.0-rc.4","apiVersion":2}"#)
        #expect(info.apiVersion == 2)
        #expect(info.presetList == nil)
    }

    @Test func syncAdoptsTheServersPresets() throws {
        let settings = makeTestSettings()
        let service = SyncService(
            api: APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test"),
            musicLibrary: try makeLibrary(), settings: settings)
        service.apply(
            try decode(
                """
                {"version":"2.0.0","apiVersion":2,"defaultPreset":"hq","presets":[
                  {"id":"hq","name":"HQ","codec":"opus","container":"ogg",
                   "mimetype":"audio/ogg","extension":"opus","bitrate":256}]}
                """))
        #expect(settings.serverPresets.defaultId == "hq")
        #expect(service.serverVersion == "2.0.0")
    }

    /// Moving from a server that lists presets to one that doesn't must not leave the
    /// newer server's ids behind: the older server only knows the built-in ones.
    @Test func anOlderServerResetsToTheBuiltInPresets() throws {
        let settings = makeTestSettings()
        settings.serverPresets = TranscodePresetList(defaultId: "hq", presets: [])
        let service = SyncService(
            api: APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test"),
            musicLibrary: try makeLibrary(), settings: settings)
        service.apply(try decode(#"{"version":"1.0.0-rc.4","apiVersion":2}"#))
        #expect(settings.serverPresets == .builtIn)
    }
}
