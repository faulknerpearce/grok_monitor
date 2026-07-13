# Architecture

## Overview

Grok Monitor is a SwiftUI agent-style macOS app (`LSUIElement` + `MenuBarExtra`) that authenticates to grok.com, polls usage endpoints, and renders weekly SuperGrok pool metrics in the menu bar and dropdown.

```
┌─────────────────────────────────────────────────────────┐
│ MenuBarExtra label  →  MenuBarPanelView (window style)  │
│ Preferences Window  →  charts / export / settings       │
└───────────────┬─────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────┐
│ UsagePoller  ←→  AuthSessionService (App Support files) │
│      │                   │                              │
│      ▼                   ▼                              │
│ UsageClient         WKWebView Sign-In                   │
│  REST / gRPC-web / CLI billing                          │
│      │                                                  │
│      ▼                                                  │
│ HistoryStore (SwiftData) → ThresholdNotifier            │
└─────────────────────────────────────────────────────────┘
```

## Modules

| Area | Responsibility |
|------|----------------|
| `App/` | `MenuBarExtra` scenes, `AppDelegate` activation policy |
| `Auth/` | WKWebView login, Application Support cookie/bearer persistence |
| `Usage/` | Models, HTTP client, gRPC-web parser, poller, endpoint probe |
| `MenuBar/` | Label, panel, segmented bar, category rows |
| `History/` | SwiftData snapshots, charts, CSV/JSON export |
| `Settings/` | UserDefaults-backed preferences, launch-at-login |
| `Alerts/` | Local notifications for usage thresholds |

## Data flow

1. On launch, `AuthSessionService` restores Application Support credentials.
2. `UsagePoller` starts a loop: active interval while the menu is open, idle interval otherwise; pauses across sleep/wake.
3. `UsageClient.fetchUsage()` tries REST JSON candidates, then grok.com gRPC-web billing, then CLI billing JSON.
4. Successful snapshots update the UI and append to SwiftData (deduped).
5. The dropdown **Daily use** chart scales each day to `100/7` of the weekly pool. Prefer server `dailySeries` when present; otherwise derive **day-over-day deltas** between successive local sample days within the billing week. Bars stay empty until two in-week samples exist (week-to-date product % is never painted onto the first sample day). Billing week bounds use `resetsAt` when available.
6. `ThresholdNotifier` fires once per threshold crossing.

## Auth storage

Session cookies and optional bearer tokens are stored as mode `0600` files under:

`~/Library/Application Support/GrokMonitor/auth_*.dat`

Keychain is intentionally avoided: unsigned/debug builds repeatedly prompt “wants to access the keychain.” Legacy Keychain items from earlier builds are deleted on launch.

## Percent semantics

- **Menu bar** shows **used** percent (e.g. 38%).
- **Dropdown** shows both used and remaining (e.g. `38% used · 62% remaining`) plus a daily use chart for the billing week.

## Error handling

- `401/403` → `AuthSessionService.markSessionInvalid` + panel prompts re-auth
- `429/5xx` / network → exponential backoff (30s → 10m cap)
- Decode failures keep `rawPayload` when available for debugging schema drift
