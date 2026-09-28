# Build configuration

`Base.xcconfig` is committed and holds the defaults, plus the app's identity —
`PRODUCT_NAME`, bundle identifier, display name, icon, export compliance. It optionally
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
| Identifier | `com.example.MusicBox.dev` | `com.example.MusicBox` |
| Name       | MusicBox Dev               | MusicBox               |
| Icon       | `AppIcon`                  | `AppIcon`              |

Debug gets its own identifier so a build mid-migration can't damage the library you
actually listen to — a different identifier means a different container, with its own
database, downloads and keychain login. Both point at `AppIcon` until a second icon set
exists; give Debug its own and the two become distinguishable on a home screen.

**Keeping your existing container.** A Debug build with a new identifier starts empty:
full re-sync, nothing downloaded, signed out. If you'd rather not pay that yet,
uncomment the two `MUSICBOX_DEBUG_*` lines in `Local.example.xcconfig` to pin Debug to
the release identifier. The natural moment to stop doing that is the rename to the real
identifier, which resets the container anyway.

## If a setting here seems to do nothing

A value set on the **target** in `project.pbxproj` silently overrides the same value
from an xcconfig. Check the target's Build Settings first; adding something here while
the target still sets it is the usual cause.

Watch for Xcode writing settings back to the target on its own. Removing
`CFBundleDisplayName` and `ITSAppUsesNonExemptEncryption` from `Info.plist` made Xcode
recreate both as target-level `INFOPLIST_KEY_*` entries, which then overrode this file.
Both now live here instead.
