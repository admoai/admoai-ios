import AdMoai
import SwiftUI

struct MenuPreview: View {
    let creative: Creative

    var body: some View {
        ZStack {
            // Background map
            Color(.systemGray4)
                .ignoresSafeArea()

            // Semi-transparent overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            // Menu drawer
            HStack(alignment: .top) {
                VStack(spacing: 0) {
                    // App logo
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .padding(.vertical, 16)

                    // Menu items list
                    VStack(spacing: 0) {
                        ForEach(0..<7) { _ in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 24, height: 24)

                                SkeletonShape(type: .text(lines: 1))

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color(.systemGray3))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)

                            Divider()
                                .padding(.leading, 60)
                        }
                    }

                    Spacer()

                    // Text-only ad
                    TextOnlyAdView(creative: creative)
                        .padding(.horizontal)
                        .padding(.bottom)

                    // Bottom profile section
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            SkeletonShape(type: .text(lines: 1), width: 120)
                            SkeletonShape(type: .text(lines: 1), width: 80)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
                .frame(width: UIScreen.main.bounds.width * 0.85)
                .background(Color(.systemBackground))

                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    MenuPreview(creative: try! JSONDecoder().decode(Creative.self, from: Data(textMockJson.utf8)))
}
