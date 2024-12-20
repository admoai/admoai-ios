import AdMoai
import SwiftUI

struct HomePreview: View {
    let creative: Creative

    var body: some View {
        ZStack {
            // Map background
            Color(.systemGray4)
                .ignoresSafeArea()

            // Ad card
            VStack {
                HorizontalWithCompanionAdView(creative: creative)
                    .padding(.horizontal)
                    .padding(.top, 70)

                Spacer()
            }

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    // Stacked floating buttons
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 44, height: 44)
                            .shadow(radius: 4, y: 2)

                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 44, height: 44)
                            .shadow(radius: 4, y: 2)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 100)
                }
            }

            VStack {
                Spacer()

                VStack {
                    HStack {
                        ForEach(0..<4) { index in
                            if index > 0 {
                                Spacer()
                            }
                            Circle()
                                .fill(index == 1 ? Color.black : Color(.systemGray5))
                                .frame(width: 44, height: 44)
                            if index < 3 {
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                }
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(radius: 8, y: 4)
                .padding(.horizontal, 16)
            }

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
        }
    }
}

#Preview {
    HomePreview(
        creative: try! JSONDecoder().decode(
            Creative.self,
            from: Data(horizontalWithCompanionMockJson.utf8)
        )
    )
}
