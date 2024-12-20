import Foundation

struct PlacementData: Identifiable {
    let id: String  // key
    let name: String
    let icon: String
}

let placementMockData: [PlacementData] = {
    var data: [PlacementData] = [
        PlacementData(id: "home", name: "Home", icon: "house"),
        PlacementData(id: "search", name: "Search", icon: "magnifyingglass"),
        PlacementData(id: "menu", name: "Menu", icon: "list.bullet"),
        PlacementData(id: "promotions", name: "Promotions", icon: "tag"),
        PlacementData(id: "waiting", name: "Waiting", icon: "clock"),
        PlacementData(id: "vehicleSelection", name: "Vehicle Selection", icon: "car"),
        PlacementData(id: "rideSummary", name: "Ride Summary", icon: "arrow.up"),
    ]

    // #if DEBUG
    data.append(
        PlacementData(
            id: "invalidPlacement", name: "Invalid Placement", icon: "exclamationmark.triangle"))
    // #endif

    return data
}()
