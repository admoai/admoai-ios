# Admoai iOS SDK


The AdMoai iOS SDK is a lightweight wrapper around the Decision Engine API, enabling iOS applications to request, render, and track native and video advertisements with advanced targeting capabilities.

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-iOS%2014%2B%20%7C%20macOS%2011%2B-blue.svg)](https://developer.apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)


Admoai iOS SDK is a native advertising solution that enables seamless integration of ads into iOS applications. The SDK provides a robust API for requesting and displaying various ad formats with advanced targeting capabilities.
=======

## Features

- **Native Ads** – Multiple template types (wide, image+text, text-only, carousel)
- **Video Ads** – JSON, VAST Tag, and VAST XML delivery methods
- **Rich Targeting** – Geo, location, and custom key-value targeting
- **Format Filter** – Request native-only, video-only, or any format
- **User Consent** – GDPR compliance with consent management
- **Event Tracking** – Impressions, clicks, video quartiles, and custom events
- **SwiftUI Ready** – Native Swift async/await integration
- **Per-Request Control** – Override user/device data collection per request

## Requirements

- **iOS** 14.0+
- **Swift** 5.9+
- **Xcode** 15.0+

## Installation

### Swift Package Manager

#### Using Xcode UI

In Xcode, go to File > Add Package Dependencies, enter `https://github.com/admoai/admoai-ios.git` in the search field, select version, and click "Add Package".

#### Using Package.swift

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/admoai/admoai-ios.git", from: "1.1.0")
]
```

Then run `swift package resolve` to download and integrate the package.

---

## Quick Start

### 1. Initialize the SDK

```swift

// Initialize SDK with base URL and optional configurations
let config = SDKConfig(
    baseUrl: "https://api.admoai.com",
    apiVersion: "2025-11-01",        // Optional: enables format filter (for Video Ads)
    defaultLanguage: "en"            // Optional: default language for requests
)

var sdk = AdMoai(config: config)
```

### 2. Configure User Settings (Optional)

```swift
sdk.setUserConfig(
    id: "user_123",
    ip: "203.0.113.1",
    timezone: TimeZone.current.identifier,
    consent: User.Consent(gdpr: true)
)

// Device and app info are auto-populated by default
// You can also manually configure them:
sdk.setDeviceConfig(model: "iPhone", os: "iOS", osVersion: "17.0")
sdk.setAppConfig(name: "MyApp", version: "1.0.0")
```

### 3. Build and Send a Request

```swift
let request = sdk.createRequestBuilder()
    .addPlacement(key: "home", format: .native)
    .addPlacement(key: "promotions", format: .video)
    .addGeoTargeting(2643743)  // London
    .addCustomTargeting(key: "category", value: "news")
    .build()

// Request ads (async/await)
let response = try await sdk.requestAds(request)

response.body.data?.forEach { adData in
    adData.creatives?.forEach { creative in
        // Render creative
    }
}
```

### 4. Extract Content

```swift
let headline = creative.contents.getContent(key: "headline")?.value.description
let posterImage = creative.contents.getContent(key: "poster_image")?.value.description
let videoAsset = creative.contents.getContent(key: "video_asset")?.value.description
```

### 5. Track Events

```swift
// Impressions
sdk.fireImpression(tracking: creative.tracking)

// Clicks
sdk.fireClick(tracking: creative.tracking)

// Video quartiles
sdk.fireVideoEvent(tracking: creative.tracking, key: "start")           // 0%
sdk.fireVideoEvent(tracking: creative.tracking, key: "first_quartile")  // 25%
sdk.fireVideoEvent(tracking: creative.tracking, key: "midpoint")        // 50%
sdk.fireVideoEvent(tracking: creative.tracking, key: "third_quartile")  // 75%
sdk.fireVideoEvent(tracking: creative.tracking, key: "complete")        // 98%
sdk.fireVideoEvent(tracking: creative.tracking, key: "skip")            // on skip

// Custom events
sdk.fireCustom(tracking: creative.tracking, key: "companionOpened")
```

### 6. Clean Up on Logout

```swift
sdk.clearUserConfig()
sdk.clearDeviceConfig()
sdk.clearAppConfig()
```

---

## Configuration Reference

### SDKConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseUrl` | String | Required | Decision Engine API endpoint |
| `apiVersion` | String? | `nil` | API version (e.g., `"2025-11-01"` for format filter) |
| `defaultLanguage` | String? | `nil` | Default language for requests |
| `logger` | Logger | SDK default | Custom logger instance |
| `sessionConfiguration` | URLSessionConfiguration | SDK default | Custom URL session configuration |

### PlacementFormat

| Value | Description |
|-------|-------------|
| `.native` | Request native ads only |
| `.video` | Request video ads only |
| `nil` | Request any format (default, recommended) |

> **Note**: Format filter requires `apiVersion = "2025-11-01"` or later.

---

## Video Ad Support

The SDK supports three video delivery methods:

| Delivery | Response Field | Tracking |
|----------|----------------|----------|
| **JSON** | `video_asset` content key | SDK methods (`fireVideoEvent`) |
| **VAST Tag** | `vast.tagUrl` | IMA SDK automatic or manual HTTP |
| **VAST XML** | `vast.xmlBase64` | Manual HTTP GET |

### Detecting Video Ads

```swift
// Check delivery method
let isVideo = creative.delivery == "json" || 
              creative.delivery == "vast_tag" || 
              creative.delivery == "vast_xml"

// Or use helper methods
creative.isJsonDelivery()
creative.isVastTagDelivery()
creative.isVastXmlDelivery()

// Get video URL (JSON delivery)
let videoUrl = creative.contents.getContent(key: "video_asset")?.value.description

// Get VAST tag URL (with optional media type/delivery params)
let vastTagUrl = creative.getVastTagUrl()
let vastTagUrlWithParams = creative.getVastTagUrl(mediaType: "video/mp4", mediaDelivery: "progressive")

// Get VAST XML (Base64 encoded, with optional modifications)
let vastXmlBase64 = creative.getVastXmlBase64()
let vastXmlModified = creative.getVastXmlBase64(mediaType: "video/mp4", mediaDelivery: "streaming")
```


## Sample App

For a complete example implementation, check out the [demo app](Examples/Demo/README.md).

## Event Tracking
=======
### Video Tracking Events

**Important**: Always fire the **impression** event first when the ad is displayed, then fire video-specific events as playback progresses.

| Event | When to Fire | Key |
|-------|--------------|-----|
| **Impression** | Ad displayed (before playback) | `default` |
| Start | Video begins playing (0%) | `start` |
| First Quartile | 25% progress | `first_quartile` |
| Midpoint | 50% progress | `midpoint` |
| Third Quartile | 75% progress | `third_quartile` |
| Complete | Video ends (98%) | `complete` |
| Skip | User skips | `skip` |

**Manual tracking** works with any delivery method:

```swift
// 1. Fire impression first (when ad is displayed)
sdk.fireImpression(tracking: creative.tracking)

// 2. Fire video events as playback progresses
sdk.fireVideoEvent(tracking: creative.tracking, key: "start")
sdk.fireVideoEvent(tracking: creative.tracking, key: "first_quartile")
sdk.fireVideoEvent(tracking: creative.tracking, key: "midpoint")
sdk.fireVideoEvent(tracking: creative.tracking, key: "third_quartile")
sdk.fireVideoEvent(tracking: creative.tracking, key: "complete")
sdk.fireVideoEvent(tracking: creative.tracking, key: "skip")  // if user skips
```

- **JSON delivery**: Tracking URLs are in the response—easiest to use with SDK methods
- **VAST Tag/XML**: Requires fetching the tag URL or decoding Base64 XML to extract tracking URLs, then firing HTTP GET beacons manually

> **Tip**: For VAST-based ads, you may optionally integrate a third-party VAST SDK (e.g., Google IMA) for automatic tracking and Open Measurement (OM) viewability.

### Video Helper Methods

```swift
// Skippable ad detection
let isSkippable = creative.isSkippable()
let skipOffset = creative.getSkipOffset()  // e.g., "00:00:05" or "5"
```

---

## Event Tracking

The SDK fires tracking beacons via HTTP requests automatically.

### Available Methods

```swift
// Impressions (fired when ad is displayed)
sdk.fireImpression(tracking: trackingInfo, key: "default")

// Clicks (fired on user tap)
sdk.fireClick(tracking: trackingInfo, key: "default")

// Video events (JSON delivery only)
sdk.fireVideoEvent(tracking: trackingInfo, key: "start")

// Custom events
sdk.fireCustom(tracking: trackingInfo, key: "companionOpened")
```

### Tracking Keys

Each tracking type supports multiple keys. Use `"default"` for standard events or specify custom keys defined in your campaign configuration.

---

## Request Builder

The `DecisionRequestBuilder` provides a fluent API:

```swift
let request = sdk.createRequestBuilder()
    // Placements
    .addPlacement(key: "home")
    .addPlacement(key: "promotions", format: .video)
    
    // User overrides (per-request)
    .setUserId("user_123")
    .setUserIp("203.0.113.1")
    .setUserTimezone("America/New_York")
    .setUserConsent(User.Consent(gdpr: true))
    
    // Targeting
    .addGeoTargeting(2643743)
    .addLocationTargeting(latitude: 37.7749, longitude: -122.4194)
    .addCustomTargeting(key: "category", value: "news")
    
    // Data collection
    .disableAppCollection()
    .disableDeviceCollection()
    
    .build()
```

---

## Response Structure

```
APIResponse<DecisionResponse>
├── response: HTTPURLResponse
├── body: APIResponseBody<DecisionResponse>
│   ├── success: Bool
│   ├── data: [Decision]?
│   │   └── Decision
│   │       ├── placement: String
│   │       └── creatives: [Creative]?
│   │           └── Creative
│   │               ├── contents: [Content]         // Key-value pairs
│   │               ├── advertiser: Advertiser
│   │               ├── template: Template          // {key, style}
│   │               ├── tracking: Tracking          // Tracking URLs
│   │               ├── metadata: Metadata
│   │               ├── delivery: String            // "json", "vast_tag", "vast_xml"
│   │               └── vast: VastData?             // {tagUrl} or {xmlBase64}
│   ├── errors: [AdMoaiError]?
│   └── warnings: [AdMoaiWarning]?
└── rawBody: String?
```

---

## Default Configuration Helpers

Auto-populate device and app information:

```swift
// Reset to system defaults (auto-detected)
sdk.resetDeviceConfig()  // Device info (model, OS, manufacturer, etc.)
sdk.resetAppConfig()     // App info (name, version, identifier, etc.)

// Clear all config
sdk.clearDeviceConfig()
sdk.clearAppConfig()
```

---

## Thread Safety

The SDK is designed for concurrent use:

- Configuration changes are handled through struct value semantics
- All network calls use async/await with proper concurrency
- URLSession handles connection pooling automatically

---

## Open Measurement Integration

The Admoai SDK provides support for Open Measurement (OM) verification data, allowing publishers to integrate with third-party viewability and verification measurement providers, such as Integral Ad Science (IAS), DoubleVerify, Moat, and others.

### Accessing Verification Resources

Each creative may include Open Measurement verification script resources that contain the necessary data for third-party verification:

```swift
if let creative = decision.creatives?.first {
    // Check if the creative has OM verification data
    if creative.hasOMVerification() {
        // Get the verification resources
        if let verificationResources = creative.getVerificationResources() {
            for resource in verificationResources {
                print("Vendor: \(resource.vendorKey)")
                print("Script URL: \(resource.scriptUrl)")
                print("Parameters: \(resource.verificationParameters)")

                // Use these values with your third-party verification SDK
                // Example: IAS or DoubleVerify integration
            }
        }
    }
}
```

### Verification Script Resource Properties

Each `VerificationScriptResource` contains:

- **vendorKey**: The identifier for the verification vendor (e.g., "ias", "doubleverify")
- **scriptUrl**: The URL to the verification script that needs to be loaded
- **verificationParameters**: Additional parameters required for verification setup

### Integration Example

Here's a complete example of how to extract and use OM data:

```swift
func setupOMVerification(for creative: Creative) {
    guard creative.hasOMVerification(),
          let resources = creative.getVerificationResources() else {
        return
    }

    for resource in resources {
        // Extract OM data
        let vendorKey = resource.vendorKey
        let scriptUrl = resource.scriptUrl
        let parameters = resource.verificationParameters

        // Integrate with your chosen verification SDK
        // Example pseudocode:
        // if vendorKey == "ias" {
        //     IASSDK.setupVerification(scriptUrl: scriptUrl, parameters: parameters)
        // } else if vendorKey == "doubleverify" {
        //     DoubleVerifySDK.setupVerification(scriptUrl: scriptUrl, parameters: parameters)
        // }
    }
}
```

### Important Notice

> [!WARNING] 
> **OM Certification Notice**: The Admoai SDK provides Open Measurement verification data as received from the ad server, but **the SDK itself is not OM certified**. Publishers must ensure that their implementation with third-party verification providers (such as IAS or DoubleVerify) complies with Open Measurement standards and requirements. Admoai acts as a stict ad server only; publishers are responsible for the proper implementation of their OM integration.
=======
See the [Demo App](Examples/Demo/README.md) for complete integration examples demonstrating:

- Native ad templates
- Tracking implementation
- SwiftUI integration

---

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- How to submit Pull Requests
- Commit message conventions (Conventional Commits)
- Code style and testing requirements
- Development workflow

## Documentation

For detailed documentation, please visit:
- [API Documentation](https://docs.admoai.com)

---

## Support

- **Email**: support@admoai.com

=======
---

## License

Copyright 2025 Admoai Inc. All rights reserved.
=======
For detailed documentation, please visit the [SDK documentation](https://admoai.github.io/admoai-ios/documentation/admoai) or our [documentation site](https://docs.admoai.com).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
