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
    public func isSkippable() -> Bool {
        return contents.getContent(key: "isSkippable")?.value as? Bool ?? false
    }
    
    public func getSkipOffset() -> String? {
        return contents.getContent(key: "skipOffset")?.value.description
    }
}
