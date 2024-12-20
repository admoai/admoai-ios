import AdMoai
import SwiftUI

// Extension to make LocationCoordinate identifiable
private var coordinateIds: [String: String] = [:]

extension Targeting.LocationCoordinate: Identifiable {
    public var id: String {
        let key = "\(latitude),\(longitude)"
        if coordinateIds[key] == nil {
            coordinateIds[key] = UUID().uuidString
        }
        return coordinateIds[key]!
    }
}

struct LocationTargetingPicker: View {
    @Binding var targeting: Targeting
    @Environment(\.dismiss) private var dismiss
    @State private var coordinates: [Targeting.LocationCoordinate] = []

    var body: some View {
        List {
            Section {
                Text(
                    "Add latitude and longitude coordinates to target specific locations. You can add multiple coordinates to target different areas."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                ForEach(coordinates.indices, id: \.self) { index in
                    CoordinateRow(
                        coordinate: coordinates[index],
                        onUpdate: { newCoordinate in
                            coordinates[index] = newCoordinate
                            updateTargeting()
                        }
                    )
                }
                .onDelete { indexSet in
                    coordinates.remove(atOffsets: indexSet)
                    updateTargeting()
                }

                Button {
                    coordinates.append(Targeting.LocationCoordinate(latitude: 0, longitude: 0))
                    updateTargeting()
                } label: {
                    Label("Add Location", systemImage: "plus.circle.fill")
                }
            }

            if !coordinates.isEmpty {
                Section {
                    Button(role: .destructive) {
                        coordinates.removeAll()
                        updateTargeting()
                    } label: {
                        Text("Clear All")
                    }
                }
            }
        }
        .navigationTitle("Location Targeting")
        .onAppear {
            coordinates = targeting.location ?? []
        }
    }

    private func updateTargeting() {
        let uniqueCoordinates = coordinates.reduce(into: [Targeting.LocationCoordinate]()) {
            result, coordinate in
            if !result.contains(coordinate) {
                result.append(coordinate)
            }
        }

        targeting = Targeting(
            geo: targeting.geo,
            location: uniqueCoordinates.isEmpty ? nil : uniqueCoordinates,
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
        HStack {
            VStack(alignment: .leading) {
                Text("Latitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Latitude", text: $latitude)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: latitude) { _, _ in updateCoordinate() }
            }

            VStack(alignment: .leading) {
                Text("Longitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Longitude", text: $longitude)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: longitude) { _, _ in updateCoordinate() }
            }

            Button {
                setRandomCoordinate()
            } label: {
                Image(systemName: "dice")
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: coordinate) { _, newCoordinate in
            latitude = String(newCoordinate.latitude)
            longitude = String(newCoordinate.longitude)
        }
    }

    private func updateCoordinate() {
        guard let lat = Double(latitude),
            let lon = Double(longitude)
        else { return }

        onUpdate(
            Targeting.LocationCoordinate(
                latitude: lat,
                longitude: lon
            ))
    }

    private func setRandomCoordinate() {
        // Random coordinates within reasonable bounds
        let lat = Double.random(in: -90...90)
        let lon = Double.random(in: -180...180)

        latitude = String(format: "%.6f", lat)
        longitude = String(format: "%.6f", lon)
        updateCoordinate()
    }
}
