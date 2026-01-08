import AdMoai
import SwiftUI

struct DestinationTargetingPicker: View {
    @Binding var targeting: Targeting
    @Environment(\.dismiss) private var dismiss
    @State private var coordinates: [Targeting.DestinationCoordinate] = []

    var body: some View {
        VStack {
            List {
                Section {
                    Text(
                        "Add destination coordinates with confidence level to target specific destinations. The min_confidence value (0.0-1.0) indicates the minimum confidence required for matching."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if !coordinates.isEmpty {
                    ForEach(0..<coordinates.count, id: \.self) { index in
                        Section {
                            DestinationCoordinateRow(
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
                    coordinates.append((latitude: 0, longitude: 0, minConfidence: 0.5))
                    updateTargeting()
                } label: {
                    Label("Add Destination", systemImage: "plus")
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
                    Label("Add Random Destination", systemImage: "dice")
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
        .navigationTitle("Destination Targeting")
        .onAppear {
            coordinates = targeting.destination ?? []
        }
    }

    private func setRandomCoordinate() -> Targeting.DestinationCoordinate {
        let randomLatitude = (Double.random(in: -90...90) * 10000).rounded() / 10000
        let randomLongitude = (Double.random(in: -180...180) * 10000).rounded() / 10000
        let randomConfidence = (Double.random(in: 0...1) * 100).rounded() / 100
        return (latitude: randomLatitude, longitude: randomLongitude, minConfidence: randomConfidence)
    }

    private func updateTargeting() {
        targeting = Targeting(
            geo: targeting.geo,
            location: targeting.location,
            destination: coordinates.isEmpty ? nil : coordinates,
            custom: targeting.custom
        )
    }
}

private struct DestinationCoordinateRow: View {
    let coordinate: Targeting.DestinationCoordinate
    let onUpdate: (Targeting.DestinationCoordinate) -> Void

    @State private var latitude: String
    @State private var longitude: String
    @State private var minConfidence: String

    init(
        coordinate: Targeting.DestinationCoordinate,
        onUpdate: @escaping (Targeting.DestinationCoordinate) -> Void
    ) {
        self.coordinate = coordinate
        self.onUpdate = onUpdate
        _latitude = State(initialValue: String(coordinate.latitude))
        _longitude = State(initialValue: String(coordinate.longitude))
        _minConfidence = State(initialValue: String(coordinate.minConfidence))
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

            LabeledContent("Min Confidence") {
                TextField("0.0 - 1.0", text: $minConfidence)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: minConfidence) { _, _ in updateCoordinate() }
            }
        }
    }

    private func updateCoordinate() {
        guard let lat = Double(latitude),
            let lon = Double(longitude),
            let conf = Double(minConfidence)
        else {
            return
        }
        onUpdate((latitude: lat, longitude: lon, minConfidence: conf))
    }
}

#Preview {
    NavigationStack {
        DestinationTargetingPicker(targeting: .constant(Targeting()))
    }
}


