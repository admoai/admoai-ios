import AdMoai
import SwiftUI

struct HTTPRequestView: View {
    let request: HTTPRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Request") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Method")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(request.method.rawValue)
                            .font(.caption.monospaced())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Path")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(request.path)
                            .font(.caption.monospaced())
                    }
                }

                if let headers = request.headers {
                    Section("Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(value)
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                }

                if let body = request.body,
                    let json = try? JSONSerialization.jsonObject(with: body),
                    let prettyData = try? JSONSerialization.data(
                        withJSONObject: json,
                        options: [.prettyPrinted, .withoutEscapingSlashes]
                    ),
                    let prettyString = String(data: prettyData, encoding: .utf8)
                {
                    Section("Body") {
                        Text(prettyString)
                            .font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("HTTP Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
