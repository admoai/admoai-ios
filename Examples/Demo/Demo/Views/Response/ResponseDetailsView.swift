import AdMoai
import SwiftUI

enum DataTab {
    case contents
    case info
    case tracking
    case validation
    case json
}

struct ResponseDetailsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    let selectedTab: DataTab
    @State private var currentTab: DataTab

    init(viewModel: ContentViewModel, selectedTab: DataTab) {
        self.viewModel = viewModel
        self.selectedTab = selectedTab
        _currentTab = State(initialValue: selectedTab)
    }

    var body: some View {
        NavigationView {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 0) {
                        Picker("", selection: $currentTab) {
                            Text("Contents").tag(DataTab.contents)
                            Text("Info").tag(DataTab.info)
                            Text("Tracking").tag(DataTab.tracking)
                            Text("Validation").tag(DataTab.validation)
                            Text("JSON").tag(DataTab.json)
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        if let response = viewModel.response {
                            switch currentTab {
                            case .validation:
                                ValidationTabView(response: response)
                            case .json:
                                if response.body.data != nil {
                                    JSONTabView(rawResponse: response.rawBody)
                                } else {
                                    EmptyStateView(tab: .json)
                                }
                            default:
                                if let creative = viewModel.response?.body.data?.first?.creatives?
                                    .first
                                {
                                    switch currentTab {
                                    case .contents:
                                        ContentsTabView(creative: creative)
                                    case .info:
                                        InfoTabView(creative: creative)
                                    case .tracking:
                                        TrackingTabView(creative: creative)
                                    default:
                                        EmptyView()
                                    }
                                } else {
                                    EmptyStateView(tab: currentTab)
                                }
                            }
                        } else {
                            EmptyStateView(tab: currentTab)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .navigationTitle("Response")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct EmptyStateView: View {
    let tab: DataTab

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text(emptyStateMessage)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var emptyStateMessage: String {
        switch tab {
        case .contents:
            return "No content data available"
        case .info:
            return "No creative information available"
        case .tracking:
            return "No tracking data available"
        case .validation:
            return "No validation data available"
        case .json:
            return "No JSON data available"
        }
    }
}

#Preview {
    let mockJson = """
        {
            "success": true,
            "data": [{
                "placement": "home",
                "creatives": [{
                    "contents": [
                        {
                            "key": "headline",
                            "value": "Premium Ride Service - 20% Off Today",
                            "type": "text"
                        },
                        {
                            "key": "coverImage",
                            "value": "https://picsum.photos/800/400",
                            "type": "image"
                        },
                        {
                            "key": "accentColor",
                            "value": "#FF0000",
                            "type": "color"
                        }
                    ],
                    "metadata": {
                        "adId": "123",
                        "creativeId": "456",
                        "advertiserId": "789",
                        "templateId": "home",
                        "placementId": "home",
                        "priority": "high",
                        "language": "en"
                    },
                    "advertiser": {
                        "name": "Ride Share Co",
                        "legalName": "Ride Share Corporation",
                        "logoUrl": "https://picsum.photos/200"
                    },
                    "template": {
                        "key": "horizontalWithCompanion",
                        "style": "default"
                    },
                    "tracking": {
                        "impressions": [
                            {
                                "key": "default",
                                "url": "https://example.com/impression"
                            }
                        ],
                        "clicks": [
                            {
                                "key": "default",
                                "url": "https://example.com/click"
                            },
                            {
                                "key": "default2",
                                "url": "https://example.com/click"
                            }
                        ],
                        "custom": null
                    }
                }]
            }],
            "errors": [
                {
                    "code": 400,
                    "message": "Invalid placement format"
                },
                {
                    "code": 401,
                    "message": "Missing required field"
                }
            ],
            "warnings": [
                {
                    "code": 300,
                    "message": "Deprecated field used"
                },
                {
                    "code": 301,
                    "message": "Performance impact detected"
                }
            ]
        }
        """

    let viewModel = ContentViewModel()
    //    viewModel.decisions = [Decision(from: Data(jsonString: jsonString)!)]
    //    viewModel.decisions = viewModel.response?.body.data ?? []

    return ResponseDetailsView(viewModel: viewModel, selectedTab: .contents)
}
