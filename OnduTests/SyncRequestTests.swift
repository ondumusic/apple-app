import Foundation
import Testing

@testable import Ondu

struct SyncRequestTests {

    private func value(_ name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name == name }?.value
    }

    /// Sent on every sync, first one included: the server records it in the cursor and
    /// resends everything once the number changes, which only works if it was there to
    /// compare against.
    @Test func everySyncSaysWhichSchemaItReads() {
        let items = APIService.syncQueryItems(cursor: nil)
        #expect(value("schemaVersion", in: items) == String(APIService.syncSchemaVersion))
        #expect(value("cursor", in: items) == nil)
    }

    @Test func aDeltaSyncSendsTheCursorToo() {
        let items = APIService.syncQueryItems(cursor: "v1-abc")
        #expect(value("cursor", in: items) == "v1-abc")
        #expect(value("schemaVersion", in: items) == String(APIService.syncSchemaVersion))
    }
}
