import Foundation

// Helper Methods (Guaranteed Fields Only)
extension Creative {
    // Delivery detection
    public func isVastTagDelivery() -> Bool { return delivery == "vast_tag" }
    public func isVastXmlDelivery() -> Bool { return delivery == "vast_xml" }
    public func isJsonDelivery() -> Bool { return delivery == "json" }
    
    // VAST data access
    /// Returns the VAST tag URL with optional mediaType and mediaDelivery query parameters.
    /// - Parameters:
    ///   - mediaType: Optional media type (e.g., "video/mp4")
    ///   - mediaDelivery: Optional delivery method (e.g., "progressive", "streaming")
    /// - Returns: The VAST tag URL with query parameters appended, or nil if not available
    public func getVastTagUrl(mediaType: String? = nil, mediaDelivery: String? = nil) -> String? {
        guard let baseUrl = vast?.tagUrl else { return nil }
        
        var queryParams: [String] = []
        if let mediaType = mediaType, let encoded = mediaType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryParams.append("mediaType=\(encoded)")
        }
        if let mediaDelivery = mediaDelivery, let encoded = mediaDelivery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryParams.append("mediaDelivery=\(encoded)")
        }
        
        if queryParams.isEmpty {
            return baseUrl
        }
        
        let separator = baseUrl.contains("?") ? "&" : "?"
        return "\(baseUrl)\(separator)\(queryParams.joined(separator: "&"))"
    }
    
    /// Returns the VAST XML Base64 string, optionally modifying MediaFile attributes.
    /// - Parameters:
    ///   - mediaType: Optional media type to set/update in MediaFile elements (e.g., "video/mp4")
    ///   - mediaDelivery: Optional delivery method to set/update in MediaFile elements (e.g., "progressive")
    /// - Returns: The Base64-encoded VAST XML with modifications, or nil if not available
    public func getVastXmlBase64(mediaType: String? = nil, mediaDelivery: String? = nil) -> String? {
        guard let base64Xml = vast?.xmlBase64 else { return nil }
        
        // If no modifications needed, return original
        if mediaType == nil && mediaDelivery == nil {
            return base64Xml
        }
        
        // Decode, modify, and re-encode
        guard let decodedData = Data(base64Encoded: base64Xml),
              let xmlString = String(data: decodedData, encoding: .utf8) else {
            return base64Xml
        }
        
        // Regex pattern to match MediaFile elements
        let mediaFilePattern = #"(<MediaFile[^>]*?)(\s+type="[^"]*")?(\s+delivery="[^"]*")?([^>]*?>)"#
        
        guard let regex = try? NSRegularExpression(pattern: mediaFilePattern, options: []) else {
            return base64Xml
        }
        
        let range = NSRange(xmlString.startIndex..., in: xmlString)
        var resultString = xmlString
        
        // Process matches in reverse to preserve indices
        let matches = regex.matches(in: xmlString, options: [], range: range).reversed()
        
        for match in matches {
            guard let matchRange = Range(match.range, in: xmlString) else { continue }
            var matchedString = String(xmlString[matchRange])
            
            // Update or add type attribute
            if let newType = mediaType {
                if matchedString.contains("type=") {
                    matchedString = matchedString.replacingOccurrences(
                        of: #"type="[^"]*""#,
                        with: "type=\"\(newType)\"",
                        options: .regularExpression
                    )
                } else {
                    matchedString = matchedString.replacingOccurrences(
                        of: ">",
                        with: " type=\"\(newType)\">"
                    )
                }
            }
            
            // Update or add delivery attribute
            if let newDelivery = mediaDelivery {
                if matchedString.contains("delivery=") {
                    matchedString = matchedString.replacingOccurrences(
                        of: #"delivery="[^"]*""#,
                        with: "delivery=\"\(newDelivery)\"",
                        options: .regularExpression
                    )
                } else {
                    matchedString = matchedString.replacingOccurrences(
                        of: ">",
                        with: " delivery=\"\(newDelivery)\">"
                    )
                }
            }
            
            resultString = resultString.replacingCharacters(in: matchRange, with: matchedString)
        }
        
        // Re-encode to Base64
        guard let encodedData = resultString.data(using: .utf8) else {
            return base64Xml
        }
        
        return encodedData.base64EncodedString()
    }
    
    // Template field helpers (guaranteed fields only)
    /// Whether the video may be skipped.
    ///
    /// Prefers ``Metadata/isSkippable`` — the engine-owned field — then falls back to the
    /// creative's content fields.
    ///
    /// This previously read `contents.getContent(key: "isSkippable")?.value as? Bool`, which could
    /// never return `true` for two independent reasons:
    ///
    /// 1. The platform creates template fields in snake_case. A live serve returns
    ///    `is_skippable`, and camelCase was the only key matched.
    /// 2. `Content.value` is an ``AnyCodable``, so casting it to `Bool` always fails — the cast
    ///    has to go through the wrapped value, exactly as `Content`'s own documentation says.
    ///
    /// Point 1 is the same class of defect as #2483, where the journey click resolver matched a
    /// hand-maintained snake_case list while the platform wrote camelCase: the same seam, the
    /// opposite direction. The Flutter and Android SDKs carried point 1 and are fixed alongside
    /// this.
    public func isSkippable() -> Bool {
        if let fromMetadata = metadata?.isSkippable {
            return fromMetadata
        }
        let content =
            contents.getContent(key: "isSkippable") ?? contents.getContent(key: "is_skippable")
        guard let value = content?.value else { return false }
        return skippabilityFlag(value)
    }

    /// Seconds before a skippable video may be skipped, as a string.
    ///
    /// Prefers ``Metadata/skipOffsetSeconds``, then falls back to the creative's content fields,
    /// matching both `skipOffset` and `skip_offset` for the reason above.
    ///
    /// Returns a `String?` to stay source-compatible; read `creative.metadata?.skipOffsetSeconds`
    /// for a typed `Int?`.
    public func getSkipOffset() -> String? {
        if let seconds = metadata?.skipOffsetSeconds {
            return String(seconds)
        }
        let content =
            contents.getContent(key: "skipOffset") ?? contents.getContent(key: "skip_offset")
        return content.flatMap { scalarText($0.value) }
    }
}

/// Renders a content value as a skip-offset string, or `nil` when it cannot be one.
///
/// `AnyCodable.description` returned the literal `"null"` for a JSON null and stringified arrays
/// and dictionaries, so `getSkipOffset()` could hand back `"null"` or `"[1, 2]"` — values a
/// publisher would parse as a duration. Only scalars are meaningful here; anything else is `nil`,
/// matching Android (`JsonPrimitive.contentOrNull`) and Flutter.
private func scalarText(_ value: AnyCodable) -> String? {
    switch value.value {
    case is NSNull: return nil
    case let text as String: return text
    case let number as Int: return String(number)
    case let number as Double: return String(number)
    case let flag as Bool: return String(flag)
    default: return nil
    }
}

/// Interprets a content value as a boolean flag.
///
/// The template field backing skippability is typed `integer`, so the value can arrive as a bool,
/// a number, or a string depending on the template and the producer. Anything unrecognized is
/// `false` — never a crash.
private func skippabilityFlag(_ value: AnyCodable) -> Bool {
    switch value.value {
    case let flag as Bool:
        return flag
    case let number as Int:
        return number != 0
    case let number as Double:
        return number != 0
    case let text as String:
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "true" || normalized == "1"
    default:
        return false
    }
}
