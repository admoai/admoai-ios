#!/usr/bin/env bash
#
# The shared SDK scenario manifest is vendored, not authored, here. Its source is
# adhub's sdk/scenarios/, published as the npm package @admoai/sdk-scenarios; this repo
# carries one published version of its scenarios.json, and MANIFEST_VERSION beside it
# names which. The same file ships in admoai-ios, admoai-android and admoai-flutter.
#
# Usage:
#   .github/scripts/scenarios.sh check <manifest>
#       Fails when <manifest> is not byte-identical to the scenarios.json of the version
#       MANIFEST_VERSION names — an edit made in this repo instead of in adhub. Warns
#       when a newer version is published. Run by CI on every pull request.
#   .github/scripts/scenarios.sh adopt <manifest> <version|latest>
#       Replaces <manifest> with that published version's scenarios.json and writes
#       MANIFEST_VERSION. How a new version is taken: by hand, or by adhub's bump bot.
#
# Exit: 0 ok (warnings included), 1 drift or bad input, 2 the registry could not be read.
#
# Network: this script is the only part of the SDK's CI that reads the registry, and only
# over HTTPS (redirects included). The test suites never do — they read the vendored
# file, which is why it is vendored.
set -euo pipefail

registry="${SCENARIOS_REGISTRY:-https://registry.npmjs.org}"
package="@admoai/sdk-scenarios"

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 1; }
[ $# -ge 2 ] || usage
cmd="$1"; manifest="$2"
version_file="$(dirname "$manifest")/MANIFEST_VERSION"
case "$registry" in https://*) ;; *) echo "SCENARIOS_REGISTRY must be an https:// URL, got '$registry'" >&2; exit 1 ;; esac

fetch() { curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 "$@"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The published version's scenarios.json, into $tmp/package/scenarios.json.
download() { # version
  local v="$1"
  if ! fetch -o "$tmp/pkg.tgz" "$registry/$package/-/sdk-scenarios-$v.tgz"; then
    echo "cannot download $package@$v from $registry (is $v published?)" >&2
    exit 2
  fi
  tar -xzf "$tmp/pkg.tgz" -C "$tmp" package/scenarios.json
}

latest() {
  local meta
  meta="$(fetch "$registry/$package")" || { echo "cannot read $registry/$package" >&2; exit 2; }
  printf '%s' "$meta" | python3 -c 'import json, sys; print(json.load(sys.stdin)["dist-tags"]["latest"])'
}

# sort -V orders 1.10.0 after 1.9.0; true when $1 is strictly older than $2.
older() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }

case "$cmd" in
  check)
    [ -f "$manifest" ] || { echo "no manifest at $manifest" >&2; exit 1; }
    [ -f "$version_file" ] || { echo "no $version_file: name the $package version $manifest vendors" >&2; exit 1; }
    version="$(tr -d '[:space:]' < "$version_file")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$version_file holds '$version', not a MAJOR.MINOR.PATCH version" >&2; exit 1; }
    download "$version"
    if ! cmp -s "$tmp/package/scenarios.json" "$manifest"; then
      echo "::error file=$manifest::$manifest is not $package@$version. Scenarios are changed in adhub (sdk/scenarios), published, then adopted here with: .github/scripts/scenarios.sh adopt $manifest <version>"
      exit 1
    fi
    echo "✓ $manifest is $package@$version, byte for byte"
    newest="$(latest)"
    if older "$version" "$newest"; then
      echo "::warning file=$version_file::$package@$newest is published; this repo vendors $version. Adopt it with: .github/scripts/scenarios.sh adopt $manifest $newest"
    fi
    ;;
  adopt)
    [ $# -eq 3 ] || usage
    version="$3"
    [ "$version" = latest ] && version="$(latest)"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "'$version' is not a MAJOR.MINOR.PATCH version" >&2; exit 1; }
    download "$version"
    cp "$tmp/package/scenarios.json" "$manifest"
    printf '%s\n' "$version" > "$version_file"
    echo "✓ $manifest is now $package@$version ($version_file updated); run the e2e suite against an engine before merging"
    ;;
  *) usage ;;
esac
