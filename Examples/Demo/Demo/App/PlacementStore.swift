import Foundation
import SwiftUI

/// Manages the list of placements including predefined and custom ones
/// Custom placements are persisted to UserDefaults
@MainActor
final class PlacementStore: ObservableObject {
    
    private static let customPlacementsKey = "customPlacements"
    
    /// All available placements (predefined + custom)
    @Published private(set) var placements: [PlacementData] = []
    
    /// Predefined placements that cannot be deleted
    private let predefinedPlacements: [PlacementData] = [
        PlacementData(id: "home", name: "Home", icon: "house"),
        PlacementData(id: "search", name: "Search", icon: "magnifyingglass"),
        PlacementData(id: "menu", name: "Menu", icon: "list.bullet"),
        PlacementData(id: "promotions", name: "Promotions", icon: "tag"),
        PlacementData(id: "waiting", name: "Waiting", icon: "clock"),
        PlacementData(id: "vehicleSelection", name: "Vehicle Selection", icon: "car"),
        PlacementData(id: "rideSummary", name: "Ride Summary", icon: "arrow.up"),
        PlacementData(id: "invalidPlacement", name: "Invalid Placement", icon: "exclamationmark.triangle"),
    ]
    
    /// Custom placements added by the user
    @Published private(set) var customPlacements: [PlacementData] = []
    
    init() {
        loadCustomPlacements()
        updatePlacements()
    }
    
    // MARK: - Public Methods
    
    /// Adds a new custom placement
    func addPlacement(key: String, name: String? = nil) {
        let displayName = (name?.isEmpty ?? true) ? key : name!
        let newPlacement = PlacementData(
            id: key,
            name: displayName,
            icon: "square.grid.2x2"  // Generic icon for custom placements
        )
        
        // Check if placement with this key already exists
        guard !placements.contains(where: { $0.id == key }) else { return }
        
        customPlacements.append(newPlacement)
        saveCustomPlacements()
        updatePlacements()
    }
    
    /// Removes a custom placement
    func removePlacement(id: String) {
        // Only allow removing custom placements, not predefined ones
        guard !predefinedPlacements.contains(where: { $0.id == id }) else { return }
        
        customPlacements.removeAll { $0.id == id }
        saveCustomPlacements()
        updatePlacements()
    }
    
    /// Checks if a placement is custom (can be deleted)
    func isCustomPlacement(id: String) -> Bool {
        customPlacements.contains { $0.id == id }
    }
    
    /// Finds a placement by its key
    func placement(forKey key: String) -> PlacementData? {
        placements.first { $0.id == key }
    }
    
    // MARK: - Private Methods
    
    private func updatePlacements() {
        placements = predefinedPlacements + customPlacements
    }
    
    private func loadCustomPlacements() {
        guard let data = UserDefaults.standard.data(forKey: Self.customPlacementsKey),
              let decoded = try? JSONDecoder().decode([PlacementData].self, from: data) else {
            return
        }
        customPlacements = decoded
    }
    
    private func saveCustomPlacements() {
        guard let data = try? JSONEncoder().encode(customPlacements) else { return }
        UserDefaults.standard.set(data, forKey: Self.customPlacementsKey)
    }
}

