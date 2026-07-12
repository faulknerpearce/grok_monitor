#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/notarize.sh /path/to/Grok\ Usage.app [keychain-profile]
APP="${1:?Path to .app required}"
PROFILE="${2:-AC_PASSWORD}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 1
fi

ZIP="${APP%.app}.zip"
echo "Zipping $APP → $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to notary service (profile: $PROFILE)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "Stapling…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "Done. Ship the stapled app (re-zip after stapling if needed)."
