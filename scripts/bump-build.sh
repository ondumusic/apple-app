#!/bin/sh
# Raises the build number for the next upload, and optionally sets a new version.
#
#   scripts/bump-build.sh        build N → N+1
#   scripts/bump-build.sh 1.1    version 1.1, build N → N+1
#
# The build number only ever goes up, across versions too: App Store Connect rejects an
# upload whose build number it has already seen for that version.
set -eu
cd "$(dirname "$0")/.."
file=Config/Version.xcconfig

build=$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9][0-9]*\)$/\1/p' "$file")
[ -n "$build" ] || { echo "No CURRENT_PROJECT_VERSION in $file" >&2; exit 1; }
sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $((build + 1))/" "$file"
if [ $# -gt 0 ]; then
    sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $1/" "$file"
fi
grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION) ' "$file"
