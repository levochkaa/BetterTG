#!/usr/bin/env bash
# Runs the liquid lens's math tests (Tests/LiquidLens, ported from Telegram 13.2's LiquidLensTests) on the Mac:
# the flex, the motion plan and the move curves need no UIKit, and the app has no test target.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.build/liquid-lens-tests"
mkdir -p "$OUTPUT_DIR"

xcrun swiftc -swift-version 6 -O \
  -module-name LiquidLensTests \
  "$ROOT_DIR/BetterTG/Views/Common/LiquidLensFlex.swift" \
  "$ROOT_DIR/BetterTG/Views/Common/LiquidLensMotionPlan.swift" \
  "$ROOT_DIR/BetterTG/Views/Common/LiquidLensCurve.swift" \
  "$ROOT_DIR"/Tests/LiquidLens/*.swift \
  -o "$OUTPUT_DIR/LiquidLensTests"

"$OUTPUT_DIR/LiquidLensTests"
