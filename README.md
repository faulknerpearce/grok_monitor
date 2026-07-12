# Grok Usage

Native macOS menu bar app that shows your **Weekly SuperGrok Limit** at a glance — used percentage, segmented usage bar, product breakdown, and daily use for the week (Build / API / Chat / Imagine / Voice).

## Features

- Menu bar item matching the compact status style (icon, used %, capsule bar, optional category chips)
- Dropdown panel with weekly limit header, segmented bar, category rows, daily use chart, reset time
- Sign in once via embedded `WKWebView` (session cookies stored under Application Support, mode 0600)
- Also imports a non-expired `~/.grok/auth.json` bearer from `grok login` when present
- Adaptive polling (faster while the menu is open)
- SwiftData usage history + Swift Charts window
- CSV / JSON export
- Threshold notifications
- Launch at login
- Preferences for display toggles, poll intervals, and visible categories
- No Dock icon (`LSUIElement`)

## Requirements

- macOS 14+
- [Xcode 15+](https://developer.apple.com/xcode/) (full Xcode.app — Command Line Tools alone are not enough)
- SuperGrok / Grok account

## Build & run

After installing Xcode, point the active developer directory at it (once) and finish first-launch setup:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
```

Open and run:

```bash
open GrokUsage.xcodeproj
```

In Xcode: select the **GrokUsage** scheme → **My Mac** → Run (⌘R). Look for the menu bar icon (no Dock icon).

Or from the terminal:

```bash
xcodebuild -project GrokUsage.xcodeproj -scheme GrokUsage -configuration Debug -destination 'platform=macOS' build
open "build/DerivedData/Build/Products/Debug/Grok Usage.app"   # if using -derivedDataPath build/DerivedData
```

Optional: regenerate the Xcode project after adding source files:

```bash
python3 Scripts/generate_xcodeproj.py
```

### Core unit tests (no Xcode required)

```bash
./Scripts/run_core_tests.sh
```

## First run

1. Click the menu bar item → **Sign In…**
2. Log in to grok.com / accounts.x.ai in the sheet
3. Click **I'm signed in — Capture Session** if it does not auto-capture
4. Usage appears after the first successful refresh

## Privacy

Grok Usage stores session cookies and optional bearer tokens as **user-only files** under `~/Library/Application Support/GrokUsage/` (not Keychain — avoids access-dialog loops in debug builds). It only contacts xAI / Grok hosts to read your usage. Historical snapshots stay on this Mac (SwiftData). There is no third-party telemetry.

## Distribution / notarization

See [Docs/NOTARIZATION.md](Docs/NOTARIZATION.md) and `Scripts/notarize.sh`.

## Architecture

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) and [Docs/AUTH_AND_ENDPOINTS.md](Docs/AUTH_AND_ENDPOINTS.md).
