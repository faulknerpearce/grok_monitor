# Contributing to Grok Monitor

Thanks for helping improve Grok Monitor. This project is a native macOS menu bar app; small, focused changes are easiest to review.

## Development setup

1. Install [Xcode 15+](https://developer.apple.com/xcode/) on macOS 14+.
2. Clone the repo and open `GrokMonitor.xcodeproj`.
3. Select the **GrokMonitor** scheme → **My Mac** → Run.

```bash
git clone https://github.com/faulknerpearce/grok_monitor.git
cd grok_monitor
open GrokMonitor.xcodeproj
```

After adding or removing source files, regenerate the Xcode project:

```bash
python3 Scripts/generate_xcodeproj.py
```

To regenerate the black Grok app icon:

```bash
swift Scripts/generate_icon.swift GrokMonitor/Resources/Assets.xcassets/AppIcon.appiconset
```

## Before you open a PR

- Keep changes focused on one concern.
- Prefer clear commit messages that explain *why*.
- Run the core tests:

```bash
./Scripts/run_core_tests.sh
```

- When you touch parsing, auth, history, or UI behavior, also run:

```bash
xcodebuild \
  -project GrokMonitor.xcodeproj \
  -scheme GrokMonitor \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  test
```

## Pull requests

1. Branch from `master`.
2. Describe the problem and how you verified the fix.
3. Note any user-facing behavior changes (menu bar, sign-in, privacy).
4. Do not commit secrets, signing certificates, provisioning profiles, or personal session cookies.

## Scope notes

- Grok Monitor is an **unofficial** client. It uses authenticated grok.com surfaces that can change without notice.
- Avoid scraping that violates xAI terms; prefer the existing auth + endpoint approach documented in `Docs/AUTH_AND_ENDPOINTS.md`.
- Do not add telemetry or third-party analytics without discussion.

## Code of conduct

By participating, you agree to uphold our [Code of Conduct](CODE_OF_CONDUCT.md).
