import AdMoai
import SwiftUI

struct PreviewResultView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingResponse = false

    var placementName: String {
        placementMockData.first { $0.id == viewModel.placement.key }?.name
            ?? viewModel.placement.key
    }

    private var hasIssues: Bool {
        guard let response = viewModel.response else { return false }
        return !(response.body.errors?.isEmpty ?? true)
            || !(response.body.warnings?.isEmpty ?? true)
    }

    private var hasErrors: Bool {
        guard let response = viewModel.response else { return false }
        return !(response.body.errors?.isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            if let decision = viewModel.response?.body.data?.first,
                let creative = decision.creatives?.first
            {
                ZStack {
                    Color(.systemGray6)
                        .ignoresSafeArea()

                    switch decision.placement {
                    case "menu":
                        MenuPreview(creative: creative)
                    case "search":
                        SearchPreview(creative: creative)
                    case "promotions":
                        PromotionsPreview(creative: creative)
                    case "rideSummary":
                        RideSummaryPreview(creative: creative)
                    case "home":
                        HomePreview(creative: creative)
                    case "waiting":
                        WaitingPreview(creative: creative)
                    case "vehicleSelection":
                        VehicleSelectionPreview(creative: creative)
                    default:
                        PlaceholderAdView(
                            placement: decision.placement,
                            template: creative.template.key,
                            style: creative.template.style
                        )
                        .padding()
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "eye.slash",
                    description: Text("Make a valid request to see the preview")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }

            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(placementName)
                        .font(.headline)
                    Text(viewModel.placement.key)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        showingResponse = true
                    } label: {
                        if hasIssues {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(hasErrors ? .red : .yellow)
                        } else {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                    }
                    .sheet(isPresented: $showingResponse) {
                        ResponseDetailsView(
                            viewModel: viewModel, selectedTab: hasIssues ? .validation : .contents)
                    }

                    Button {
                        Task {
                            try await viewModel.loadAds()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }
}
