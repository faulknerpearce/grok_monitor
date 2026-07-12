# Auth and endpoints

Grok does not publish a stable public consumer API for the Weekly SuperGrok pool. This app uses the same authenticated surfaces the web Settings → Usage experience relies on, with defensive decoding.

## Authentication

### Primary: WKWebView session cookies

1. User signs in inside an embedded `WKWebView` pointed at `https://grok.com/?_s=usage`.
2. After navigation returns to `grok.com`, cookies are read from `WKWebsiteDataStore.default().httpCookieStore`.
3. Cookies scoped to `grok.com` / `x.ai` / `x.com` are serialized into a `Cookie` header and stored under Application Support (`~/Library/Application Support/GrokMonitor/auth_session.dat`, mode `0600`).

`ASWebAuthenticationSession` is **not** used because its cookies live in the system jar and are not readable by the app. Keychain is also avoided to prevent access-dialog loops in unsigned debug builds.

Optional bearer tokens captured during WebKit sign-in (or saved under Application Support) are sent as `Authorization: Bearer …` when present. The app no longer imports `~/.grok/auth.json` from the Grok CLI.

## Endpoints (ordered)

| Order | Method | URL | Notes |
|------:|--------|-----|-------|
| 1 | GET | `https://grok.com/rest/subscriptions` | Prefer JSON with product breakdown |
| 1 | GET | `https://grok.com/rest/user` | Alternate identity/usage payload |
| 1 | GET | `https://grok.com/rest/billing/usage` | Candidate usage JSON |
| 1 | GET | `https://grok.com/rest/usage` | Candidate usage JSON |
| 2 | POST | `https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig` | gRPC-web+proto; empty frame body; yields used % + reset + product mix |
| 3 | GET | `https://cli-chat-proxy.grok.com/v1/billing` | CLI JSON; needs bearer |

### Daily use — status

**No confirmed public daily series endpoint.**

Probed (2026-07-11) with a live session:

| Endpoint | Result |
|----------|--------|
| `GetGrokCreditsConfig` | Cumulative weekly `%` + product mix + period start/end only |
| `GetGrokUsageInfo` / `GetGrokBuildBillingHistory` | HTTP 200, **empty body** (even with period params) |
| `GetUsage` / `GetDailyUsage` / REST `/usage/daily` | Empty or 404 |

Observed CreditsConfig paths: `[1,1]` used%, `[1,4]` period start, `[1,5]` reset, `[1,7]` product enum+%.

Until a real daily RPC is found, the dropdown chart:

1. Prefers `WeeklyUsageSnapshot.dailySeries` when the parser finds day stamps
2. Else uses **deltas between successive local sample days** (SwiftData end-of-day snapshots)
3. On the **first tracked day**, attributes that day’s cumulative weekly used % to that day (scaled to a **`100/7`** daily cap) — days before tracking stay empty rather than inventing a split
4. After a calendar day rollover, yesterday keeps its end-of-day total; today shows only new usage since then

Use `UsageEndpointProbe.probeWithFieldDump(...)` when hunting a real daily API.


### gRPC-web request shape

```
POST /grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig
Content-Type: application/grpc-web+proto
x-grpc-web: 1
Origin: https://grok.com
Referer: https://grok.com/?_s=usage
Cookie: <session>
Authorization: Bearer <optional>

Body: 00 00 00 00 00   # empty gRPC-web data frame
```

Response is scanned for float32 usage percent fields and unix reset timestamps (community-proven approach used by tools such as CodexBar).

### Expected JSON fields (defensive)

```json
{
  "usedPercent": 35,
  "remainingPercent": 65,
  "resetsAt": "2026-07-16T20:25:00Z",
  "products": [
    { "id": "build", "displayName": "Grok Build", "percentOfPool": 25 },
    { "id": "api", "displayName": "API", "percentOfPool": 9 },
    { "id": "chat", "displayName": "Chat", "percentOfPool": 1 }
  ],
  "extraCredits": 0
}
```

Also accepted:

- Nested wrappers (`usage`, `data`, `billing`, …)
- `byProduct` / `productUsage` maps
- CLI shape: `monthlyLimit.val`, `usage.totalUsed.val`, `billingCycle.billingPeriodEnd`

When only an overall percent is available, the UI synthesizes a single **Grok Build** segment so the segmented bar still renders.

## Discovery helper

`UsageEndpointProbe.probe(cookieHeader:bearerToken:)` hits REST + gRPC billing + daily-candidate URLs and returns status / content-type / preview for debugging after a live sign-in.

`UsageEndpointProbe.probeWithFieldDump(...)` additionally returns a `GetGrokCreditsConfig` protobuf path dump via `GRPCWebParser.debugFieldDump`.

Prefer documenting any newly observed schema here when xAI changes payloads.

## Fixture

`GrokMonitor/Fixtures/usage_fixture.json` mirrors the reference UI numbers for offline previews and tests.
