#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
OUT="$ROOT/.build/manual"
mkdir -p "$OUT"

swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -parse-as-library \
  -o "$OUT/CoreTests" \
  "$ROOT/GrokUsage/Features/Usage/UsageModels.swift" \
  "$ROOT/GrokUsage/Features/Usage/UsageClient.swift" \
  "$ROOT/GrokUsage/Features/Usage/DailyUsageBuilder.swift" \
  "$ROOT/GrokUsage/Features/History/ExportService.swift" \
  "$ROOT/Tests/Manual/CoreTestsMain.swift"

"$OUT/CoreTests"
