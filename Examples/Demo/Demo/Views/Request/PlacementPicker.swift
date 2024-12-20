import AdMoai
import SwiftUI

struct PlacementPicker: View {
    @Binding var placement: Placement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(placementMockData) { mockPlacement in
                Button {
                    // Create a new Placement instance when selected
                    placement = Placement(key: mockPlacement.id)
                    dismiss()
                } label: {
                    HStack {
                        Label(mockPlacement.name, systemImage: mockPlacement.icon)
                        Spacer()
                        if placement.key == mockPlacement.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .navigationTitle("Select Placement")
    }
}
