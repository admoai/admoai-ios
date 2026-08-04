#!/usr/bin/env bash
#
# Runs the Journey Ads live E2E suite against a locally-running decision-engine and exits with
# the same contract as the Android and Flutter runners:
#
#   0  pass (a documented SKIP is allowed)
#   1  a scenario FAILED
#   2  preflight aborted — the environment is unusable, not the SDK
#
# The runner is an `.executableTarget`, so it owns its own exit code directly — no report
# post-processing is needed to recover it. The report at build/journey-e2e/report.json is still
# written on every run, so a later round can diff scenario-by-scenario after an engine change
# instead of re-reading console output.
#
# Usage:
#   Tools/journey_e2e.sh
#   ADMOAI_JOURNEY_E2E_BASE_URL=http://127.0.0.1:8080 Tools/journey_e2e.sh
#
# Environment:
#   ADMOAI_JOURNEY_E2E_BASE_URL  default http://127.0.0.1:8080
#   ADMOAI_JOURNEY_E2E_VERSION   default 2025-11-01
#   DEVELOPER_DIR                set automatically to the Xcode toolchain if one is present
#
# Requires the engine reachable on the Journey-capable API version, Statsig
# `is_journey_ads_enabled = true` (default OFF), Redis up, a 32-char TRACKING_KEY, mock seeds
# loaded, and VAST env vars for the video scenarios.

set -uo pipefail

cd "$(dirname "$0")/.."

# CommandLineTools ships no swift-testing and an older toolchain; the full Xcode one is what CI
# uses and what the package expects. Only set it if the caller has not.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

REPORT="build/journey-e2e/report.json"
rm -f "$REPORT"

swift run journey-e2e
exit_code=$?

if [[ ! -f "$REPORT" ]]; then
  echo ""
  echo "FATAL: the runner produced no report at $REPORT."
  echo "       It likely failed to build or crashed before writing one."
  echo "       swift run exited $exit_code."
  # A crash before the report is an unusable run, not a clean pass — never report it as green.
  [[ "$exit_code" == "0" ]] && exit 2
fi

exit "$exit_code"
