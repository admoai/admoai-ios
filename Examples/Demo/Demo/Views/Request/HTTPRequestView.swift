import AdMoai
import SwiftUI

struct HTTPRequestView: View {
    let request: HTTPRequest
    @Environment(\.dismiss) private var dismiss

    private var formattedBody: String? {
        guard let body = request.body,
            let json = try? JSONSerialization.jsonObject(with: body),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .withoutEscapingSlashes]
            ),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else { return nil }

        return prettyString
    }

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

                if let body = formattedBody {
                    Section("Body") {
                        Text(body)
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

#Preview {
    HTTPRequestView(
        request: HTTPRequest(
            path: "/v1/decisions",
            method: .get,
            headers: [:],
            body: """
                {
                  "placement": {
                    "key": "home",
                    "count": 1,
                    "format": "native",
                    "advertiserId": "sample_advertiser",
                    "templateId": "default_template"
                  },
                  "app": {
                    "name": "AdMoai Demo",
                    "version": "1.0.0",
                    "buildNumber": "1",
                    "identifier": "com.admoai.demo",
                    "language": "en"
                  },
                  "device": {
                    "id": "\(getDeviceDetails().id ?? "")",
                    "model": "\(getDeviceDetails().model ?? "")",
                    "manufacturer": "\(getDeviceDetails().manufacturer ?? "")",
                    "os": "\(getDeviceDetails().os ?? "")",
                    "osVersion": "\(getDeviceDetails().osVersion ?? "")",
                    "timezone": "\(getDeviceDetails().timezone ?? "")",
                    "language": "\(getDeviceDetails().language ?? "")"
                  },
                  "targeting": {
                    "geo": [1234, 5678],
                    "location": [
                      {
                        "latitude": 37.7749,
                        "longitude": -122.4194
                      },
                      {
                        "latitude": 40.7128,
                        "longitude": -74.0060
                      }
                    ],
                    "custom": [
                      {
                        "key": "category",
                        "value": "news"
                      }
                    ]
                  },
                  "user": {
                    "id": "user_123",
                    "ip": "203.0.113.1",
                    "timezone": "America/Los_Angeles",
                    "consent": {
                      "gdpr": true
                    }
                  }
                }
                """.data(using: .utf8)
        )
    )
}
