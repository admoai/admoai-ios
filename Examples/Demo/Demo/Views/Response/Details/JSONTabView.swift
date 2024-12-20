import AdMoai
import SwiftUI

struct JSONTabView: View {
    let rawResponse: String?

    var body: some View {
        List {
            Section {
                ScrollView([.horizontal], showsIndicators: true) {
                    Text(prettyPrint(rawResponse))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Response Data")
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }

    private func prettyPrint(_ rawJson: String?) -> String {
        guard let jsonData = rawJson?.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let dataArray = json["data"]
        else {
            return "No data available"
        }

        // Handle both array and dictionary cases
        if let data = try? JSONSerialization.data(
            withJSONObject: dataArray,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        ),
            let string = String(data: data, encoding: .utf8)
        {
            return string
        }

        return "Unable to format data"
    }
}
