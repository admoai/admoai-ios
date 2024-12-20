import AdMoai
import SwiftUI

struct CustomTargetingPicker: View {
    @Binding var targeting: Targeting

    var body: some View {
        List {
            Section {
                Text(
                    "Add custom key-value pairs for targeting. Note: This demo only supports string values, but the SDK supports boolean and numeric values as well.\n\nThe key and value must be valid according to the ad server preset settings. For this demo you can use 'category' as a valid key with possible values like 'sports', 'news', 'entertainment', or 'technology'."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                ForEach((targeting.custom ?? []).indices, id: \.self) { index in
                    CustomTargetRow(
                        keyValue: (targeting.custom ?? [])[index],
                        onUpdate: { newKeyValue in
                            var newCustoms = targeting.custom ?? []
                            newCustoms[index] = newKeyValue
                            targeting = Targeting(
                                geo: targeting.geo,
                                location: targeting.location,
                                custom: newCustoms.isEmpty ? nil : newCustoms
                            )
                        }
                    )
                }
                .onDelete { indexSet in
                    var newCustoms = targeting.custom ?? []
                    newCustoms.remove(atOffsets: indexSet)
                    targeting = Targeting(
                        geo: targeting.geo,
                        location: targeting.location,
                        custom: newCustoms.isEmpty ? nil : newCustoms
                    )
                }

                Button {
                    var newCustoms = targeting.custom ?? []
                    newCustoms.append(
                        Targeting.CustomKeyValue(
                            key: "",
                            value: AnyCodable("")
                        )
                    )
                    targeting = Targeting(
                        geo: targeting.geo,
                        location: targeting.location,
                        custom: newCustoms
                    )
                } label: {
                    Label("Add Custom Target", systemImage: "plus.circle.fill")
                }
            }

            if !(targeting.custom?.isEmpty ?? true) {
                Section {
                    Button(role: .destructive) {
                        targeting = Targeting(
                            geo: targeting.geo,
                            location: targeting.location,
                            custom: nil
                        )
                    } label: {
                        Text("Clear All")
                    }
                }
            }
        }
        .navigationTitle("Custom Targeting")
    }
}

private struct CustomTargetRow: View {
    let keyValue: Targeting.CustomKeyValue
    let onUpdate: (Targeting.CustomKeyValue) -> Void

    @State private var key: String
    @State private var value: String

    init(keyValue: Targeting.CustomKeyValue, onUpdate: @escaping (Targeting.CustomKeyValue) -> Void)
    {
        self.keyValue = keyValue
        self.onUpdate = onUpdate
        _key = State(initialValue: keyValue.key)

        // Extract just the value from AnyCodable(value: "actual_value")
        let fullString = String(describing: keyValue.value)
        let valueStart = fullString.firstIndex(of: "\"")
        let valueEnd = fullString.lastIndex(of: "\"")

        if let start = valueStart, let end = valueEnd,
            start != end
        {
            let startIndex = fullString.index(after: start)
            let value = String(fullString[startIndex..<end])
            _value = State(initialValue: value)
        } else {
            _value = State(initialValue: "")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("Key", text: $key)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            TextField("Value", text: $value)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
        }
        .padding(.vertical, 8)
        .onChange(of: key) { _ in
            guard !key.isEmpty else { return }
            onUpdate(.init(key: key, value: AnyCodable(value)))
        }
        .onChange(of: value) { _ in
            guard !key.isEmpty else { return }
            onUpdate(.init(key: key, value: AnyCodable(value)))
        }
    }
}
