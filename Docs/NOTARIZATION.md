# Notarization and distribution

Requires an Apple Developer Program membership and **Xcode.app** with a Developer ID Application certificate.

## 1. Archive

In Xcode:

1. Scheme **GrokUsage** → Any Mac
2. Product → Archive
3. Distribute App → Developer ID → Upload / Export

Or from the command line (with Xcode selected via `xcode-select`):

```bash
xcodebuild -project GrokUsage.xcodeproj -scheme GrokUsage -configuration Release \
  -archivePath build/GrokUsage.xcarchive archive

xcodebuild -exportArchive -archivePath build/GrokUsage.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist Scripts/ExportOptions.plist
```

## 2. Notarize

```bash
# Create an app-specific password at appleid.apple.com and store it in Keychain:
# xcrun notarytool store-credentials "AC_PASSWORD" --apple-id YOU@email --team-id TEAMID

./Scripts/notarize.sh build/export/Grok\ Usage.app
```

The script zips the app, submits with `notarytool`, waits, then staples the ticket.

## 3. Ship

- Zip or DMG the stapled `.app`
- Publish SHA-256 checksum alongside the download
- Optional later: Sparkle for auto-updates (not included in v1)

## Sandbox entitlements

`GrokUsage/Resources/GrokUsage.entitlements` enables:

- App Sandbox
- Outgoing network client
- User-selected file read/write (export panel)

## Gatekeeper check

```bash
spctl --assess --type execute -v "Grok Usage.app"
stapler validate "Grok Usage.app"
```
