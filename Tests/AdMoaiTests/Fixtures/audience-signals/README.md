# Audience signals catalog (vendored)

`catalog.generated.json` is a byte-for-byte copy of
`ui/platform/lib/audience-signals/catalog.generated.json` in admoai/adhub (generated from
`catalog.ts`, the single source of the Standard audience catalog). Vendored at adhub
`1df3c5812`.

`AudienceSignalsCatalogTests` fails when the SDK's typed enums drift from it. To update after a
catalog change in adhub:

```sh
gh api repos/admoai/adhub/contents/ui/platform/lib/audience-signals/catalog.generated.json \
  -H "Accept: application/vnd.github.raw" > Tests/AdMoaiTests/Fixtures/audience-signals/catalog.generated.json
swift test --filter AudienceSignalsCatalogTests
```
