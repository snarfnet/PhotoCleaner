import SwiftUI
import Photos

struct PhotoThumbnail: View {
    let asset: PHAsset
    let size: CGSize
    @ObservedObject var service: PhotoScanService
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                    )
            }
        }
        .onAppear {
            guard image == nil else { return }
            service.loadThumbnail(for: asset, size: CGSize(width: size.width * 2, height: size.height * 2)) { img in
                image = img
            }
        }
    }
}
