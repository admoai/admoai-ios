import AdMoai
import Foundation

/// Where a tapped ad should take the user.
///
/// Recording the click and navigating are two separate steps: `sdk.fireClick(...)` reports the
/// click and returns nothing to open. The destination is a **content field of the creative**,
/// never `tracking.clicks[].url` — that one is a measurement endpoint whose redirect is an
/// implementation detail, and opening it double-counts the click.
enum AdDestination: Equatable {
    /// A web page. Hand it to the system browser.
    case web(URL)
    /// A link into the host app. Route it through the app's own router, not the system opener.
    case deeplink(URL)
}

/// Destination content keys, per template. These mirror the template field definitions exactly —
/// `contents.getContent(key:)` matches keys verbatim, so the casing here is load-bearing.
enum AdDestinationKey {
    /// `standard`, `imageWithText`, `wideImageOnly`, and Journey templates.
    static let standard = "destinationUrl"
    /// `wideWithCompanion`: the companion's call-to-action.
    static let companion = "clickThroughUrl"
    /// `carousel3Slides`: one destination per slide, paired with the slide's own tracking key.
    static func carouselSlide(_ index: Int) -> String { "urlSlide\(index)" }
}

/// Resolves the destination of a tapped ad from the creative's contents.
enum AdClickResolver {
    /// The destination declared under `key`, or `nil` when the creative carries none.
    ///
    /// Reads `contents` only, so a tracking URL can never come back as a destination. A missing,
    /// blank, or unparseable value yields `nil`: the caller still records the click, and simply
    /// has nowhere to navigate (the `textOnly` template, for one, declares no destination).
    static func destination(in creative: Creative, key: String) -> AdDestination? {
        guard let raw = creative.contents.getContent(key: key)?.value.description
        else { return nil }
        return destination(from: raw)
    }

    /// Classifies a raw destination string. Exposed for callers that already hold a value.
    static func destination(from raw: String) -> AdDestination? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased()
        else { return nil }

        let isWeb = scheme == "http" || scheme == "https"
        // A web URL with no host ("https://") is malformed, not a destination.
        guard !isWeb || url.host != nil else { return nil }

        return isWeb ? .web(url) : .deeplink(url)
    }
}
