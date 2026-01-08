import SwiftUI

@main
struct DemoApp: App {
    @StateObject private var placementStore = PlacementStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(placementStore)
        }
    }
}
