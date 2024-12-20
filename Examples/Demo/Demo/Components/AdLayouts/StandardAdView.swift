import AdMoai
import SwiftUI

struct StandardAdView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    let creative: Creative

    private var coverImage: String {
        creative.contents.getContent(key: "coverImage")?.value.description ?? ""
    }

    private var headline: String {
        creative.contents.getContent(key: "headline")?.value.description ?? ""
    }

    private var bodyText: String {
        creative.contents.getContent(key: "body")?.value.description ?? ""
    }

    private var destinationURL: String {
        creative.contents.getContent(key: "destinationURL")?.value.description ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover Image
            AsyncImage(url: URL(string: coverImage)) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(1.91, contentMode: .fit)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1.91, contentMode: .fit)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(1.91, contentMode: .fit)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                // Headline
                Text(headline)
                    .font(.headline)
                    .lineLimit(2)

                // Body
                Text(bodyText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Advertiser and Ad Badge
                HStack {
                    // Advertiser info
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: creative.advertiser.logoUrl)) { phase in
                            switch phase {
                            case .empty:
                                Image(systemName: "building.2")
                                    .frame(width: 16, height: 16)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            case .failure:
                                Image(systemName: "building.2")
                                    .frame(width: 16, height: 16)
                            @unknown default:
                                EmptyView()
                            }
                        }

                        Text(creative.advertiser.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("Ad")
                        .font(.caption2)
                        .foregroundColor(Color(.systemBackground))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(.label))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 4, y: 3)
        .onAppear {
            viewModel.handleAdImpression(creative: creative, key: "default")
        }
        .onTapGesture {
            viewModel.handleAdClick(creative: creative, key: "default")
        }
    }
}

#Preview {
    let creative = try! JSONDecoder().decode(Creative.self, from: Data(standardMockJson.utf8))

    StandardAdView(creative: creative)
        .environmentObject(ContentViewModel())
        .padding()
}
