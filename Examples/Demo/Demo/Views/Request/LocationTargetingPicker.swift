import AdMoai
import SwiftUI

struct LocationTargetingPicker: View {
    @Binding var targeting: Targeting
    @Environment(\.dismiss) private var dismiss
    @State private var coordinates: [Targeting.LocationCoordinate] = []

    var body: some View {
        VStack {
            List {
                Section {
                    Text(
                        "Add latitude and longitude coordinates to target specific locations. You can add multiple coordinates to target different areas."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if !coordinates.isEmpty {
                    ForEach(0..<coordinates.count, id: \.self) { index in
                        Section {
                            CoordinateRow(
                                coordinate: coordinates[index],
                                onUpdate: { newCoordinate in
                                    coordinates[index] = newCoordinate
                                    updateTargeting()
                                }
                            )
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                coordinates.remove(at: index)
                                updateTargeting()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                Button {
                    coordinates.append((latitude: 0, longitude: 0))
                    updateTargeting()
                } label: {
                    Label("Add Location", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    coordinates.append(setRandomCoordinate())
                    updateTargeting()
                } label: {
                    Label("Add Random Location", systemImage: "dice")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.blue)
                        .padding(.vertical, 12)
                        .background(.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    coordinates.removeAll()
                    updateTargeting()
                } label: {
                    Text("Clear All")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.red)
                        .padding(.vertical, 12)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(coordinates.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .navigationTitle("Location Targeting")
        .onAppear {
            coordinates = targeting.location ?? []
        }
    }

    private func setRandomCoordinate() -> Targeting.LocationCoordinate {
        let randomLatitude = (Double.random(in: -90...90) * 10000).rounded() / 10000
        let randomLongitude = (Double.random(in: -180...180) * 10000).rounded() / 10000
        return (latitude: randomLatitude, longitude: randomLongitude)
    }

    private func updateTargeting() {
        targeting = Targeting(
            geo: targeting.geo,
            location: coordinates.isEmpty ? nil : coordinates,
            custom: targeting.custom
        )
    }
}

private struct CoordinateRow: View {
    let coordinate: Targeting.LocationCoordinate
    let onUpdate: (Targeting.LocationCoordinate) -> Void

    @State private var latitude: String
    @State private var longitude: String

    init(
        coordinate: Targeting.LocationCoordinate,
        onUpdate: @escaping (Targeting.LocationCoordinate) -> Void
    ) {
        self.coordinate = coordinate
        self.onUpdate = onUpdate
        _latitude = State(initialValue: String(coordinate.latitude))
        _longitude = State(initialValue: String(coordinate.longitude))
    }

    var body: some View {
        VStack {
            LabeledContent("Latitude") {
                TextField("Latitude", text: $latitude)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: latitude) { _, _ in updateCoordinate() }
            }

            LabeledContent("Longitude") {
                TextField("Longitude", text: $longitude)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: longitude) { _, _ in updateCoordinate() }
            }
        }
    }

    private func updateCoordinate() {
        guard let lat = Double(latitude),
            let lon = Double(longitude)
        else {
            return
        }
        onUpdate((latitude: lat, longitude: lon))
    }
}

#Preview {
    NavigationStack {
        LocationTargetingPicker(targeting: .constant(Targeting()))
    }
}
