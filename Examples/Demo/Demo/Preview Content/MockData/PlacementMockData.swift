import Foundation

struct PlacementData: Identifiable, Codable {
    let id: String  // key
    let name: String
    let icon: String
}

// Note: This constant is kept for backward compatibility.
// The app now uses PlacementStore which manages both predefined and custom placements.
// Custom placements can be added dynamically from the PlacementPicker UI.
let placementMockData: [PlacementData] = [
    PlacementData(id: "home", name: "Home", icon: "house"),
    PlacementData(id: "search", name: "Search", icon: "magnifyingglass"),
    PlacementData(id: "menu", name: "Menu", icon: "list.bullet"),
    PlacementData(id: "promotions", name: "Promotions", icon: "tag"),
    PlacementData(id: "waiting", name: "Waiting", icon: "clock"),
    PlacementData(id: "vehicleSelection", name: "Vehicle Selection", icon: "car"),
    PlacementData(id: "rideSummary", name: "Ride Summary", icon: "arrow.up"),
    PlacementData(id: "invalidPlacement", name: "Invalid Placement", icon: "exclamationmark.triangle"),
]
