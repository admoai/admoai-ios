import AdMoai
import SwiftUI

struct ValidationTabView: View {
    let response: APIResponse<DecisionResponse>

    var body: some View {
        List {
            Section {
                if let errors = response.body.errors, !errors.isEmpty {
                    ForEach(errors, id: \.code) { error in
                        HStack {
                            Text(String(error.code))
                                .font(.caption)
                                .monospaced()
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(error.message)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No errors found")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } header: {
                Text("Errors")
            }

            Section {
                if let warnings = response.body.warnings, !warnings.isEmpty {
                    ForEach(warnings, id: \.code) { warning in
                        HStack {
                            Text(String(warning.code))
                                .font(.caption)
                                .monospaced()
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(warning.message)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No warnings found")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } header: {
                Text("Warnings")
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}
