# Build configuration

`Base.xcconfig` is committed and holds the defaults, plus the app's identity —
`PRODUCT_NAME`, bundle identifier, display name, icon, copyright. It optionally
includes `Local.xcconfig`, which is gitignored and holds whatever differs on your
machine. Local wins: it's included after the defaults, and a later assignment replaces
an earlier one.

## Setup on a new machine

    cp Local.example.xcconfig Local.xcconfig

Then edit it. The project is already wired to `Base.xcconfig`, so there's nothing to do
in Xcode.

## What varies by configuration

|            | Debug                      | Release                |
| ---------- | -------------------------- | ---------------------- |
| Identifier | `com.ondumusic.ondu.dev`   | `com.ondumusic.ondu`   |
| Name       | Ondu Dev                   | Ondu                   |
| File       | `Ondu.app`                 | `Ondu.app`             |
| Icon       | `AppIcon`                  | `AppIcon`              |

Debug gets its own identifier so a build mid-migration can't damage the library you
actually listen to — a different identifier means a different container, with its own
database, downloads and keychain login. The name is what the home screen, Dock,
menu bar and About window show; the file on disk is `Ondu.app` in both, since a product
name that varied by configuration made Xcode rewrite the project file whenever the
active configuration changed. Both point at `AppIcon` until a second icon set
exists; give Debug its own and the two become distinguishable on a home screen.

**Keeping your existing container.** A Debug build with a new identifier starts empty:
full re-sync, nothing downloaded, signed out. If you'd rather not pay that yet,
uncomment the two `ONDU_DEBUG_*` lines in `Local.example.xcconfig` to pin Debug to
the release identifier — at the cost of Debug and release sharing one library again.

## If a setting here seems to do nothing

A value set on the **target** in `project.pbxproj` silently overrides the same value
from an xcconfig. Check the target's Build Settings first; adding something here while
the target still sets it is the usual cause.

## Info.plist

The app target does not generate its Info.plist from `INFOPLIST_KEY_*` build settings.
It uses a hand-written file per platform, `Ondu/Info-iOS.plist` and
`Ondu/Info-macOS.plist`, selected by an SDK condition on `INFOPLIST_FILE`. Anything that
varies is a `$(…)` reference to a setting from `Base.xcconfig`, so the display name is
`$(EFFECTIVE_APP_NAME)` and the copyright `$(ONDU_COPYRIGHT)`.

Generation is off on purpose. Xcode's target editor treats `INFOPLIST_KEY_*` settings as
its own: whenever the Info tab is shown (which happens on launch if it was the last
thing open), it writes every such value it can see onto the target as a literal,
resolved for the active configuration and applied to all configurations. With the
display name coming from the xcconfig, that once turned a Release archive into
"Ondu Dev". A hand-written plist gives the editor nothing to import. Both files are
listed as membership exceptions on the synced `Ondu` folder so they are not also copied
into the bundle as resources; a new plist there needs the same.

The Info tab also re-serialises whichever plist it is showing, so comments do not
survive in them. Why the less obvious keys are there:

- `UIBackgroundModes` is audio only. `fetch` and `processing` were once declared but
  nothing uses BGTaskScheduler, and an unused background mode is something review asks
  about.
- `NSAppTransportSecurity` allows local networking so a Debug build can reach a local
  server without TLS. Release builds refuse an `http://` server outright (see
  `LoginView.allowsInsecureServers`), so nothing cleartext is ever requested, and it is
  scoped to local addresses rather than `NSAllowsArbitraryLoads`.
- `NSLocalNetworkUsageDescription` is in both files: iOS and macOS 15 prompt before an
  app may reach LAN addresses, and without a string the prompt gives the user nothing
  to decide on.
- `ITSAppUsesNonExemptEncryption` is false because the app only speaks HTTPS to the
  user's own server. Without it, every App Store upload asks the question again.
