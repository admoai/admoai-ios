import AdMoai
import SwiftUI

struct CustomTargetingPicker: View {
    @Binding var targeting: Targeting
    @State private var customs: [Targeting.CustomKeyValue] = []

    var body: some View {
        VStack {
            List {
                Section {
                    Text("""
Add custom key-value pairs for targeting. Note: This demo only supports string values, but the SDK supports boolean and numeric values as well.

The key and value must be valid according to the ad server preset settings. For this demo you can use 'category' as a valid key with possible values like 'sports', 'news', 'entertainment', or 'technology'.
"""
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if !customs.isEmpty {
                    ForEach(0..<customs.count, id: \.self) { index in
                        Section {
                            CustomTargetRow(
                                keyValue: customs[index],
                                onUpdate: { newKeyValue in
                                    customs[index] = newKeyValue
                                    updateTargeting()
                                }
                            )
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                customs.remove(at: index)
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
                    customs.append((key: "", value: ""))
                    updateTargeting()
                } label: {
                    Label("Add Custom Target", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    customs.removeAll()
                    updateTargeting()
                } label: {
                    Text("Clear All")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.red)
                        .padding(.vertical, 12)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(customs.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .navigationTitle("Custom Targeting")
        .onAppear {
            customs = targeting.custom ?? []
        }
    }

    private func updateTargeting() {
        targeting = Targeting(
            geo: targeting.geo,
            location: targeting.location,
            custom: customs.isEmpty ? nil : customs
        )
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
        _value = State(initialValue: keyValue.value as? String ?? "")
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
            onUpdate((key: key, value: value))
        }
        .onChange(of: value) { _ in
            guard !key.isEmpty else { return }
            onUpdate((key: key, value: value))
        }
    }
}

#Preview {
    NavigationStack {
        CustomTargetingPicker(targeting: .constant(Targeting()))
    }
}
