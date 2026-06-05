import SwiftUI
import Photos

struct GroupDetailView: View {
    let group: SimilarGroup
    @ObservedObject var service: PhotoScanService
    @Environment(\.dismiss) private var dismiss
    @State private var fullScreenAsset: PHAsset?

    private let accentBlue = Color(red: 0.04, green: 0.33, blue: 0.72)
    private let accentGreen = Color(red: 0.06, green: 0.52, blue: 0.36)
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(group.assets, id: \.localIdentifier) { asset in
                        ZStack(alignment: .topTrailing) {
                            PhotoThumbnail(asset: asset, size: CGSize(width: 220, height: 220), service: service)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .overlay(alignment: .topLeading) {
                                    if asset.localIdentifier == group.recommendedKeepIdentifier {
                                        keepBadge
                                            .padding(6)
                                    }
                                }
                                .onTapGesture {
                                    fullScreenAsset = asset
                                }

                            Button {
                                service.toggleSelection(asset)
                            } label: {
                                Image(systemName: service.isSelected(asset) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundColor(service.isSelected(asset) ? .red : .white)
                                    .shadow(radius: 2)
                            }
                            .padding(6)
                        }
                    }
                }
                .padding(4)
            }

            bottomBar
        }
        .navigationTitle("\(group.count)枚の類似写真")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $fullScreenAsset) { asset in
            FullPhotoView(asset: asset)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ConfidenceBadge(confidence: group.confidence)
                Spacer()
                Text("平均 \(String(format: "%.2f", group.averageDistance)) / 最大 \(String(format: "%.2f", group.maxDistance))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(group.confidence.note)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var keepBadge: some View {
        Label("残す候補", systemImage: "checkmark.seal.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(accentGreen)
            .clipShape(Capsule())
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accentBlue)
                    .frame(width: 42, height: 40)
                    .background(accentBlue.opacity(0.12))
                    .clipShape(Capsule())
            }

            Button {
                service.selectAllInGroup(group, keepRecommended: true)
            } label: {
                Label("おすすめ以外", systemImage: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accentBlue)
                    .clipShape(Capsule())
            }

            Button {
                service.selectAllInGroup(group, keepRecommended: false)
            } label: {
                Text("全選択")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accentBlue.opacity(0.12))
                    .clipShape(Capsule())
            }

            Button {
                service.deselectAllInGroup(group)
            } label: {
                Text("解除")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 28)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
    }
}

struct FullPhotoView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onTapGesture { dismiss() }
        .task { loadFullImage() }
    }

    private func loadFullImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1200, height: 1200),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            self.image = image
        }
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}
