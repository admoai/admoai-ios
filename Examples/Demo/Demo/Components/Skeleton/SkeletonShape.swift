import SwiftUI

enum SkeletonType {
    case circle
    case rectangle(cornerRadius: CGFloat = 4)
    case text(lines: Int = 1, spacing: CGFloat = 8)
}

struct SkeletonShape: View {
    let type: SkeletonType
    var width: CGFloat?
    var height: CGFloat?

    var body: some View {
        switch type {
        case .circle:
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: width ?? 40, height: height ?? 40)
        case .rectangle(let cornerRadius):
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.2))
                .frame(width: width, height: height)
        case .text(let lines, let spacing):
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<lines, id: \.self) { index in
                    HStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: height ?? 14)
                        if lines > 1 && index == lines - 1 {
                            Spacer(minLength: 0)
                                .frame(maxWidth: .infinity * 0.4)
                        }
                    }
                }
            }
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
        }
    }
}

// Preview provider
struct SkeletonShape_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Circle example
            SkeletonShape(type: .circle)

            // Rectangle example
            SkeletonShape(
                type: .rectangle(cornerRadius: 8),
                width: 200,
                height: 100
            )

            // Single line text
            SkeletonShape(
                type: .text(),
                width: 200
            )

            // Multi-line text
            SkeletonShape(
                type: .text(lines: 3),
                width: 300
            )

            SkeletonShape(
                type: .text(lines: 4)
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
