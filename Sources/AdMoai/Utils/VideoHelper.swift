import Foundation

// Helper Methods (Guaranteed Fields Only)
extension Creative {
    // Delivery detection
    public func isVastTagDelivery() -> Bool { return delivery == "vast_tag" }
    public func isVastXmlDelivery() -> Bool { return delivery == "vast_xml" }
    public func isJsonDelivery() -> Bool { return delivery == "json" }
    
    // VAST data access
    public func getVastTagUrl() -> String? { return vast?.tagUrl }
    public func getVastXmlBase64() -> String? { return vast?.xmlBase64 }
    
    // Template field helpers (guaranteed fields only)
    public func isSkippable() -> Bool {
        return contents.getContent(key: "isSkippable")?.value as? Bool ?? false
    }
    
    public func getSkipOffset() -> String? {
        return contents.getContent(key: "skipOffset")?.value.description
    }
}
