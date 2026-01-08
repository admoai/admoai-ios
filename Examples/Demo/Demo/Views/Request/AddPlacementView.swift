import SwiftUI

struct AddPlacementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var placementStore: PlacementStore
    
    @State private var key: String = ""
    @State private var name: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add a custom placement to test different placement keys with the ad server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    TextField("Placement Key", text: $key)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    TextField("Display Name (optional)", text: $name)
                } header: {
                    Text("Placement Details")
                } footer: {
                    Text("The key is required and must be unique. If no display name is provided, the key will be used.")
                }
                
                Section {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.secondary)
                        Text("Generic icon will be used")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Icon")
                }
            }
            .navigationTitle("Add Placement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addPlacement()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addPlacement() {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        
        // Check if key already exists
        if placementStore.placement(forKey: trimmedKey) != nil {
            errorMessage = "A placement with this key already exists."
            showingError = true
            return
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        placementStore.addPlacement(key: trimmedKey, name: trimmedName.isEmpty ? nil : trimmedName)
        dismiss()
    }
}

#Preview {
    AddPlacementView()
        .environmentObject(PlacementStore())
}

