# Admoai Android SDK — Cross-SDK Equivalence Initiative

**Date**: 2026-05-20  
**Author**: Matias Vial (matias@admoai.com)  
**Branch context**: All PRs open, not merged. User reviews individually.

---

## Overview

This document captures the full context of the cross-SDK equivalence initiative for the Admoai Android SDK. The goal was to bring Android to feature parity with iOS and Flutter (after Flutter PRs #22–#30 / v0.3.0).

The same exercise should next be applied to the iOS SDK at `/Users/matias-admoai/Documents/repos/admoai-ios`.

---

## Flutter PRs That Drove This Initiative

Flutter was leveled up first (PRs #22–#30 on `admoai/admoai-flutter`):

| PR | Feature |
|----|---------|
| #22 | `defaultLanguage` / `Accept-Language` header |
| #23 | Network timeouts (request, connect, socket) |
| #24 | Video format support |
| #25 | Destination targeting + `minConfidence` validation |
| #26 | Video metadata fields |
| #27 | OM (Open Measurement) verification |
| #28 | Response model hardening (nullable fields) |
| #29 | Typed errors |
| #30 | User-Agent header on all requests |

---

## Android PRs Created

All PRs are open and unmerged. Review in order:

| PR | Branch | Feature |
|----|--------|---------|
| #48 | `fix/nullable-metadata-ktor3-test` | Fix `metadata.priority` NPE in Ktor3IntegrationTest |
| #27 | `feat/api-version-header` | `X-Decision-Version` header on decision requests |
| #39 | `feat/user-agent-header` | User-Agent: `AdMoaiSDK/{version}` on all requests |
| #40 | `feat/accept-language-header` | `Accept-Language` header on decision requests |
| #41 | `feat/response-model-hardening` | `Advertiser.id` nullable; `TrackingInfo` helper extensions |
| #42 | `feat/content-list-extensions` | `List<Content>` helper extensions |
| #43 | `feat/request-builder-clear-methods` | 8 clear methods on `DecisionRequestBuilder` |
| #44 | `feat/fire-and-forget-tracking` | Fire methods return `Unit`, fire-and-forget via `sdkScope` |
| #45 | `feat/accept-language-tracking` | `Accept-Language` header on tracking requests |
| #46 | `feat/location-targeting-dedup` | Dedup location targets by `(lat, lng)` |
| #47 | `feat/destination-min-confidence-validation` | `minConfidence` range validation `[0.0..1.0]` |
| #50 | `test/sdk-integration-coverage` | End-to-end integration test suite (MockWebServer) |
| #51 | `test/consumer-validation` | Consumer-perspective BDD tests in sample module |

---

## Key Technical Decisions

### Fire-and-Forget Tracking

Fire methods (`fireImpression`, `fireClick`, `fireCustomEvent`, `fireVideoEvent`, `fireTracking`) changed from `Flow<Unit>` to `Unit`. Network calls happen on `sdkScope` (a `CoroutineScope` with `SupervisorJob`).

Critical rule: `CancellationException` must **never** be swallowed:
```kotlin
fun fireTracking(url: String) {
    val currentApiService = apiService ?: return
    sdkScope.launch {
        try {
            currentApiService.fireTrackingUrl(url).collect {}
        } catch (e: CancellationException) {
            throw e  // MUST rethrow — cooperative cancellation contract
        } catch (_: Exception) {
            // fire-and-forget: network failures never propagate to caller
        }
    }
}
```

### Test Injection Pattern

`sdkScope` is `@VisibleForTesting internal var` to allow injecting `UnconfinedTestDispatcher` in tests:
```kotlin
runTest(UnconfinedTestDispatcher()) {
    admoaiInstance.sdkScope = this
    admoaiInstance.fireImpression(trackingInfo)
    // background launch runs synchronously under UnconfinedTestDispatcher
    coVerify { mockApiService.fireTrackingUrl(any()) }
}
```

MockWebServer integration tests use `server.takeRequest(3, TimeUnit.SECONDS)` to block until the background HTTP request arrives.

### Version Constant

`sdk/src/main/kotlin/com/admoai/sdk/Version.kt`:
```kotlin
package com.admoai.sdk
internal const val SDK_VERSION = "1.3.0"
```
Note: `build.gradle.kts` still shows `"1.1.2"` — update this when cutting the release.

---

## Bug Found During Review

**`CancellationException` swallowed by `catch (_: Exception)`** — present in PRs #44, #50, #51.

This violates Kotlin coroutines cooperative cancellation. All three branches were fixed before this document was written. Fix: add `catch (e: CancellationException) { throw e }` before the general catch, plus `import kotlinx.coroutines.CancellationException`.

---

## Final Review Status

| PR | Status |
|----|--------|
| #48 | ✅ Clean |
| #27 | ✅ Clean |
| #39 | ✅ Clean |
| #40 | ✅ Clean |
| #41 | ✅ Clean |
| #42 | ✅ Clean |
| #43 | ✅ Clean |
| #44 | ✅ Fixed (CancellationException) |
| #45 | ✅ Clean |
| #46 | ✅ Clean |
| #47 | ✅ Clean |
| #50 | ✅ Fixed (CancellationException) |
| #51 | ✅ Fixed (CancellationException) |

---

## iOS SDK — Known Gaps (Next Exercise)

Compare iOS against Flutter v0.3.0 and Android post-fix state. Suspected gaps based on earlier analysis:

| Feature | Flutter | Android | iOS |
|---------|---------|---------|-----|
| User-Agent on tracking | ✅ | ✅ | ⚠️ session-level only, no explicit header |
| Accept-Language on tracking | ✅ | ✅ | ❌ plain `dataTask(with: url)` — no headers |
| X-Decision-Version on tracking | ✅ | ✅ | ❌ same |
| `minConfidence` validation | ✅ | ✅ | ❌ no validation |
| `Metadata.priority` typed enum | ✅ | ✅ `MetadataPriority` | ❌ raw `String` |

iOS `fireTracking` current implementation (`AdMoai.swift`):
```swift
public func fireTracking(url: String) {
    guard let url = URL(string: url) else { return }
    session.dataTask(with: url).resume()  // no explicit headers
}
```
To add `Accept-Language` and `X-Decision-Version`, needs a `URLRequest` instead of plain URL.

Repo: `/Users/matias-admoai/Documents/repos/admoai-ios`

---

## Conversation Transcript

Full JSONL transcript for deeper context:
`/Users/matias-admoai/.claude/projects/-Users-matias-admoai-Documents-repos-admoai-android/5aafecbb-e57a-428b-8692-07a8701654ef.jsonl`
