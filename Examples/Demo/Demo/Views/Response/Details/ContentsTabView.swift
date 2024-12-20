import AdMoai
import SwiftUI

struct ContentsTabView: View {
    let creative: Creative

    var body: some View {
        List {
            ForEach(creative.contents, id: \.key) { content in
                Section {
                    ContentValueView(content: content)
                } header: {
                    HStack {
                        Text(content.key)
                            .monospaced()
                            .textCase(nil)
                        Spacer()
                        Text(content.type)
                            .font(.caption2)
                            .monospaced()
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}

private struct ContentValueView: View {
    let content: Content

    var body: some View {
        Group {
            switch content.type {
            case "image":
                ImageContentView(urlString: content.value.description)
            case "color":
                ColorContentView(colorHex: content.value.description)
            default:
                if let value = content.value.description {
                    Text(value)
                        .font(.body)
                }
            }
        }
    }
}

private struct ImageContentView: View {
    let urlString: String?

    var body: some View {
        if let urlString = urlString,
            let url = URL(string: urlString)
        {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            ProgressView()
                                .tint(.gray)
                        }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.gray)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .cornerRadius(8)
        }
    }
}

private struct ColorContentView: View {
    let colorHex: String?

    var body: some View {
        if let colorHex = colorHex {
            HStack {
                Circle()
                    .fill(Color(hex: colorHex) ?? .clear)
                    .frame(width: 24, height: 24)
                Text(colorHex)
                    .monospaced()
            }
        }
    }
}
