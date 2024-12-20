import AdMoai
import SwiftUI

struct SearchPreview: View {
    let creative: Creative

    var body: some View {
        VStack(spacing: 16) {
            SkeletonShape(type: .rectangle(cornerRadius: 8), height: 44)
                .padding(.horizontal)

            VStack(spacing: 12) {
                SkeletonShape(type: .text(lines: 3))
                SkeletonShape(type: .text(lines: 4))
            }
            .padding(.horizontal)

            HorizontalAdView(creative: creative)
                .padding(.horizontal)

            VStack(spacing: 12) {
                SkeletonShape(type: .text(lines: 4))
                SkeletonShape(type: .text(lines: 5))
                SkeletonShape(type: .text(lines: 3))
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    SearchPreview(creative: try! JSONDecoder().decode(Creative.self, from: Data(horizontalMockJson.utf8)))
}
