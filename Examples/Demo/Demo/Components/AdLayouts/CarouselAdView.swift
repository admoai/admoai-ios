import AdMoai
import SwiftUI

struct CarouselSlide: Identifiable {
    let id: Int
    let image: String
    let headline: String
    let cta: String
    let url: String
}

struct CarouselAdView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    let creative: Creative
    @State private var currentIndex: Int = 0
    @State private var offset: CGFloat = 0
    @State private var isUserSwiping: Bool = false
    @State private var containerWidth: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let spacing: CGFloat = 16

    private var slides: [CarouselSlide] {
        (1...3).map { index in
            CarouselSlide(
                id: index,
                image: creative.contents.getContent(key: "imageSlide\(index)")?.value.description
                    ?? "",
                headline: creative.contents.getContent(key: "headlineSlide\(index)")?.value
                    .description ?? "",
                cta: creative.contents.getContent(key: "ctaSlide\(index)")?.value.description ?? "",
                url: creative.contents.getContent(key: "URLSlide\(index)")?.value.description ?? ""
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width - 64

            HStack(spacing: spacing) {
                ForEach(slides) { slide in
                    VStack(spacing: 0) {
                        AsyncImage(url: URL(string: slide.image)) { phase in
                            switch phase {
                            case .empty, .failure:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .aspectRatio(16 / 9, contentMode: .fill)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(16 / 9, contentMode: .fill)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: cardWidth)
                        .frame(height: cardWidth * 9 / 16)
                        .clipped()

                        Text(slide.headline)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 4) {
                            Text(slide.cta)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)

                        HStack(spacing: 8) {
                            AsyncImage(url: URL(string: creative.advertiser.logoUrl)) {
                                phase in
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

                            Spacer()

                            Text("Ad")
                                .font(.caption2)
                                .foregroundColor(Color(.systemBackground))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color(.label))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(.white)
                    .cornerRadius(12)
                    .shadow(radius: 4, y: 3)
                    .frame(width: cardWidth)
                    .background(
                        GeometryReader { itemGeometry in
                            Color.clear.onAppear {
                                contentHeight = max(contentHeight, itemGeometry.size.height)
                            }
                        }
                    )
                    .onTapGesture {
                        viewModel.handleAdClick(creative: creative, key: "slide\(slide.id)")
                    }
                    .onAppear {
                        viewModel.handleAdImpression(creative: creative, key: "slide\(slide.id)")
                    }
                }
            }
            .offset(x: -CGFloat(currentIndex) * (cardWidth + spacing) + offset + 32)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isUserSwiping = true
                        offset = value.translation.width
                    }
                    .onEnded { value in
                        let velocity =
                            value.predictedEndTranslation.width - value.translation.width
                        let swipeThreshold: CGFloat = 500

                        withAnimation(.spring()) {
                            if abs(velocity) > swipeThreshold {
                                if velocity > 0 {
                                    currentIndex = max(currentIndex - 1, 0)
                                } else {
                                    currentIndex = min(currentIndex + 1, slides.count - 1)
                                }
                            } else if abs(offset) > cardWidth / 2 {
                                if offset > 0 {
                                    currentIndex = max(currentIndex - 1, 0)
                                } else {
                                    currentIndex = min(currentIndex + 1, slides.count - 1)
                                }
                            }
                            offset = 0
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isUserSwiping = false
                        }
                    }
            )
        }
        .frame(height: contentHeight)
        .onReceive(timer) { _ in
            guard !isUserSwiping else { return }
            withAnimation(.spring()) {
                currentIndex = (currentIndex + 1) % slides.count
            }
        }
    }
}

#Preview {
    let creative = try! JSONDecoder().decode(Creative.self, from: Data(carouselMockJson.utf8))

    CarouselAdView(creative: creative)
        .environmentObject(ContentViewModel())
        .padding()
}
