# AdMoai iOS SDK

AdMoai iOS SDK is a native advertising solution that enables seamless integration of ads into iOS applications. The SDK provides a robust API for requesting and displaying various ad formats with advanced targeting capabilities.

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

let sdk = AdMoai(config: config)

// Configure user settings globally
sdk.setUserConfig(
    UserConfig(
        id: "user_123",
        ip: "203.0.113.1",
        timezone: TimeZone.current.identifier,
        consent: User.Consent(gdpr: true)
    )
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
    .setUser(User(
        id: "different_user",
        ip: "203.0.113.2",
        timezone: "America/New_York",
        consent: User.Consent(gdpr: false)
    ))
    // Add targeting
    .addLocationTargeting(latitude: 37.7749, longitude: -122.4194)
    .setCustomTargeting([
        Targeting.CustomKeyValue(key: "age", value: 25),
        Targeting.CustomKeyValue(key: "category", value: "travel")
    ])
    .addCustomTargeting(key: "vip", value: true)
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
> The SDK automatically handles impression and custom event tracking through URL sessions. For clicks, opening the URL in a browser handles both the tracking and destination URL redirection in a single request. The key parameter is optional for impressions and clicks, defaulting to "default".

## Demo App

For a complete example implementation, check out the [demo app](Examples/Demo/README.md).

## Documentation

For detailed documentation, please visit our [documentation site](https://docs.admoai.com).
