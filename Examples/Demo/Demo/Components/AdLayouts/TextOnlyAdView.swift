import AdMoai
import SwiftUI

struct TextOnlyAdView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    let creative: Creative

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = creative.contents.getContent(key: "text")?.value.description {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    // Advertiser info
                    HStack(spacing: 6) {
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

                    Text("Sponsored")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .onAppear {
            viewModel.handleAdImpression(creative: creative, key: "default")
        }
        .onTapGesture {
            viewModel.handleAdClick(creative: creative, key: "default")
        }
    }
}

#Preview {
    let creative = try! JSONDecoder().decode(Creative.self, from: Data(textMockJson.utf8))

    TextOnlyAdView(creative: creative)
        .environmentObject(ContentViewModel())
        .padding()
}
