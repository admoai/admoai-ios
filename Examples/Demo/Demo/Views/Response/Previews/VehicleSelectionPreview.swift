import AdMoai
import SwiftUI

struct VehicleSelectionPreview: View {
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

                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(Color.black))
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()
            }

            // Bottom sheet
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    // Sheet handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray3))
                        .frame(width: 36, height: 4)

                    ScrollView {
                        VStack(spacing: 24) {
                            // Search bar placeholder
                            HStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 36)
                            }
                            .padding(.horizontal)

                            // Vehicle options and ad
                            VStack(spacing: 24) {
                                // First two vehicle options
                                VStack(spacing: 16) {
                                    ForEach(0..<2) { _ in
                                        HStack(spacing: 12) {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(.systemGray5))
                                                .frame(width: 60, height: 60)

                                            VStack(alignment: .leading, spacing: 4) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 100, height: 16)
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 80, height: 14)
                                            }

                                            Spacer()

                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color(.systemGray5))
                                                .frame(width: 60, height: 20)
                                        }
                                    }
                                }

                                // Ad placement
                                HorizontalAdView(creative: creative)

                                // Last vehicle option
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 60, height: 60)

                                    VStack(alignment: .leading, spacing: 4) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.systemGray5))
                                            .frame(width: 100, height: 16)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.systemGray5))
                                            .frame(width: 80, height: 14)
                                    }

                                    Spacer()

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 60, height: 20)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .frame(height: 400)
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
    VehicleSelectionPreview(
        creative: try! JSONDecoder().decode(Creative.self, from: Data(horizontalMockJson.utf8)))
}
