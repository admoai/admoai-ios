import AdMoai
import SwiftUI
import UIKit

private class CompanionViewController: UIViewController {
    let creative: Creative
    let onDismiss: () -> Void
    let onAdClick: (Creative, String) -> Void

    init(
        creative: Creative,
        onDismiss: @escaping () -> Void,
        onAdClick: @escaping (Creative, String) -> Void
    ) {
        self.creative = creative
        self.onDismiss = onDismiss
        self.onAdClick = onAdClick
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.8)

        let contentView = CompanionContentView(
            creative: creative,
            onDismiss: onDismiss,
            onAdClick: onAdClick
        )
        .frame(maxWidth: min(UIScreen.main.bounds.width - 48, 400))
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20, y: 10)
        .padding(.horizontal, 24)

        let hostingController = UIHostingController(rootView: contentView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hostingController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])

        hostingController.didMove(toParent: self)

        // Add tap gesture to dismiss
        let tapGesture = UITapGestureRecognizer(
            target: self, action: #selector(handleBackgroundTap))
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if let hostingView = children.first?.view,
            !hostingView.frame.contains(location)
        {
            onDismiss()
            dismiss(animated: true)
        }
    }
}

private struct CompanionContentView: View {
    let creative: Creative
    let onDismiss: () -> Void
    let onAdClick: (Creative, String) -> Void

    private var buttonColor: Color {
        if let color = creative.contents.getContent(key: "buttonColor")?.value.description {
            return Color(hex: color) ?? .blue
        }
        return .blue
    }

    private var buttonTextColor: Color {
        if let color = creative.contents.getContent(key: "buttonTextColor")?.value.description {
            return Color(hex: color) ?? .white
        }
        return .white
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Cover Image
                if let coverImage = creative.contents.getContent(key: "coverImage")?.value
                    .description
                {
                    AsyncImage(url: URL(string: coverImage)) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1.91, contentMode: .fit)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(1.91, contentMode: .fit)
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1.91, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    if let headline = creative.contents.getContent(key: "headline")?.value
                        .description
                    {
                        Text(headline)
                            .font(.title2)
                            .bold()
                    }

                    if let body = creative.contents.getContent(key: "body")?.value.description {
                        Text(body)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    if let cta = creative.contents.getContent(key: "cta")?.value.description {
                        Button(action: {
                            onAdClick(creative, "default")
                            onDismiss()
                        }) {
                            Text(cta)
                                .font(.headline)
                                .foregroundColor(buttonTextColor)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(buttonColor)
                                .cornerRadius(8)
                        }
                    }

                    // Advertiser info
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: creative.advertiser.logoUrl)) { phase in
                            switch phase {
                            case .empty, .failure:
                                Image(systemName: "building.2")
                                    .frame(width: 16, height: 16)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            @unknown default:
                                EmptyView()
                            }
                        }

                        Text(creative.advertiser.name)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("Ad")
                            .font(.caption2)
                            .foregroundColor(Color(.systemBackground))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(.label))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding()
            }
        }
    }
}

struct HorizontalWithCompanionAdView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    let creative: Creative
    private let aspectRatio: CGFloat = 4  // 4:1 ratio
    // @State private var impressionId = UUID()

    private var isImageRight: Bool {
        creative.template.style == "imageRight"
    }

    private var isImageOnly: Bool {
        creative.template.style == "wideImageOnly"
    }

    private var wideImage: String? {
        creative.contents.getContent(key: "wideImage")?.value.description
    }

    private var squareImage: String? {
        creative.contents.getContent(key: "squareImage")?.value.description
    }

    private var headline: String? {
        creative.contents.getContent(key: "headline")?.value.description
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.width / aspectRatio
            let imageSize = height

            if isImageOnly {
                imageOnlyLayout(width: geometry.size.width, height: height)
            } else {
                HStack(spacing: 0) {
                    if !isImageRight {
                        adImage(size: imageSize)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        if let headline = headline {
                            Text(headline)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        advertiserInfoView()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(height: height)

                    if isImageRight {
                        adImage(size: imageSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 4, y: 3)
        // .id(impressionId)
        .onAppear {
            viewModel.handleAdImpression(creative: creative, key: "default")
        }
        // Triggers impression when impression URL changes, this is only for demo purposes
        // for when the refresh button is pressed in the preview result view
        // .onChange(of: creative.tracking.getImpressionUrl(key: "default")) { _ in
        //     impressionId = UUID()
        //     creative.tracking.fireImpression()
        // }
        .onTapGesture {
            // Fire tracking first
            viewModel.handleCustomEvent(tracking: creative.tracking, key: "companionOpened")

            // Create and store view controller
            var viewController: CompanionViewController?
            viewController = CompanionViewController(
                creative: creative,
                onDismiss: { [weak viewController] in
                    viewController?.dismiss(animated: true)
                },
                onAdClick: viewModel.handleAdClick
            )

            // Present if we have a view controller
            if let viewController = viewController,
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first
            {
                window.rootViewController?.present(viewController, animated: true)
            }
        }
    }

    private func imageOnlyLayout(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: wideImage ?? "")) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: width, height: height)
            .clipped()

            HStack {
                advertiserInfoView(isOverlay: true)
            }
            .padding(12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.5),
                        Color.black.opacity(0),
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .frame(height: height)
    }

    private func adImage(size: CGFloat) -> some View {
        Group {
            if let imageUrl = squareImage {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .empty:
                        SkeletonShape(type: .rectangle(cornerRadius: 0))
                            .frame(width: size, height: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: size, height: size)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                SkeletonShape(type: .rectangle(cornerRadius: 0))
                    .frame(width: size, height: size)
            }
        }
    }

    private func advertiserInfoView(isOverlay: Bool = false) -> some View {
        HStack {
            AsyncImage(url: URL(string: creative.advertiser.logoUrl)) { phase in
                switch phase {
                case .empty:
                    SkeletonShape(
                        type: .rectangle(cornerRadius: 4), width: 16, height: 16)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                case .failure:
                    Image(systemName: "building.2")
                        .frame(width: 16, height: 16)
                @unknown default:
                    EmptyView()
                }
            }

            Text(creative.advertiser.name)
                .font(.caption)
                .foregroundColor(isOverlay ? .white : .secondary)

            Spacer()

            Text("Ad")
                .font(.caption2)
                .foregroundColor(Color(.systemBackground))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(.label))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

#Preview {
    let horizontalCreative = try! JSONDecoder().decode(
        Creative.self, from: Data(horizontalWithCompanionMockJson.utf8))
    let imageOnlyCreative = try! JSONDecoder().decode(
        Creative.self, from: Data(horizontalWithCompanionImageOnlyMockJson.utf8))

    VStack(spacing: 20) {
        // Standard horizontal ad with companion
        HorizontalWithCompanionAdView(creative: horizontalCreative)
            .environmentObject(ContentViewModel())

        // Image-only ad with companion
        HorizontalWithCompanionAdView(creative: imageOnlyCreative)
            .environmentObject(ContentViewModel())
    }
    .padding()
    .environmentObject(ContentViewModel())
}
