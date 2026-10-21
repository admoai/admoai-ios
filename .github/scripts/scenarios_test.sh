#!/usr/bin/env bash
#
# Hermetic tests for scenarios.sh: a fake `curl` serves a local "registry" with two
# published versions, so nothing touches the network. Run by CI next to the check.
#
#   .github/scripts/scenarios_test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
passed=0; failed=0
pass() { echo "ok:   $case_name"; passed=$((passed + 1)); }
fail() { echo "FAIL: $case_name ($1)"; sed 's/^/    | /' "$tmp/out"; failed=$((failed + 1)); }

# The registry: $tmp/reg/<path after the registry URL>.
reg="$tmp/reg/@admoai/sdk-scenarios"
mkdir -p "$reg/-"
publish() { # version content
  local d="$tmp/build/$1/package"; mkdir -p "$d"; printf '%s' "$2" > "$d/scenarios.json"
  tar -czf "$reg/-/sdk-scenarios-$1.tgz" -C "$tmp/build/$1" package
}
publish 1.0.0 '{"v":1}'
publish 1.1.0 '{"v":11}'
printf '{"dist-tags":{"latest":"1.1.0"}}' > "$reg/index"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<EOF
#!/usr/bin/env bash
out=""; url=""
while [ \$# -gt 0 ]; do
  case "\$1" in -o) out="\$2"; shift 2 ;; https://*) url="\$1"; shift ;; *) shift ;; esac
done
path="\${url#https://registry.test/}"
f="$tmp/reg/\$path"; [ -d "\$f" ] && f="\$f/index"
[ -f "\$f" ] || exit 22
if [ -n "\$out" ]; then cp "\$f" "\$out"; else cat "\$f"; fi
EOF
chmod +x "$tmp/bin/curl"

run() {
  set +e
  PATH="$tmp/bin:$PATH" SCENARIOS_REGISTRY=https://registry.test "$here/scenarios.sh" "$@" > "$tmp/out" 2>&1
  status=$?
  set -e
}
has() { grep -qF -- "$1" "$tmp/out"; }
m="$tmp/repo/scenarios.json"; mkdir -p "$tmp/repo"

case_name="the vendored bytes of the named version pass, and a newer version is a warning"
printf '{"v":1}' > "$m"; echo 1.0.0 > "$tmp/repo/MANIFEST_VERSION"; run check "$m"
if [ $status -eq 0 ] && has "is @admoai/sdk-scenarios@1.0.0, byte for byte" && has "::warning" && has "@1.1.0 is published"; then pass; else fail "status=$status"; fi

case_name="the latest version passes with no warning"
printf '{"v":11}' > "$m"; echo 1.1.0 > "$tmp/repo/MANIFEST_VERSION"; run check "$m"
if [ $status -eq 0 ] && ! has "::warning"; then pass; else fail "status=$status"; fi

case_name="a manifest edited in this repo fails, naming adhub as the place to change it"
printf '{"v":11,"edited":true}' > "$m"; run check "$m"
if [ $status -eq 1 ] && has "::error" && has "changed in adhub"; then pass; else fail "status=$status"; fi

case_name="a version that was never published is a registry error (2), not a pass"
printf '{"v":11}' > "$m"; echo 9.9.9 > "$tmp/repo/MANIFEST_VERSION"; run check "$m"
if [ $status -eq 2 ] && has "cannot download"; then pass; else fail "status=$status"; fi

case_name="a missing or malformed MANIFEST_VERSION fails"
rm "$tmp/repo/MANIFEST_VERSION"; run check "$m"; s1=$status
echo "v1" > "$tmp/repo/MANIFEST_VERSION"; run check "$m"
if [ $s1 -eq 1 ] && [ $status -eq 1 ] && has "not a MAJOR.MINOR.PATCH"; then pass; else fail "status=$s1/$status"; fi

case_name="adopt latest writes the published bytes and the version, and check then passes"
printf 'old' > "$m"; run adopt "$m" latest
adopted="$(cat "$m")"; ver="$(cat "$tmp/repo/MANIFEST_VERSION")"; run check "$m"
if [ "$adopted" = '{"v":11}' ] && [ "$ver" = 1.1.0 ] && [ $status -eq 0 ]; then pass; else fail "adopted=$adopted ver=$ver"; fi

case_name="a plain-http registry is refused"
set +e; SCENARIOS_REGISTRY=http://registry.test "$here/scenarios.sh" check "$m" > "$tmp/out" 2>&1; status=$?; set -e
if [ $status -eq 1 ] && has "must be an https:// URL"; then pass; else fail "status=$status"; fi

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
