# Admoai iOS SDK


The AdMoai iOS SDK is a lightweight wrapper around the Decision Engine API, enabling iOS applications to request, render, and track native and video advertisements with advanced targeting capabilities.

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-iOS%2014%2B%20%7C%20macOS%2011%2B-blue.svg)](https://developer.apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)



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

### Format

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

> **Note**: Admoai is OM-compatible and passes verification metadata through VAST `<AdVerifications>` tags. See the [Open Measurement Integration](#open-measurement-integration) section below for implementation guidance.

### Video Helper Methods

```swift
// Skippable ad detection
let isSkippable = creative.isSkippable()
let skipOffset = creative.getSkipOffset()  // e.g., "00:00:05" or "5"
```

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
│   │               ├── vast: VastData?             // {tagUrl} or {xmlBase64}
│   │               └── verificationScriptResources: [VerificationScriptResource]?  // OM verification data
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

Admoai is **OM-compatible** and passes Open Measurement verification metadata through VAST `<AdVerifications>` tags. This section explains how publishers can implement Open Measurement viewability and verification measurement in their apps.

### Roles and Responsibilities

**What Admoai does:**
- Acts as a strict ad server / decision engine
- Includes `<AdVerifications>` tags in VAST responses
- Provides verification metadata via SDK helper methods
- Documents OM integration patterns

**What Admoai does NOT do:**
- Ship an OM SDK or namespaced OM build
- Act as the "OM integration partner" in the trust chain
- Provide IAB OM certification

**What you (the Publisher) must do:**
- Own the OM integration in your app
- Obtain and use your own IAB namespace
- Integrate the IAB OM SDK or OM-compatible video player
- Manage OM session lifecycle (create, start, track events, finish)

> **Important**: Admoai stays out of the OM trust chain. Your app is the OM integration partner and uses your own IAB namespace for all measurements.

---

### Do I Need My Own IAB Namespace?

**Short answer:** No namespace = verification still works, but the SDK owns OM. Namespace = you own OM.

**Detailed explanation:**

You do **not** need your own IAB OM namespace if you use an OM-certified SDK like Google IMA (Path B). In that case, verification vendors (IAS, DoubleVerify, Moat, etc.) will still receive all required measurement data, but the OM integration partner will be the SDK provider (e.g., Google), not your app.

Creating your own IAB OM namespace is **only required** if you want to implement Open Measurement directly (e.g., using AVPlayer as shown in Path A) and retain full control and ownership of the OM session lifecycle. This gives you complete flexibility over the video player UI and behavior.

**In summary:**
- **Path A (Native OM SDK)**: Requires your own IAB namespace → You own the OM integration
- **Path B (Google IMA SDK)**: No namespace needed → Google owns the OM integration
- **Path C (JW Player)**: No namespace needed → JW Player owns the OM integration

> If you choose Path A and want full control, proceed to Step 1 below. If you choose Path B or C, skip to their respective implementation sections.

---

### Step 1: Get Your IAB Namespace (Path A Only)

If you're implementing Path A (Native OM SDK), you need to obtain your own namespaced OM SDK from IAB Tech Lab:

1. **Visit the IAB Tech Lab website**: Go to [https://iabtechlab.com/standards/open-measurement-sdk/](https://iabtechlab.com/standards/open-measurement-sdk/)
2. **Click "Download OM SDK"**: This will take you to the compliance portal
3. **Sign in or register**: Create an account if you don't have one already
4. **Navigate to "Open Measurement SDK" section**: Find the SDK download area in your account dashboard
5. **Add a namespace**: Create a unique namespace identifier for your organization (e.g., `com.yourcompany-omid`)
   - Use a simple, recognizable name that represents your organization
   - This namespace identifies you as the OM integration partner
6. **Click "Build iOS"**: Generate the iOS SDK with your namespace
7. **Download from iOS tab**: Download the framework (e.g., `OMSDK_Yournamespace.xcframework`)
8. **Add to your Xcode project**: Drag the framework into your project and ensure it's embedded

> **Critical**: Your namespace will follow you throughout the OM trust chain. All verification vendors (IAS, DoubleVerify, Moat, etc.) will see your namespace as the OM integration partner, not Admoai.

---

### Step 2: Choose Your Implementation Path

Admoai is OM-compatible and works with any OM integration approach. We recommend the Native OM SDK for maximum flexibility, but you have multiple options:

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Path A: Native OM SDK** (Recommended) | Full control, better UX, custom UI | More engineering effort | Publishers wanting complete control over video UX |
| **Path B: Google IMA SDK** | OM handled automatically, less code | Less control, IMA watermarks | Publishers prioritizing speed over customization |
| **Path C: JW Player** | Commercial support, OM built-in | License cost, vendor lock-in | Publishers wanting commercial-grade video player with support |

---

### Path A: Native OM SDK Integration (Recommended for Best UX)

Use this approach for full control over video playback and custom UI.

#### 1. Add the IAB OM SDK to your project

After downloading the namespaced OM SDK framework from IAB:

1. Drag `OMSDK_Yournamespace.xcframework` into your Xcode project
2. Ensure it's added to your target's "Frameworks, Libraries, and Embedded Content"
3. Set the framework to "Embed & Sign"

#### 2. Extract verification resources from Admoai

```swift
import AdMoai
import OMSDK_Yournamespace  // Your IAB namespace

// Get creative from Admoai SDK
if let creative = response.body.data?.first?.creatives?.first {
    // Check if OM verification is available
    if creative.hasOMVerification() {
        let verificationResources = creative.getVerificationResources()
        // Proceed with OM session creation
    }
}
```

#### 3. Create and start OM session

```swift
import AVFoundation
import OMSDK_Yournamespace

class VideoAdPlayer {
    
    private var omAdSession: OMIDAdSession?
    private var omAdEvents: OMIDAdEvents?
    private var omMediaEvents: OMIDMediaEvents?
    
    func setupOMSession(creative: Creative, playerView: UIView) {
        guard creative.hasOMVerification() else { return }
        
        // 1. Activate OM SDK (once per app lifecycle)
        OMIDSDK.activate()
        
        // 2. Create Partner (your company info)
        guard let partner = OMIDPartner(name: "YourCompany", versionString: "1.0.0") else {
            return
        }
        
        // 3. Extract verification scripts from Admoai
        guard let verificationResources = creative.getVerificationResources() else {
            return
        }
        
        var verificationScripts: [OMIDVerificationScriptResource] = []
        for resource in verificationResources {
            if let url = URL(string: resource.scriptUrl),
               let script = OMIDVerificationScriptResource(
                   url: url,
                   vendorKey: resource.vendorKey,
                   parameters: resource.verificationParameters
               ) {
                verificationScripts.append(script)
            }
        }
        
        // 4. Create AdSessionContext
        guard let context = try? OMIDAdSessionContext(
            partner: partner,
            script: OMIDSDK.shared().scriptContent,
            resources: verificationScripts,
            contentUrl: nil,
            customReferenceIdentifier: nil
        ) else {
            return
        }
        
        // 5. Create AdSessionConfiguration
        let config = OMIDAdSessionConfiguration(
            creativeType: .video,
            impressionType: .beginToRender,
            impressionOwner: .nativeOwner,
            mediaEventsOwner: .nativeOwner,
            isolateVerificationScripts: false
        )
        
        // 6. Create AdSession
        guard let session = try? OMIDAdSession(configuration: config, adSessionContext: context) else {
            return
        }
        omAdSession = session
        
        // 7. Register video view
        omAdSession?.mainAdView = playerView
        
        // 8. Create event trackers
        omAdEvents = try? OMIDAdEvents(adSession: session)
        omMediaEvents = try? OMIDMediaEvents(adSession: session)
        
        // 9. Start session
        try? omAdSession?.start()
        
        // 10. Fire loaded event
        let vastProperties = OMIDVASTProperties(
            autoPlay: true,
            position: .standalone
        )
        try? omAdEvents?.loaded(with: vastProperties)
    }
    
    func onVideoStarted(duration: TimeInterval, volume: Float) {
        try? omMediaEvents?.start(duration: duration, mediaPlayerVolume: volume)
        try? omAdEvents?.impressionOccurred()
    }
    
    func onVideoProgress(currentTime: TimeInterval, duration: TimeInterval) {
        let progress = currentTime / duration
        
        if progress >= 0.25 && !firstQuartileFired {
            try? omMediaEvents?.firstQuartile()
            firstQuartileFired = true
        } else if progress >= 0.5 && !midpointFired {
            try? omMediaEvents?.midpoint()
            midpointFired = true
        } else if progress >= 0.75 && !thirdQuartileFired {
            try? omMediaEvents?.thirdQuartile()
            thirdQuartileFired = true
        }
    }
    
    func onVideoCompleted() {
        try? omMediaEvents?.complete()
        omAdSession?.finish()
    }
    
    func onVideoSkipped() {
        try? omMediaEvents?.skipped()
        omAdSession?.finish()
    }
    
    func cleanup() {
        omAdSession?.finish()
        omAdSession = nil
        omAdEvents = nil
        omMediaEvents = nil
    }
    
    private var firstQuartileFired = false
    private var midpointFired = false
    private var thirdQuartileFired = false
}
```

#### 4. Integrate with AVPlayer

```swift
import AVFoundation
import UIKit

class VideoAdViewController: UIViewController {
    
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoAdPlayer: VideoAdPlayer?
    private var timeObserver: Any?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get creative from Admoai SDK
        guard let creative = getCreativeFromAdmoai() else { return }
        
        // Setup video URL (VAST or JSON delivery)
        let videoUrl: URL?
        
        if creative.isVastTagDelivery() {
            // Fetch and parse VAST XML to get MediaFile URL
            videoUrl = fetchVastAndExtractMediaUrl(creative.vast?.tagUrl)
        } else if creative.isVastXmlDelivery() {
            // Decode Base64 VAST XML and extract MediaFile URL
            videoUrl = parseVastXmlAndExtractMediaUrl(creative.vast?.xmlBase64)
        } else {
            // JSON delivery: direct video URL
            if let urlString = creative.contents.getContent(key: "video_asset")?.value.description {
                videoUrl = URL(string: urlString)
            } else {
                videoUrl = nil
            }
        }
        
        guard let url = videoUrl else { return }
        
        // Setup AVPlayer
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = view.bounds
        playerLayer?.videoGravity = .resizeAspect
        
        if let layer = playerLayer {
            view.layer.addSublayer(layer)
        }
        
        // Setup OM session
        videoAdPlayer = VideoAdPlayer()
        videoAdPlayer?.setupOMSession(creative: creative, playerView: view)
        
        // Observe playback state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
        
        // Track video progress
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  let duration = self.player?.currentItem?.duration else { return }
            
            let currentTime = CMTimeGetSeconds(time)
            let totalDuration = CMTimeGetSeconds(duration)
            
            if currentTime > 0 && !self.hasStarted {
                self.videoAdPlayer?.onVideoStarted(duration: totalDuration, volume: 1.0)
                self.hasStarted = true
            }
            
            self.videoAdPlayer?.onVideoProgress(currentTime: currentTime, duration: totalDuration)
        }
        
        // Start playback
        player?.play()
    }
    
    @objc private func playerDidFinishPlaying() {
        videoAdPlayer?.onVideoCompleted()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        videoAdPlayer?.cleanup()
        player?.pause()
    }
    
    private var hasStarted = false
}
```

---

### Path B: Google IMA SDK (Convenience Path)

Use this approach if you want OM handled automatically with less code, at the cost of less UI control.

#### 1. Add dependencies

```swift
// Using CocoaPods - add to your Podfile:
pod 'GoogleAds-IMA-iOS-SDK', '~> 3.19'

// Or using Swift Package Manager:
dependencies: [
    .package(url: "https://github.com/googleads/swift-package-manager-google-interactive-media-ads-ios.git", from: "3.19.0")
]
```

#### 2. Setup IMA with OM support

```swift
import UIKit
import GoogleInteractiveMediaAds
import AVFoundation

class VideoAdViewController: UIViewController {
    
    private var adsLoader: IMAAdsLoader?
    private var adsManager: IMAAdsManager?
    private var contentPlayer: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get creative from Admoai SDK
        guard let creative = getCreativeFromAdmoai() else { return }
        
        // Setup content player
        setupContentPlayer()
        
        // Setup IMA with OM enabled
        let settings = IMASettings()
        settings.enableOMIDSupport = true  // Enable OM in IMA
        
        adsLoader = IMAAdsLoader(settings: settings)
        adsLoader?.delegate = self
        
        // Get VAST tag URL from Admoai creative
        guard let vastTagUrl = creative.vast?.tagUrl else { return }
        
        // Request ads
        let request = IMAAdsRequest(
            adTagUrl: vastTagUrl,
            adDisplayContainer: IMAAdDisplayContainer(
                adContainer: view,
                viewController: self
            ),
            contentPlayhead: nil,
            userContext: nil
        )
        
        adsLoader?.requestAds(with: request)
    }
    
    private func setupContentPlayer() {
        contentPlayer = AVPlayer()
        playerLayer = AVPlayerLayer(player: contentPlayer)
        playerLayer?.frame = view.bounds
        
        if let layer = playerLayer {
            view.layer.addSublayer(layer)
        }
    }
}

extension VideoAdViewController: IMAAdsLoaderDelegate {
    func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
        adsManager = adsLoadedData.adsManager
        adsManager?.delegate = self
        adsManager?.initialize(with: nil)
    }
    
    func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        print("Ad loading failed: \(adErrorData.adError.message ?? "")")
        contentPlayer?.play()
    }
}

extension VideoAdViewController: IMAAdsManagerDelegate {
    func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        switch event.type {
        case .LOADED:
            adsManager.start()
        case .COMPLETE, .SKIPPED:
            contentPlayer?.play()
        default:
            break
        }
    }
    
    func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        print("Ad error: \(error.message ?? "")")
        contentPlayer?.play()
    }
}
```

> **Note on Google IMA**: Google IMA automatically handles OM session creation when `enableOMIDSupport = true` and VAST includes `<AdVerifications>` tags. However, you get less control over UI (IMA shows watermarks, "Learn More" buttons, and default skip buttons). For custom video UX, use Path A.

---

### Accessing Admoai's Verification Metadata

Regardless of which path you choose, Admoai provides helper methods to access OM verification data:

```swift
// Check if creative has OM verification
if creative.hasOMVerification() {
    let resources = creative.getVerificationResources()
    
    resources?.forEach { resource in
        print("Vendor: \(resource.vendorKey)")           // e.g., "company.com-omid"
        print("Script URL: \(resource.scriptUrl)")       // e.g., "https://verification.ias.com/..."
        print("Parameters: \(resource.verificationParameters)")  // e.g., "anId=123&advId=789"
    }
}
```

#### VerificationScriptResource Properties

| Property | Type | Description |
|----------|------|-------------|
| `vendorKey` | String | Vendor identifier (e.g., "ias", "doubleverify", "moat") |
| `scriptUrl` | String | URL to verification JavaScript that OM SDK will load |
| `verificationParameters` | String | Query parameters for verification session |

---

### VAST `<AdVerifications>` Handling

When you use VAST Tag or VAST XML delivery, Admoai includes `<AdVerifications>` in the VAST response:

```xml
<VAST version="4.2">
  <Ad>
    <InLine>
      <AdVerifications>
        <Verification vendor="company.com-omid">
          <JavaScriptResource apiFramework="omid" browserOptional="true">
            <![CDATA[https://verification.ias.com/omid_verification.js]]>
          </JavaScriptResource>
          <VerificationParameters>
            <![CDATA[anId=123&advId=789&creativeId=456]]>
          </VerificationParameters>
        </Verification>
      </AdVerifications>
      <!-- Linear creative, tracking, media files, etc. -->
    </InLine>
  </Ad>
</VAST>
```

- **Path A (Native OM SDK)**: Parse VAST yourself, extract `<AdVerifications>`, map to OM SDK `OMIDVerificationScriptResource` objects
- **Path B (Google IMA SDK)**: IMA automatically parses `<AdVerifications>` and creates OM sessions

---

### Testing Your OM Integration

**Use OM SDK validation**: The IAB OM SDK includes validation modes to verify your integration

---

### Summary

- **Admoai is OM-compatible**: We pass verification metadata via VAST `<AdVerifications>` and SDK helpers
- **Publishers own OM integration**: Publisher's app is the OM integration partner with your own IAB namespace
- **Three paths available**: Native OM SDK (full control), Google IMA SDK (convenience), or JW Player (commercial)
- **Admoai stays out of the trust chain**: We're a strict ad server; you're responsible for OM implementation

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

---

## License

Copyright 2025 Admoai Inc. All rights reserved.
