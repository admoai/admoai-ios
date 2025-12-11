# Admoai iOS SDK

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-iOS%2014%2B%20%7C%20macOS%2011%2B-blue.svg)](https://developer.apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

Admoai iOS SDK is a native advertising solution that enables seamless integration of ads into iOS applications. The SDK provides a robust API for requesting and displaying various ad formats with advanced targeting capabilities.

## Features

- Native ad format support
- Rich targeting options (geo, location, custom)
- User consent management (GDPR)
- Flexible ad templates
- Companion ad support
- Carousel ad layouts
- Impression and click tracking
- Per-request data collection control

## Requirements

- iOS 14.0+
- Swift 5.9+

## Installation

### Swift Package Manager

#### Using Xcode UI

In Xcode, go to File > Add Package Dependencies, enter `https://github.com/admoai/admoai-ios.git` in the search field, select version, and click "Add Package".

#### Using Package.swift

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/admoai/admoai-ios.git", from: "0.1.0")
]
```

Then run `swift package resolve` to download and integrate the package.

## Quick Start

1. Initialize the SDK:

```swift
// Initialize SDK with base URL and optional configurations
let config = SDKConfig(baseUrl: "https://example.api.admoai.com")
let sdk = Admoai(config: config)

// Configure user settings globally
sdk.setUserConfig(
    id: "user_123",
    ip: "203.0.113.1",
    timezone: TimeZone.current.identifier,
    consent: User.Consent(gdpr: true)
)
```

2. Create and send an ad request:

```swift
// Build request with placement
let request = sdk.createRequestBuilder()
    .addPlacement(key: "home")
    .build()

// Request ads
let response = try await sdk.requestAds(request)
```

You can also build the request with targeting and user settings:

```swift
let request = sdk.createRequestBuilder()
    .addPlacement(key: "home")

    // Override user settings for this request
    .setUserId("different_user")
    .setUserIp("203.0.113.2")
    .setUserTimezone("America/New_York")
    .setUserConsent(User.Consent(gdpr: false))

    // Add targeting
    .addGeoTargeting(2643743)  // London
    .addLocationTargeting(latitude: 37.7749, longitude: -122.4194)
    .addCustomTargeting(key: "category", value: "news")

    // Build request
    .build()
```

3. Handle the creative:

```swift
if let decision = response.body.data?.first,
   let creative = decision.creatives?.first
{
    // Access creative properties
    let headline = creative.contents.getContent(key: "headline")?.value.description
    let imageUrl = creative.contents.getContent(key: "coverImage")?.value.description

    // Track impression
    sdk.fireImpression(tracking: creative.tracking)

    // Handle click with tracking
    if let clickUrl = creative.tracking.getClickUrl(key: "default"),
       let url = URL(string: clickUrl)
    {
        UIApplication.shared.open(url)
    }
}
```

4. Clean up on logout:

```swift
// Reset user configuration when user logs out
sdk.clearUserConfig()  // Resets to: id = nil, ip = nil, timezone = nil, consent.gdpr = false
```

## Sample App

For a complete example implementation, check out the [demo app](Examples/Demo/README.md).

## Event Tracking

The SDK automatically handles event tracking through URL sessions. Each creative contains tracking URLs for different events (impressions, clicks, custom events) that are called when triggered.

### Tracking Configuration

Each creative includes tracking configuration for different event types:

```swift
// Available tracking URLs in the creative
creative.tracking.impressions  // Array of impression tracking URLs
creative.tracking.clicks       // Array of click tracking URLs
creative.tracking.custom       // Array of custom event tracking URLs

// Get specific URLs
let impressionUrl = creative.tracking.getImpressionUrl(key: "default")
let clickUrl = creative.tracking.getClickUrl(key: "default")
let customUrl = creative.tracking.getCustomUrl(key: "companionOpened")
```

### Firing Events

Use the SDK to fire tracking events:

```swift
// Fire impressions
sdk.fireImpression(tracking: creative.tracking)  // "default" key
sdk.fireImpression(tracking: creative.tracking, key: "slide1")

// Fire clicks
sdk.fireClick(tracking: creative.tracking)  // "default" key
sdk.fireClick(tracking: creative.tracking, key: "slide1")

// Fire custom events
sdk.fireCustom(tracking: creative.tracking, key: "companionOpened")
```

> [!NOTE]
> The `key` parameter is optional for impressions and clicks, defaulting to `default`.

### Utility Functions

Here's an example of utility functions to handle tracking and URL opening:

```swift
func handleImpression(creative: Creative, key: String? = nil) {
    sdk.fireImpression(tracking: creative.tracking, key: key)
}

func handleClick(creative: Creative, key: String? = nil) {
    // Get click URL which includes tracking
    if let clickUrl = creative.tracking.getClickUrl(key: key ?? "default"),
       let url = URL(string: clickUrl)
    {
        // Opening URL in browser handles both tracking and redirection
        UIApplication.shared.open(url)
    }
}

func handleCustomEvent(tracking: Tracking, key: String) {
    sdk.fireCustom(tracking: tracking, key: key)
}
```

> [!NOTE]
> For click tracking, opening the URL in a browser handles both the tracking and destination URL redirection in a single request.

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

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- How to submit Pull Requests
- Commit message conventions (Conventional Commits)
- Code style and testing requirements
- Development workflow

## Documentation

For detailed documentation, please visit the [SDK documentation](https://admoai.github.io/admoai-ios/documentation/admoai) or our [documentation site](https://docs.admoai.com).

## Support

- **API Documentation**: https://admoai.github.io/admoai-ios/documentation/admoai
- **Issues**: [GitHub Issues](https://github.com/admoai/admoai-ios/issues)
- **Discussions**: [GitHub Discussions](https://github.com/admoai/admoai-ios/discussions)
- **Email**: support@admoai.com

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
