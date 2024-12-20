import AdMoai
import SwiftUI

struct HorizontalAdView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    let creative: Creative
    private let aspectRatio: CGFloat = 4  // 4:1 ratio

    private var isImageRight: Bool {
        creative.template.style == "imageRight"
    }

    private var isImageOnly: Bool {
        creative.template.style == "wideImageOnly"
    }

    private var wideImage: String? {
        creative.contents.getContent(key: "wideImage")?.value.description
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.width / aspectRatio
            let imageSize = height

            if isImageOnly {
                // Image-only layout
                imageOnlyLayout(width: geometry.size.width, height: height)
            } else {
                // Standard horizontal layout with text and square image
                HStack(spacing: 0) {
                    if !isImageRight {
                        adImage(size: imageSize)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        if let headline = creative.contents.getContent(key: "headline")?.value
                            .description
                        {
                            Text(headline)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        // Advertiser info and Ad badge
                        advertiserInfoView()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(height: height)

                    if isImageRight {
                        adImage(size: imageSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 4, y: 3)
        .onAppear {
            viewModel.handleAdImpression(creative: creative, key: "default")
        }
        .onTapGesture {
            viewModel.handleAdClick(creative: creative, key: "default")
        }
    }

    private func imageOnlyLayout(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Wide image
            AsyncImage(url: URL(string: wideImage ?? "")) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: width, height: height)
            .clipped()

            // Overlay with advertiser info
            HStack {
                advertiserInfoView(isOverlay: true)
            }
            .padding(12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.5),
                        Color.black.opacity(0),
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .frame(height: height)
    }

    private func adImage(size: CGFloat) -> some View {
        Group {
            if let imageUrl = creative.contents.getContent(key: "squareImage")?.value.description {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .empty:
                        SkeletonShape(type: .rectangle(cornerRadius: 0))
                            .frame(width: size, height: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: size, height: size)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                SkeletonShape(type: .rectangle(cornerRadius: 0))
                    .frame(width: size, height: size)
            }
        }
    }

    private func advertiserInfoView(isOverlay: Bool = false) -> some View {
        HStack {
            AsyncImage(url: URL(string: creative.advertiser.logoUrl)) { phase in
                switch phase {
                case .empty:
                    SkeletonShape(
                        type: .rectangle(cornerRadius: 4), width: 16, height: 16)
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
                .foregroundColor(isOverlay ? .white : .secondary)

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
}

#Preview {
    VStack(spacing: 20) {
        // Standard horizontal ad
        HorizontalAdView(
            creative: try! JSONDecoder().decode(Creative.self, from: Data(horizontalMockJson.utf8)))
        .environmentObject(ContentViewModel())

        // Image-only ad
        HorizontalAdView(
            creative: try! JSONDecoder().decode(
                Creative.self, from: Data(horizontalImageOnlyMockJson.utf8)))
        .environmentObject(ContentViewModel())
    }
    .padding()
}
