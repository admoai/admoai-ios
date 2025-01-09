import AdMoai
import SwiftUI

private enum TrackingButtonState {
    case ready
    case loading
    case success
    case error
}

struct TrackingTabView: View {
    let creative: Creative
    @EnvironmentObject private var viewModel: ContentViewModel

    var body: some View {
        List {
            if !creative.tracking.impressions.isEmpty {
                Section {
                    ForEach(creative.tracking.impressions, id: \.key) { item in
                        TrackingItemView(key: item.key, url: item.url)
                    }
                } header: {
                    Text("Impressions")
                }
            }

            if let clicks = creative.tracking.clicks, !clicks.isEmpty {
                Section {
                    ForEach(clicks, id: \.key) { item in
                        TrackingItemView(key: item.key, url: item.url)
                    }
                } header: {
                    Text("Clicks")
                }
            }

            if let custom = creative.tracking.custom, !custom.isEmpty {
                Section {
                    ForEach(custom, id: \.key) { item in
                        TrackingItemView(key: item.key, url: item.url)
                    }
                } header: {
                    Text("Custom")
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}

struct TrackingItemView: View {
    let key: String
    let url: String
    @State private var buttonState: TrackingButtonState = .ready
    @EnvironmentObject private var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray4))
                    .monospaced()
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                Button {
                    fireTracking()
                } label: {
                    Group {
                        switch buttonState {
                        case .ready:
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.accentColor)
                        case .loading:
                            ProgressView()
                                .controlSize(.small)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .error:
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(buttonState != .ready)
            }
            Text(url)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }

    private func fireTracking() {
        buttonState = .loading

        guard let url = URL(string: url) else {
            buttonState = .error
            return
        }

        viewModel.sdk.fireTracking(url: url.absoluteString)

        buttonState = .success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            buttonState = .ready
        }
    }
}
