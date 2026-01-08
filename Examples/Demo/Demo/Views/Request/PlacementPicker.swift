import AdMoai
import SwiftUI

struct PlacementPicker: View {
    @Binding var placement: Placement
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var placementStore: PlacementStore
    
    @State private var showingAddPlacement = false

    var body: some View {
        List {
            Section {
                ForEach(placementStore.placements) { mockPlacement in
                    Button {
                        placement = Placement(key: mockPlacement.id)
                        dismiss()
                    } label: {
                        HStack {
                            Label(mockPlacement.name, systemImage: mockPlacement.icon)
                            
                            if placementStore.isCustomPlacement(id: mockPlacement.id) {
                                Text("Custom")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()
                            
                            if placement.key == mockPlacement.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if placementStore.isCustomPlacement(id: mockPlacement.id) {
                            Button(role: .destructive) {
                                placementStore.removePlacement(id: mockPlacement.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                if placementStore.customPlacements.isEmpty {
                    Text("Tap the + button to add custom placements for testing.")
                } else {
                    Text("Swipe left on custom placements to delete them.")
                }
            }
        }
        .navigationTitle("Select Placement")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPlacement = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPlacement) {
            AddPlacementView()
                .environmentObject(placementStore)
        }
    }
}

#Preview {
    NavigationStack {
        PlacementPicker(placement: .constant(Placement(key: "home")))
            .environmentObject(PlacementStore())
    }
}
