import Foundation
import Testing

@testable import Ondu

struct PrivateSessionTests {

    private let window = SettingsStore.privateSessionIdleWindow

    @Test func isOffByDefault() {
        #expect(makeTestSettings().isPrivateSession == false)
    }

    @Test func startingAndEndingFlipIt() {
        let store = makeTestSettings()
        store.startPrivateSession()
        #expect(store.isPrivateSession)
        store.endPrivateSession()
        #expect(store.isPrivateSession == false)
    }

    @Test func toggleGoesBothWays() {
        let store = makeTestSettings()
        store.togglePrivateSession()
        #expect(store.isPrivateSession)
        store.togglePrivateSession()
        #expect(store.isPrivateSession == false)
    }

    @Test func lapsesOnceTheIdleWindowPasses() {
        var now = Date()
        let store = SettingsStore(defaults: isolatedDefaults(), now: { now })
        store.startPrivateSession()
        now += window - 1
        #expect(store.isPrivateSession)
        now += 2
        #expect(store.isPrivateSession == false)
    }

    /// The session should outlast the workout, not a fixed hour: as long as music plays
    /// the deadline keeps moving.
    @Test func playbackPushesTheDeadlineForward() {
        var now = Date()
        let store = SettingsStore(defaults: isolatedDefaults(), now: { now })
        store.startPrivateSession()
        let original = store.privateSessionEndsAt
        now += window / 2
        store.extendPrivateSession()
        #expect(store.privateSessionEndsAt == now + window)
        #expect(store.privateSessionEndsAt != original)
        now += window - 1
        #expect(store.isPrivateSession)
    }

    /// Called twice a second from the player, so it mustn't write on every call.
    @Test func extendingWithinAMinuteIsANoOp() {
        var now = Date()
        let store = SettingsStore(defaults: isolatedDefaults(), now: { now })
        store.startPrivateSession()
        let original = store.privateSessionEndsAt
        now += 30
        store.extendPrivateSession()
        #expect(store.privateSessionEndsAt == original)
    }

    @Test func extendingWithoutASessionStartsNothing() {
        let store = makeTestSettings()
        store.extendPrivateSession()
        #expect(store.isPrivateSession == false)
        #expect(store.privateSessionEndsAt == nil)
    }

    /// Already lapsed, a session shouldn't come back because a track happened to play.
    @Test func extendingALapsedSessionDoesNotReviveIt() {
        var now = Date()
        let store = SettingsStore(defaults: isolatedDefaults(), now: { now })
        store.startPrivateSession()
        now += window + 1
        store.extendPrivateSession()
        #expect(store.isPrivateSession == false)
    }

    @Test func survivesARelaunch() {
        let defaults = isolatedDefaults()
        SettingsStore(defaults: defaults).startPrivateSession()
        #expect(SettingsStore(defaults: defaults).isPrivateSession)
    }

    /// Killed at the gym and reopened the next morning: no cleanup should be needed.
    @Test func aLapsedSessionIsOverOnRelaunch() {
        let defaults = isolatedDefaults()
        var now = Date()
        SettingsStore(defaults: defaults, now: { now }).startPrivateSession()
        now += window + 1
        #expect(SettingsStore(defaults: defaults, now: { now }).isPrivateSession == false)
    }
}
