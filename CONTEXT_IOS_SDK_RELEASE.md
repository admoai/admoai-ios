# Admoai iOS SDK — v1.4.0 Release Context

**Date**: 2026-05-27  
**Author**: Matias Vial (matias@admoai.com)  
**Branch**: `release/1.4.0` → merged via PR #22  
**Repo**: `/Users/matias-admoai/Documents/repos/admoai-ios`

---

## Purpose of this document

This document captures the full context of the iOS SDK v1.4.0 release session. The same exercise should next be applied to the **Android SDK** at `/Users/matias-admoai/Documents/repos/admoai-android`.

Reference documents for prior work:
- Flutter v0.3.0: `/Users/matias-admoai/Downloads/SDK_RELEASE_CONTEXT.md`
- Android (pre-iOS session): `CONTEXT_SDK_EQUIVALENCE.md` in this repo

---

## Starting state

`release/1.4.0` existed with a CHANGELOG that described 5 features as done — but **none of them were actually implemented in the code**. The branch was 2 commits ahead of `main` (a version bump and a CHANGELOG update), with the implementation missing entirely.

`main` was at `e9bf2d8` (OM verification models, v1.3.0 base).

PRs #17–#21 show as MERGED in GitHub, but they were merged into `release/1.4.0` (not into `main`). Their code was not present on the branch — only the CHANGELOG reflected their intent.

---

## What was found and fixed

### Bug 1 — `SDK_VERSION` not wired (`Configs.swift`)

`Configs.swift` computed the version from `Bundle.infoDictionary?["CFBundleShortVersionString"]`, which returns `nil` in Swift Package Manager contexts → `User-Agent: AdMoaiSDK/Unknown`.

`Version.swift` already had `internal let SDK_VERSION = "1.4.0"` but was never referenced.

**Fix**: Replace the computed property with a direct reference to `SDK_VERSION`.

```swift
// Before (wrong):
private static let sdkVersion: String = {
    Bundle(for: AdMoaiClient.self).infoDictionary?["CFBundleShortVersionString"] as? String
        ?? "Unknown"
}()
configuration.httpAdditionalHeaders = ["User-Agent": "AdMoaiSDK/\(sdkVersion)"]

// After (correct):
configuration.httpAdditionalHeaders = ["User-Agent": "AdMoaiSDK/\(SDK_VERSION)"]
```

### Bug 2 — `userConfig` silently ignored in `AdMoai.init`

```swift
// Before (wrong):
self.userConfig = .clear()   // parameter was always discarded

// After (correct):
self.userConfig = userConfig ?? .clear()
```

### Bug 3 — `fireTracking` sent no explicit headers

`fireTracking(url:)` used `session.dataTask(with: url)` (bare `URL`). The session's `httpAdditionalHeaders` carries `User-Agent` automatically, but `Accept-Language` and `X-Decision-Version` were never set on tracking requests.

**Fix**: Build a `URLRequest` explicitly:

```swift
// Before:
session.dataTask(with: url).resume()

// After:
var request = URLRequest(url: parsedURL)
if let defaultLanguage = config.defaultLanguage {
    request.setValue(defaultLanguage, forHTTPHeaderField: "Accept-Language")
}
if let apiVersion = config.apiVersion {
    request.setValue(apiVersion, forHTTPHeaderField: "X-Decision-Version")
}
session.dataTask(with: request).resume()
```

### Feature 1 — `Priority` enum (`DecisionResponse.swift`)

`Metadata.priority` was a raw `String`. Changed to a typed enum with a graceful unknown fallback:

```swift
public enum Priority: String, Decodable {
    case house = "house"
    case sponsorship = "sponsorship"
    case standard = "standard"
    case unknown = "unknown"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Priority(rawValue: raw) ?? .unknown  // never throws for unknown server values
    }
}
```

**Breaking change**: `Metadata.priority` type changed from `String` to `Priority`. Consumers must use enum cases or `.rawValue`.

### Feature 2 — `minConfidence` validation (`DecisionRequestBuilder.swift`)

`addDestinationTargeting` and `setDestinationTargeting` now throw when `minConfidence` is outside `[0.0, 1.0]`.

New error type:

```swift
public enum SDKError: Error, CustomStringConvertible, Equatable {
    case invalidMinConfidence(Double)
}
```

**API change**: `addDestinationTargeting(latitude:longitude:minConfidence:)` is now `throws`. Call sites must use `try`.

```swift
// Usage:
let request = try builder
    .addDestinationTargeting(latitude: 72.51, longitude: 120.64, minConfidence: 0.5)
    .build()
```

---

## Commits (in order)

| Commit | Description |
|--------|-------------|
| `5f07af2` | fix: use SDK_VERSION constant in User-Agent header |
| `5464a41` | fix: userConfig ignored in init + tracking headers via URLRequest |
| `3b45c6f` | feat: Priority enum, Metadata.priority strongly typed (breaking) |
| `5cc5eed` | feat: minConfidence validation + SDKError type |
| `5c6fb5b` | test: comprehensive unit tests + live integration test suite |
| `9a98c14` | fix: correct mock URL (mock.api → api.mock) + isolate vastxml placement |
| `83c1716` | fix: vastxml_native_endcard key typo + no format requirement |
| `65f2cb5` | test: live Accept-Language end-to-end request |

---

## Mock API

```
Base URL:  https://api.mock.admoai.com
Auth:      none required
```

> ⚠️ The URL `https://mock.api.admoai.com` (subdomain order reversed) returns Cloudflare 526 SSL errors. Always use `https://api.mock.admoai.com`.

### Placement keys and requirements

| Key | Requires version header | Requires `format: .video` | Notes |
|-----|------------------------|--------------------------|-------|
| `json_none` | No | No | Native, JSON delivery |
| `vasttag_none` | No | No | Works without; can also use `format: .video` |
| `json_native_endcard` | No | No | Native with endcard |
| `vasttag_native_endcard` | No | No | VAST tag with native endcard |
| `home` | No | No | Standard native placement |
| `menu` | No | No | Standard native placement |
| `freeMinutes` | No | No | Standard native placement |
| `search` | No | No | Standard native placement |
| `vastxml_native_endcard` | **Yes** (`2025-11-01`) | **No** | VAST XML video + native endcard — returns 422 without version header; does NOT need `format: .video` |

---

## Live Integration Test Suite

File: `Tests/AdMoaiTests/LiveIntegrationTests.swift`

Tests use Apple's **Swift Testing** framework (`import Testing`, `@Test`). They require **Xcode** to run — `swift test` from CLI tools does not work (the Testing framework is not available without the full Xcode SDK).

```bash
# Run all tests (Xcode):
Cmd+U

# Run only live integration tests:
# Filter by "LiveIntegration" in the Xcode test navigator
```

### Test SDKs (fixtures)

```swift
// No API version, no language
let sdk = AdMoai(
    config: SDKConfig(baseUrl: "https://api.mock.admoai.com"),
    userConfig: UserConfig(id: "user_123", ip: "203.0.113.1",
                           timezone: "America/Santiago", consent: .init(gdpr: true))
)

// With API version
let sdkWithVersion = AdMoai(
    config: SDKConfig(baseUrl: "https://api.mock.admoai.com", apiVersion: "2025-11-01"),
    userConfig: ...same...
)

// With API version + language
let sdkWithLanguage = AdMoai(
    config: SDKConfig(baseUrl: "https://api.mock.admoai.com",
                      apiVersion: "2025-11-01", defaultLanguage: "en"),
    userConfig: ...same...
)
```

### Standard targeting payload (used in most live tests)

```
geo:         [2643743]
location:    [(27.92, -160.32)]
custom:      [{category: "sports"}]
```

### Live request matrix (26 total)

| Test | SDK | Placement(s) | Format | X-Decision-Version | Accept-Language | Count |
|------|-----|-------------|--------|--------------------|-----------------|-------|
| `testAllPlacementsWithoutAPIVersion` | `sdk` | 8 general | — | — | — | 8 |
| `testAllPlacementsWithAPIVersion` | `sdkWithVersion` | all 9 | — | `2025-11-01` | — | 9 |
| `testAcceptLanguageHeaderLive` | `sdkWithLanguage` | `home` | — | `2025-11-01` | `en` | 1 |
| `testHomePlacementResponseStructure` | `sdk` | `home` | — | — | — | 1 |
| `testMultiPlacementRequest` | `sdk` | `home`+`menu` | — | — | — | 1 |
| `testVastXmlPlacementWithAPIVersion` | `sdkWithVersion` | `vastxml_native_endcard` | — | `2025-11-01` | — | 1 |
| `testVideoFormatExplicitRequest` | `sdkWithVersion` | `vasttag_none` | `video` | `2025-11-01` | — | 1 |
| `testDestinationTargetingRoundTrip` | `sdk` | `search` | — | — | — | 1 |
| `testDestinationTargetingBoundaryValuesAccepted` | `sdk` | `search` | — | — | — | 1 |
| `testInvalidPlacementReturns422` | `sdk` | `this_placement_does_not_exist_xyz_abc` | — | — | — | 1 |
| `testPriorityDecodesFromLiveResponse` | `sdk` | `home` | — | — | — | 1 |

### Non-live sections (no network)

- **§1 Serialisation**: `min_confidence` snake_case key, format omission when nil, `format: .video` encoding, userConfig propagation, SDK_VERSION validity
- **§2 Headers** (via `getHttpRequest()`): `User-Agent`, `Accept-Language`, `X-Decision-Version`, `Content-Type`, `Accept`
- **§6 network error**: invalid base URL → `APIError.networkError` (never reaches server)
- **§8 Tracking**: fire-and-forget methods don't crash; header config is wired

---

## SDK Architecture (iOS-specific)

### Headers per request type

| Header | Decision requests | Tracking requests |
|--------|-------------------|-------------------|
| `User-Agent: AdMoaiSDK/{version}` | ✅ session-level | ✅ session-level |
| `Content-Type: application/json` | ✅ explicit | — |
| `Accept: application/json` | ✅ explicit | — |
| `Accept-Language: {lang}` | ✅ explicit (if configured) | ✅ explicit (if configured) |
| `X-Decision-Version: {version}` | ✅ explicit (if configured) | ✅ explicit (if configured) |

### File structure

```
Sources/AdMoai/
├── AdMoai.swift                        # Public struct: init, config setters, fire* methods
├── APIClient.swift                     # Internal HTTP client, error types, HTTPRequest
├── Configs.swift                       # SDKConfig, AppConfig, DeviceConfig, UserConfig
├── Version.swift                       # internal let SDK_VERSION = "1.4.0"
├── Models/
│   ├── DecisionRequest.swift           # Placement, Targeting, User, Device, App, Format
│   ├── DecisionRequestBuilder.swift    # Fluent builder + SDKError
│   └── DecisionResponse.swift         # Decision, Creative, Content, Metadata, Priority,
│                                      # Tracking, TrackingItem, Advertiser, VastData, etc.
└── Utils/
    ├── AnyCodable.swift
    ├── AppDetails.swift
    ├── DeviceDetails.swift
    ├── OMHelper.swift                  # Creative extensions: hasOMVerification(), getVerificationResources()
    └── VideoHelper.swift              # Creative extensions: isVastTagDelivery(), getVastTagUrl(), etc.

Tests/AdMoaiTests/
├── AdMoaiTests.swift                  # SDK init, config management, SDK_VERSION assertions
├── DecisionRequestTests.swift         # Builder, targeting, serialisation, Priority enum
├── OMVerificationTests.swift          # OM resource decoding, full response deserialization
└── LiveIntegrationTests.swift         # 26 live HTTP requests (NEW in v1.4.0)
```

### Error types

```swift
// Pre-request (builder-level):
SDKError.invalidMinConfidence(Double)

// Network / response:
APIError.invalidURL
APIError.networkError(Error)
APIError.decodingError(Error)
APIError.invalidResponse
APIError.serverError(Int)           // 5xx
APIError.validationError([AdMoaiError])  // 422 with structured errors
APIError.clientError(HTTPStatus)    // 400, 404, 405, 410, 429
APIError.unexpectedStatusCode(Int)
```

### DEBUG vs RELEASE behaviour

In `DEBUG` builds, the `APIClient` accepts HTTP 200–499 and returns them as decoded responses (useful for inspecting 422 bodies). In `RELEASE` builds, 422 throws `.validationError`, 4xx throws `.clientError`, etc.

---

## Feature parity status after v1.4.0

| Feature | Flutter | Android | iOS |
|---------|---------|---------|-----|
| User-Agent on all requests | ✅ | ✅ | ✅ |
| Accept-Language on decision | ✅ | ✅ | ✅ |
| Accept-Language on tracking | ✅ | ✅ | ✅ |
| X-Decision-Version on decision | ✅ | ✅ | ✅ |
| X-Decision-Version on tracking | ✅ | ✅ | ✅ |
| `minConfidence` validation | ✅ | ✅ | ✅ |
| `Metadata.priority` typed enum | ✅ `MetadataPriority` | ✅ `MetadataPriority` | ✅ `Priority` |
| Destination targeting dedup | ✅ | ✅ | ✅ |
| Location targeting dedup | ✅ | ✅ | ✅ |
| OM verification | ✅ | ✅ | ✅ |
| Video ad support (VAST tag/XML) | ✅ | ✅ | ✅ |
| Live integration tests | ✅ | ⚠️ (see below) | ✅ |

---

## Android SDK — known gaps going into this session

From `CONTEXT_SDK_EQUIVALENCE.md`, Android had all of the above features implemented via PRs #27, #39–#47. The one thing to check for Android is whether a **live integration test suite** equivalent to Flutter's `test/integration_live_test.dart` and iOS's `LiveIntegrationTests.swift` exists.

If not, the primary task for the Android session is to create one. Use the same fixture values:

```
Base URL:    https://api.mock.admoai.com
Placements: json_none, vasttag_none, vastxml_native_endcard,
            json_native_endcard, vasttag_native_endcard,
            home, menu, freeMinutes, search
API version: 2025-11-01
User:        id=user_123, ip=203.0.113.1, timezone=America/Santiago, gdpr=true
Targeting:   geo=[2643743], location=(27.92, -160.32),
             destination=(72.51, 120.64, minConfidence=0.50),
             custom=[{category: sports}]
```

The `vastxml_native_endcard` placement requires `X-Decision-Version: 2025-11-01` but does **not** require an explicit `format=video` in the request body.

---

## Conversation transcript

Full JSONL transcript for deeper context:
`/Users/matias-admoai/.claude/projects/-Users-matias-admoai-Documents-repos-admoai-ios/`
