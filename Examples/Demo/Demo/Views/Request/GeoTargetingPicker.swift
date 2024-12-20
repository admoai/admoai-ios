import AdMoai
import SwiftUI

struct GeoTargetingPicker: View {
    @Binding var targeting: Targeting
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private struct City: Identifiable {
        let id: Int  // Geoname ID
        let name: String
        let country: String
        
        static let available: [City] = [
            City(id: 2_643_743, name: "London", country: "UK"),
            City(id: 3_530_597, name: "Miami", country: "US"),
            City(id: 5_128_581, name: "New York", country: "US"),
            City(id: 2_988_507, name: "Paris", country: "FR"),
            City(id: 3_169_070, name: "Rome", country: "IT"),
            City(id: 3_871_336, name: "Santiago", country: "CL"),
        ].sorted(by: { $0.name < $1.name })
    }

    private var selectedIds: Set<Int> {
        Set(targeting.geo ?? [])
    }

    private var filteredCities: [City] {
        searchText.isEmpty
            ? City.available
            : City.available.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
    }

    var body: some View {
        List {
            Section {
                Text(
                    "This is a sample list of cities. The actual implementation must use the correct Geoname IDs for the cities and countries you want to target.\nThe user's IP address automatically determines the Geoname ID for their city and country, but setting geo-targeting will override these values."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                ForEach(filteredCities) { city in
                    Button {
                        var newIds = selectedIds
                        if newIds.contains(city.id) {
                            newIds.remove(city.id)
                        } else {
                            newIds.insert(city.id)
                        }
                        targeting = Targeting(
                            geo: newIds.isEmpty ? nil : Array(newIds),
                            location: targeting.location,
                            custom: targeting.custom
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(city.name)
                                Text(String(city.id))
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Spacer()
                            if selectedIds.contains(city.id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            } footer: {
                if selectedIds.isEmpty {
                    Text("Select one or more cities to target ads using their Geoname IDs.")
                } else {
                    Text("Selected \(selectedIds.count) cities for geo targeting.")
                }
            }

            if !selectedIds.isEmpty {
                Section {
                    Button(role: .destructive) {
                        targeting = Targeting(
                            geo: nil,
                            location: targeting.location,
                            custom: targeting.custom
                        )   
                    } label: {
                        Text("Clear Selection")
                    }
                }
            }
        }
        .navigationTitle("Geo Targeting")
        .searchable(text: $searchText, prompt: "Search cities")
    }
}
