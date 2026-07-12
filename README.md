# Grok Usage

A native macOS menu bar app for tracking your **Weekly SuperGrok** usage pool in real time.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![License](https://img.shields.io/badge/license-private-lightgrey)

## Overview

Grok Usage sits in the macOS menu bar and shows how much of your SuperGrok weekly limit you have used — overall and by product (Chat, Grok Build, API, and others when present). Sign in once with your Grok account; the app polls authenticated grok.com endpoints and keeps a local history for the daily chart.

## Features

| Area | Details |
|------|---------|
| **Menu bar** | Compact status: Grok icon, used %, optional filling pill, optional Chat / Build / API chips |
| **Dropdown** | Weekly used / remaining, segmented bar, category breakdown, daily bars, reset time |
| **Daily use** | Billing-week chart (`100/7` daily cap); day-over-day deltas from local history |
| **Auth** | WKWebView sign-in; session cookies in Application Support; optional `~/.grok/auth.json` import |
| **Polling** | Faster refresh while the menu is open; backoff on errors; sleep / wake aware |
| **History** | SwiftData snapshots, charts window, CSV / JSON export |
| **Alerts** | Optional threshold notifications |
| **Preferences** | Menu bar toggles, poll intervals, visible products, launch at login |
| **Agent app** | No Dock icon by default (`LSUIElement`) |

## Requirements

- macOS 14 Sonoma or later
- [Xcode 15+](https://developer.apple.com/xcode/) (full app; Command Line Tools alone are not enough)
- A SuperGrok / Grok account

## Getting started

### 1. Open the project

```bash
git clone git@github.com:faulknerpearce/grok_usage.git
cd grok_usage
open GrokUsage.xcodeproj
```

Select the **GrokUsage** scheme → **My Mac** → Run (⌘R). The app appears in the menu bar (no Dock icon).

### 2. Sign in

1. Click the menu bar item → **Sign In…**
2. Complete login on `accounts.x.ai` / grok.com in the sign-in window
3. If capture does not happen automatically, click **I'm signed in — Capture Session**
4. Usage appears after the first successful refresh

Optional: if you already ran `grok login`, the app can import a non-expired bearer from `~/.grok/auth.json`.

## Build from the command line

Point `xcode-select` at Xcode once (if needed):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
```

Debug build:

```bash
xcodebuild \
  -project GrokUsage.xcodeproj \
  -scheme GrokUsage \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  build

open "build/DerivedData/Build/Products/Debug/Grok Usage.app"
```

After adding source files, regenerate the Xcode project if needed:

```bash
python3 Scripts/generate_xcodeproj.py
```

## Testing

Full Xcode test suite:

```bash
xcodebuild \
  -project GrokUsage.xcodeproj \
  -scheme GrokUsage \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  test
```

Core parsers / builders without launching the app:

```bash
./Scripts/run_core_tests.sh
```

## Project layout

```
GrokUsage/
  App/           Entry point, AppDelegate
  Features/
    Auth/        WKWebView sign-in, session storage
    Usage/       Client, poller, models, daily builder, endpoint probe
    MenuBar/     Label renderer, dropdown, daily chart
    History/     SwiftData store, charts, export
    Settings/    Preferences, UserDefaults
    Alerts/      Threshold notifications
  Resources/     Info.plist, entitlements, assets
Docs/            Architecture, auth/endpoints, notarization
Scripts/         Xcode project generator, tests, notarize
GrokUsageTests/  XCTest suite
```

## Privacy

- Session cookies and optional bearer tokens are stored as **user-only** files under Application Support (not Keychain — avoids access-dialog loops on ad-hoc debug builds).
- Sandboxed container path (typical):  
  `~/Library/Containers/com.grokusage.app/Data/Library/Application Support/GrokUsage/`
- Network access is limited to xAI / Grok hosts for usage and auth.
- History stays on this Mac (SwiftData). No third-party telemetry.

## Documentation

| Doc | Contents |
|-----|----------|
| [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) | Module map and data flow |
| [Docs/AUTH_AND_ENDPOINTS.md](Docs/AUTH_AND_ENDPOINTS.md) | Auth model, endpoints, daily-use limitations |
| [Docs/NOTARIZATION.md](Docs/NOTARIZATION.md) | Developer ID signing and notarization |

## Distribution

For a signed, notarized release build, see [Docs/NOTARIZATION.md](Docs/NOTARIZATION.md) and `Scripts/notarize.sh`.

## Notes on daily use

Grok’s billing API exposes **cumulative weekly** usage, not a public per-day series. Until local day-to-day history exists, today’s bar shows the tracked weekly total. After the app has polled across multiple days, bars use day-over-day deltas. Each bar is scaled to a daily share of the pool (`100 / 7`).

## Contributing

1. Create a feature branch from `master`
2. Make focused commits with clear messages
3. Run `./Scripts/run_core_tests.sh` (and Xcode tests when UI changes)
4. Open a pull request

## License

Private repository. All rights reserved unless otherwise stated by the owner.
