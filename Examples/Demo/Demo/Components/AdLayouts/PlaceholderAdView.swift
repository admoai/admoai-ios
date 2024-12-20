import AdMoai
import SwiftUI

struct PlaceholderAdView: View {
    let placement: String
    let template: String
    let style: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text(placement)
                    .font(.headline)
                Text("\(template)")
                    .font(.caption)
                    .monospaced()
                    .foregroundColor(.secondary)
                Text("\(style)")
                    .font(.caption)
                    .monospaced()
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 4, y: 3)
    }
}

#Preview {
    PlaceholderAdView(placement: "Placement", template: "Template", style: "Style")
        .padding()
}
