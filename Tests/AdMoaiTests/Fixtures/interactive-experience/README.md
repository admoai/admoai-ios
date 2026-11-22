# Interactive experience contract (vendored)

`standard-fields.json` and `decision/*.json` are byte-for-byte copies of the interactive
experience contract pack in admoai/adhub, `shared/interactiveexperience/contract/` (decision D13,
issue #7127): the seven standard contact keys and the decision request and per-creative
descriptor fixtures. Identical to adhub main at `b1e28e23d` (the pack merged with #7127 and
#7170).

`bridge-messages.json`, `error-codes.json` and `bridge/**` (the bridge fixtures, from
`fixtures/bridge/**`) are vendored the same way, also identical to adhub main at `60e9994b1`
(#7170 merged: `bridgeVersion`, `submitting`, `submit_failed`, `back`). `bridge/context.json` is
the identity the SDK minted for one controller; `bridge/invalid/**` are messages that must be
refused. `bridge/tolerated/**` are prefill entries the form drops while still answering
`prefill_applied` (adhub #7299 and #7321, which adds a `__proto__` key; outcome in each
`.outcome.json`); the SDK never sends them either.
`LeadFormBridgeTests` asserts the SDK's table equals
`bridge-messages.json` with no exceptions.

`InteractiveExperienceTests` fails when the SDK drifts from them: the typed keys must be the
catalog's `prefillKeys` in order, the request extension must serialise to the fixture bodies, and
the descriptor fixture must decode. To update after a contract change in adhub:

```sh
for f in standard-fields.json fixtures/decision/creative-descriptor.json \
  fixtures/decision/request-malformed-shape.json fixtures/decision/request-omitted.json \
  fixtures/decision/request-supported-empty-keys.json \
  fixtures/decision/request-supported-with-keys.json fixtures/decision/request-unknown-key.json \
  bridge-messages.json error-codes.json; do
  gh api "repos/admoai/adhub/contents/shared/interactiveexperience/contract/$f" \
    -H "Accept: application/vnd.github.raw" \
    > "Tests/AdMoaiTests/Fixtures/interactive-experience/${f#fixtures/}"
done
# fixtures/bridge/** (context.json, app-to-runtime, runtime-to-app, invalid/**) -> bridge/**,
# one file at a time with the same `gh api` call (list them with
# `gh api repos/admoai/adhub/contents/shared/interactiveexperience/contract/fixtures/bridge/<dir>`).
swift test --filter InteractiveExperienceTests --filter LeadFormBridgeTests
```
