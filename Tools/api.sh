#!/usr/bin/env bash
#
# The AdMoai module's public API baseline, api/AdMoai.api.txt (see Tools/api_render.py).
#
# Usage:
#   Tools/api.sh           regenerate it — run after an intended API change and commit it
#   Tools/api.sh --check   what CI runs: fail when the code's API differs from the baseline,
#                          and classify the difference against the merge base
#
# The gate is the committed file, so every API change is a diff a reviewer reads in the PR.
# The classification is `swift package diagnose-api-breaking-changes <merge base>`:
# informative, never the gate.
#
# The compiler spells declarations, so the baseline is generated with the Xcode CI pins
# (XCODE_API_VERSION in .github/workflows/ci.yml). With a different local Xcode, take
# api/AdMoai.api.txt from the failing run's `api-baseline` artifact instead.
set -euo pipefail

cd "$(dirname "$0")/.."

# CommandLineTools has no symbol-graph support for packages; the full Xcode does.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swift package dump-symbol-graph --minimum-access-level public --skip-synthesized-members > "$tmp/dump.log" 2>&1 \
  || { cat "$tmp/dump.log"; exit 2; }
graphs="$(sed -n 's/^Files written to //p' "$tmp/dump.log" | tail -1)"
python3 Tools/api_render.py "$graphs" "$tmp/AdMoai.api.txt"
count="$(grep -vc '^#' "$tmp/AdMoai.api.txt")"

if [[ "${1:-}" != "--check" ]]; then
  mkdir -p api
  cp "$tmp/AdMoai.api.txt" api/AdMoai.api.txt
  echo "api/AdMoai.api.txt regenerated: $count public symbols"
  exit 0
fi

if diff -u api/AdMoai.api.txt "$tmp/AdMoai.api.txt" > "$tmp/api.diff"; then
  echo "✓ the public API matches api/AdMoai.api.txt ($count symbols)"
  exit 0
fi

mkdir -p build/api && cp "$tmp/AdMoai.api.txt" build/api/AdMoai.api.txt
echo "✗ the public API changed and api/AdMoai.api.txt was not regenerated:"
echo
cat "$tmp/api.diff"
echo
if base="$(git merge-base HEAD origin/main 2>/dev/null)"; then
  echo "Classification against the merge base (${base:0:7}):"
  swift package diagnose-api-breaking-changes "$base" --products AdMoai 2>&1 \
    | grep -E "breaking change|API breakage|💔" | tee "$tmp/report.txt" || true
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -s "$tmp/report.txt" ]]; then
    { echo '### Public API changes'; echo '```'; cat "$tmp/report.txt"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
  fi
fi
echo
echo "Fix: run Tools/api.sh (or take build/api/AdMoai.api.txt) and commit api/AdMoai.api.txt."
echo "If any line was removed or changed, the change is breaking: see CONTRIBUTING."
exit 1
