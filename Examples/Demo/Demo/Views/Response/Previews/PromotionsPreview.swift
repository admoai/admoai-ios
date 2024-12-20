import AdMoai
import SwiftUI

struct PromotionsPreview: View {
    let creative: Creative

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                VStack(spacing: 16) {

                    // Categories row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonShape(type: .rectangle(cornerRadius: 20))
                                    .frame(width: 80, height: 32)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Carousel ad
                CarouselAdView(creative: creative)
                    .padding(.horizontal)

                // Product grid section
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 16
                ) {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonShape(type: .rectangle())
                                .aspectRatio(1, contentMode: .fit)
                            SkeletonShape(type: .text(lines: 2))
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    PromotionsPreview(creative: try! JSONDecoder().decode(Creative.self, from: Data(carouselMockJson.utf8)))
}
