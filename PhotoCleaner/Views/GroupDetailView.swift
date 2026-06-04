import SwiftUI
import Photos

struct GroupDetailView: View {
    let group: SimilarGroup
    @ObservedObject var service: PhotoScanService
    @State private var fullScreenAsset: PHAsset?

    private let accentPink = Color(red: 1.0, green: 0.5, blue: 0.6)
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(group.assets, id: \.localIdentifier) { asset in
                        ZStack(alignment: .topTrailing) {
                            PhotoThumbnail(asset: asset, size: CGSize(width: 200, height: 200), service: service)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .onTapGesture {
                                    fullScreenAsset = asset
                                }

                            // Selection checkbox
                            Button {
                                service.toggleSelection(asset)
                            } label: {
                                Image(systemName: service.isSelected(asset) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(service.isSelected(asset) ? .red : .white)
                                    .shadow(radius: 2)
                            }
                            .padding(6)
                        }
                    }
                }
                .padding(4)
            }

            // Bottom bar
            bottomBar
        }
        .navigationTitle("\(group.count)枚の類似写真")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $fullScreenAsset) { asset in
            FullPhotoView(asset: asset)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                service.selectAllInGroup(group, keepFirst: true)
            } label: {
                Text("1枚残して全選択")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(accentPink)
                    .clipShape(Capsule())
            }

            Button {
                service.selectAllInGroup(group, keepFirst: false)
            } label: {
                Text("全選択")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentPink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(accentPink.opacity(0.12))
                    .clipShape(Capsule())
            }

            Button {
                service.deselectAllInGroup(group)
            } label: {
                Text("全解除")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Full screen photo viewer
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
        ) { img, _ in
            image = img
        }
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}
