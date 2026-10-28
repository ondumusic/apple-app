# Ondu

SwiftUI multiplatform music streaming app (iOS 26.2+ / macOS 15.7+) connecting to a self-hosted Elixir/Phoenix server backed by SQLite. Both platforms ship in v1.0; the macOS UI is a native AppKit/SwiftUI hybrid rather than a port of the iOS one. Deferred work is tracked in a local `TODO.md`, kept out of the repo.

## Architecture

### Sync-based library

The full library metadata (artists, albums, tracks, playlists) is synced to on-device SwiftData via `GET /sync?cursor=`. **All browsing is local** — there is no API pagination for browse views. The opaque cursor is persisted in `UserDefaults`.

### Key services

- `Persistence/MusicLibrary.swift` — SwiftData store + query API. Owns the `ModelContainer` (with schema migration fallback) and all download state. Query methods read a `revision` counter; mutations bump it. Returns reconstructed `Artist`/`Album`/`Track`/`Playlist` structs by joining `LibraryArtist`/`LibraryAlbum`/`LibraryTrack` rows.
- `Services/SyncService.swift` — drives `/sync` paging. `hasCompletedInitialSync` gates the UI behind a progress view. Foreground triggers a delta sync (5-minute cooldown). `sync()` always flushes the outbox first so local mutations land before the server snapshot.
- `Services/OutboxService.swift` — durable replay queue for playlist mutations. Drains on launch, foreground, connectivity restore, at the top of `sync()`, and after every enqueue. Batches adjacent item-level mutations into one PATCH `/items` call (capped at 250 ops). 422 errors decode into `PlaylistItemsError` for typed recovery.
- `Services/PlaylistController.swift` — synchronous façade. UI → local SwiftData write → outbox enqueue, returns immediately.
- `Services/PlayerService.swift` — `AVQueuePlayer` wrapper. Owns shuffle, queue, gapless/crossfade, `AVAudioSession`, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`. Audio session uses `routeSharingPolicy: .longFormAudio` (Apple's recommended policy for music apps).
- `Services/DownloadService.swift` — background `URLSession` named `"<bundle id>.downloads"`, so Debug and release never pick up each other's transfers. Files at `AppSupport/Ondu/Downloads/{artistId}/{albumId}/{trackId}.ext`. Download state lives on `LibraryTrack.isDownloaded` + `localFilePath` (relative path).
- `Services/SmartShuffle.swift` — Fisher-Yates plus a forward-pass spreader that pushes same-album/artist tracks apart. Gated by `SettingsStore.spreadShuffle`.

### Sync flow

1. **Initial sync**: clears local DB, pages through `/sync` until `complete: true`. `ContentView` shows `SyncProgressView` until this finishes.
2. **Delta syncs**: send cursor, get only changes. Triggered on foreground (5-min cooldown) or pull-to-refresh on any list view.
3. **Logout**: `SyncService.clearSyncState()` + `musicLibrary.clearAll()`.

### API endpoints

Base URL ends in `/api` (set during login). All bodies send lowercase UUID strings; the server normalizes.

- `POST /auth/login`, `GET /auth/me`, `GET /auth/playtoken`, `DELETE /auth/session`
- `GET /sync?cursor=`
- `POST /playlists`, `PATCH /playlists/{id}`, `DELETE /playlists/{id}`
- `PATCH /playlists/{id}/items` — batched add/move/remove (mixed). 422 returns the discriminated `PlaylistItemsError` union.
- Transcoding presets: `TranscodePreset` asks for `default_ogg`/`mobile_ogg` (Opus in Ogg: gapless, seekable, sized up front, so a transcoded download is a plain GET).
- Streaming: `track.streamUrl + ?token=`.

### Playlists

Playlists shipped on `feat/playlists`. Folders are `Playlist`s with `isFolder == true`; `parentId == nil` is root. Item positions are base-62 fractional index strings (`Services/FractionalIndex.swift`), byte-compatible with rocicorp/fractional-indexing and with the server's. `OutboxService` remaps temp UUIDs to server UUIDs across all queued mutations on `create_playlist` / `add_items` resolves. Local state is never rolled back on outbox discard — the next sync reconciles authoritatively.

## Code conventions

### Hard rules

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on. New `struct`/`enum`/`@Model` types need `nonisolated`.
- `@ObservationIgnored` is required for stored closures and non-UI state inside `@Observable` classes.
- `track.streamUrl` is a `String`, not a `URL`. Convert + resolve relative URLs against `api.baseURL`.
- Use Nuke's `LazyImage` / `ArtworkView` for artwork — never `AsyncImage`.
- `@Environment(Type?.self)` does not work — use the `optionalEnvironment()` helper.
- The `revision` counter pattern: query methods read it, mutations increment it.
- Filesystem auto-sync is enabled — new Swift files don't need `.pbxproj` edits.

### Don't

- **Don't force logout on auth issues.** Show the `ReAuthView` re-auth dialog. Never delete user data without explicit consent.
- **Don't add comments that explain WHAT the code does** — names already do that. Only comment WHY when it's non-obvious (a hidden constraint, a workaround, surprising behavior).
- **Don't reference past tasks/PRs/issues in comments** — that belongs in the PR description and rots in code.
- **Don't add backwards-compatibility shims, dead-code fallbacks, or speculative validation.** If something is unused, delete it.
- **Don't use `print` for production logging.** It's only acceptable inside `#if DEBUG` blocks.

### Do

- Follow existing patterns when in doubt — read the nearest sibling file.
- **Format with swift-format** (config in `.swift-format`, ships with Xcode): `xcrun swift-format format -i -r --parallel Ondu OnduTests`. CI fails on anything `xcrun swift-format lint --strict -r Ondu OnduTests` reports.
- Prefer `async` / `await` and `@MainActor` over `DispatchQueue`.
- Keep responses concise. Terse output is preferred; trailing summaries that restate the diff are not.
- **Maintain tests with code changes.** Add or update tests as part of the same work, not as a separate task. Test files live in `OnduTests/`.
- **Localize user-facing strings.** SwiftUI's `Text("...")` literal initializer auto-routes through `Localizable.xcstrings`. For dynamic counts, use Apple's inflection markup: `Text("^[\(count) song](inflect: true)")`. Strings stored as `String` and passed to `Text(String)` are **not** localized — use `LocalizedStringResource` instead.

## Commit messages

- Subject: `area: what changed`, imperative, terse, no trailing period (e.g. `downloads: fix foreground-migration concurrency bug`). No generic messages (`fix`, `wip`, `updates`, `more tests`, `attempt 2`) — say what actually changed.
- Body: usually unnecessary — most commits are their subject. Add one when a non-obvious reason or constraint sits behind the change, and keep it to a sentence or two of that reason. Not a narrative of what was tried and abandoned, not what might be done later, not the diff restated in prose.
- When a commit is authored or co-authored by Claude Code, add `Co-Authored-By: <model name> <noreply@anthropic.com>` as the last line, naming the model actually in use at commit time.
- A `commit-msg` hook (`.githooks/commit-msg`) rejects generic/junk subjects at commit time, and strips the `Claude-Session:` trailer Claude Code appends. It's installed at `.git/hooks/commit-msg` in this clone; a fresh clone needs to copy or symlink it in (see the hook's header comment) since git doesn't version hooks.

## Build & test

```bash
# Build for iPhone simulator
xcodebuild -scheme Ondu -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build

# Run unit tests (~1 min)
xcodebuild -scheme Ondu -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test
```

A test run that hangs with no output usually means the test host crashed: the bundle
aborts mid-run and leaves `/usr/libexec/testmanagerd` orphaned, which then wedges the
*next* run too. Killing `xcodebuild` doesn't clear it — `killall -9 testmanagerd` does.
Look for a crash report in `~/Library/Logs/DiagnosticReports/Ondu*.ips` and for a
failing test in the same area before blaming the simulator.

Parallel testing is off deliberately. The iOS 27 simulator runtime clones unreliably —
runs failed with "Failed to install or launch the test runner", whole clones reporting
every test as failed in 0.000s, and a 600s "collecting diagnostics from simulator"
stall. Serially the same 377 tests pass in under a minute.

Judge a build or test run by its **exit code**, not by grepping for `error:`. The first
build after an Xcode upgrade prints `error: the following command failed with exit code 0
but produced no further output` while succeeding — that's the SDK stat-cache and explicit
module rebuild, and it clears once the caches are warm.

### SourceKit indexing noise

After file edits, SourceKit often emits transient "Cannot find type X in scope" errors for types defined in the same module (`MusicLibrary`, `PlayerService`, `Track`, etc.). These are stale indexer state, not real errors. Trust `xcodebuild` over live diagnostics.
