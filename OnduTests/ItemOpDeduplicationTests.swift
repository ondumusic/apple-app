import Foundation
import Testing
@testable import Ondu


/// The server rejects the same item twice in one request, and batching two drags of one
/// track produces exactly that.
struct ItemOpDeduplicationTests {

    private func move(_ id: UUID, _ position: String) -> MoveItemsPayload.Entry {
        MoveItemsPayload.Entry(itemId: id, position: position)
    }

    @Test func keepsOnlyTheLastMoveOfAnItem() {
        let a = UUID(), b = UUID()
        let entries = [move(a, "a0"), move(b, "a1"), move(a, "a2")]

        let kept = OutboxService.lastPerItem(entries)

        #expect(kept.map(\.position) == ["a1", "a2"])
    }

    @Test func leavesDistinctMovesAlone() {
        let entries = [move(UUID(), "a0"), move(UUID(), "a1")]
        #expect(OutboxService.lastPerItem(entries).count == 2)
    }

    @Test func dropsRepeatedRemovals() {
        let a = UUID(), b = UUID()
        #expect(OutboxService.deduplicated([a, b, a]) == [a, b])
    }
}
