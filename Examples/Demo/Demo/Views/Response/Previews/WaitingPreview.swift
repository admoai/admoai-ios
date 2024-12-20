import AdMoai
import SwiftUI

struct WaitingPreview: View {
    let creative: Creative

    var body: some View {
        ZStack {
            // Map background
            Color(.systemGray4)
                .ignoresSafeArea()

            // Top buttons
            VStack {
                HStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 32, height: 32)

                    Spacer()

                    Circle()
                        .fill(Color(Color.black))
                        .frame(width: 32, height: 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()
            }

            // Bottom sheet content
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray3))
                        .frame(width: 36, height: 4)

                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.secondary)

                        Text("Looking for a driver...")
                            .foregroundStyle(.secondary)
                    }

                    CarouselAdView(creative: creative)
                        .padding(.horizontal)
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
                .background(
                    Color(.systemBackground)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                topTrailingRadius: 16
                            )
                        )
                        .shadow(radius: 8, y: -4)
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    WaitingPreview(
        creative: try! JSONDecoder().decode(Creative.self, from: Data(carouselMockJson.utf8)))
}
