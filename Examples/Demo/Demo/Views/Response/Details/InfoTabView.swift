import AdMoai
import SwiftUI

struct InfoTabView: View {
    let creative: Creative

    var body: some View {
        List {
            Section {
                AdvertiserView(advertiser: creative.advertiser)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Advertiser")
            } footer: {
                Text("This is the advertiser for the creative.")
            }

            Section {
                LabeledContent("Key") {
                    Text(creative.template.key)
                        .monospaced()
                }
                .font(.caption)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                LabeledContent("Style") {
                    Text(creative.template.style)
                        .monospaced()
                }
                .font(.caption)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } header: {
                Text("Template")
            } footer: {
                Text("Use the key and style to identify the template and build your own creative.")
            }

            if let metadata = creative.metadata {
                Section {
                    Group {
                        LabeledContent("Ad ID") {
                            Text(metadata.adId)
                                .monospaced()
                        }

                        LabeledContent("Creative ID") {
                            Text(metadata.creativeId)
                                .monospaced()
                        }

                        LabeledContent("Advertiser ID") {
                            Text(metadata.advertiserId)
                                .monospaced()
                        }

                        LabeledContent("Template ID") {
                            Text(metadata.templateId)
                                .monospaced()
                        }

                        LabeledContent("Placement ID") {
                            Text(metadata.placementId)
                                .monospaced()
                        }

                        LabeledContent("Priority") {
                            Text(metadata.priority)
                        }

                        LabeledContent("Language") {
                            Text(metadata.language)
                        }
                    }
                    .font(.caption)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } header: {
                    Text("Metadata")
                } footer: {
                    Text("This is the metadata for the creative.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}

private struct AdvertiserView: View {
    let advertiser: Advertiser

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: advertiser.logoUrl)) { phase in
                switch phase {
                case .empty:
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .tint(.gray)
                        }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.gray)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(advertiser.name)
                    .font(.subheadline)
                    .bold()
                Text(advertiser.legalName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
