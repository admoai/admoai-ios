import AdMoai
import SwiftUI

struct RideSummaryPreview: View {
    let creative: Creative

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Top section with addresses and map
                HStack(alignment: .top, spacing: 16) {
                    // Addresses on the left
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonShape(type: .text(lines: 1))
                        HStack(spacing: 8) {
                            SkeletonShape(type: .circle, width: 20)
                            SkeletonShape(type: .text(lines: 2))
                        }

                        HStack(spacing: 8) {
                            SkeletonShape(type: .circle, width: 20)
                            SkeletonShape(type: .text(lines: 2))
                        }
                    }
                    .padding(.horizontal)

                    // Map placeholder on the right
                    SkeletonShape(type: .rectangle(cornerRadius: 8))
                        .frame(height: 120)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Divider()
                    .padding(.horizontal)

                // Ride information grid
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            SkeletonShape(type: .text(lines: 1), width: 160)
                            SkeletonShape(type: .text(lines: 1), width: 130)
                            SkeletonShape(type: .text(lines: 1), width: 140)
                            SkeletonShape(type: .text(lines: 1), width: 150)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            SkeletonShape(type: .text(lines: 1), width: 100)
                            SkeletonShape(type: .text(lines: 1), width: 90)
                            SkeletonShape(type: .text(lines: 1), width: 110)
                            SkeletonShape(type: .text(lines: 1), width: 80)
                        }
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Ad placement
                StandardAdView(creative: creative)
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Text lines after ad
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonShape(type: .text(lines: 3))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color(.systemGray6))
    }
}

#Preview {
    let creative = try! JSONDecoder().decode(Creative.self, from: Data(standardMockJson.utf8))

    RideSummaryPreview(creative: creative)
}
