import Foundation
import Photos
import Vision
import UIKit

@MainActor
class PhotoScanService: ObservableObject {
    @Published var scanState: ScanState = .idle
    @Published var progress: Double = 0
    @Published var scanResult: ScanResult?
    @Published var selectedForDeletion: Set<String> = [] // PHAsset localIdentifiers

    enum ScanState {
        case idle
        case requesting
        case scanning
        case done
        case error(String)
    }

    private let imageManager = PHCachingImageManager()
    private let requestOptions: PHImageRequestOptions = {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true
        opts.deliveryMode = .fastFormat
        opts.resizeMode = .fast
        return opts
    }()

    // MARK: - Scan

    func startScan() {
        scanState = .requesting
        progress = 0
        scanResult = nil
        selectedForDeletion = []

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized, .limited:
                    self.scanState = .scanning
                    await self.performScan()
                default:
                    self.scanState = .error("写真ライブラリへのアクセスが許可されていません。設定からアクセスを許可してください。")
                }
            }
        }
    }

    private func performScan() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        let totalCount = allPhotos.count
        guard totalCount > 1 else {
            scanResult = ScanResult(groups: [])
            scanState = .done
            return
        }

        // Compute feature prints in background
        let prints: [(PHAsset, VNFeaturePrintObservation)] = await withCheckedContinuation { continuation in
            Task.detached { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                var results: [(PHAsset, VNFeaturePrintObservation)] = []
                let targetSize = CGSize(width: 200, height: 200)

                for i in 0..<totalCount {
                    let asset = allPhotos.object(at: i)

                    // Get thumbnail
                    var image: UIImage?
                    self.imageManager.requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: .aspectFill,
                        options: self.requestOptions
                    ) { img, _ in
                        image = img
                    }

                    guard let img = image, let cgImage = img.cgImage else { continue }

                    // Compute feature print
                    let request = VNGenerateImageFeaturePrintRequest()
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try? handler.perform([request])

                    if let result = request.results?.first as? VNFeaturePrintObservation {
                        results.append((asset, result))
                    }

                    // Update progress on main thread
                    if i % 10 == 0 {
                        let p = Double(i) / Double(totalCount) * 0.8
                        Task { @MainActor in
                            self.progress = p
                        }
                    }
                }
                continuation.resume(returning: results)
            }
        }

        progress = 0.8

        // Group similar photos
        let groups = await withCheckedContinuation { continuation in
            Task.detached {
                var used = Set<Int>()
                var groups: [SimilarGroup] = []
                let threshold: Float = 0.5 // lower = more similar required

                for i in 0..<prints.count {
                    guard !used.contains(i) else { continue }
                    var group = [prints[i].0]
                    used.insert(i)

                    for j in (i + 1)..<prints.count {
                        guard !used.contains(j) else { continue }
                        var distance: Float = 0
                        do {
                            try prints[i].1.computeDistance(&distance, to: prints[j].1)
                        } catch { continue }

                        if distance < threshold {
                            group.append(prints[j].0)
                            used.insert(j)
                        }
                    }

                    if group.count >= 2 {
                        groups.append(SimilarGroup(assets: group))
                    }
                }

                // Sort by group size
                groups.sort { $0.count > $1.count }
                continuation.resume(returning: groups)
            }
        }

        progress = 1.0
        scanResult = ScanResult(groups: groups)
        scanState = .done
    }

    // MARK: - Selection

    func selectAllInGroup(_ group: SimilarGroup, keepFirst: Bool = true) {
        let toSelect = keepFirst ? Array(group.assets.dropFirst()) : group.assets
        for asset in toSelect {
            selectedForDeletion.insert(asset.localIdentifier)
        }
    }

    func deselectAllInGroup(_ group: SimilarGroup) {
        for asset in group.assets {
            selectedForDeletion.remove(asset.localIdentifier)
        }
    }

    func toggleSelection(_ asset: PHAsset) {
        if selectedForDeletion.contains(asset.localIdentifier) {
            selectedForDeletion.remove(asset.localIdentifier)
        } else {
            selectedForDeletion.insert(asset.localIdentifier)
        }
    }

    func isSelected(_ asset: PHAsset) -> Bool {
        selectedForDeletion.contains(asset.localIdentifier)
    }

    // MARK: - Delete

    func deleteSelected() async -> Bool {
        let identifiers = Array(selectedForDeletion)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            // Remove deleted from groups
            selectedForDeletion.removeAll()
            // Re-filter groups
            if var result = scanResult {
                result.groups = result.groups.compactMap { group in
                    let remaining = group.assets.filter { !identifiers.contains($0.localIdentifier) }
                    guard remaining.count >= 2 else { return nil }
                    return SimilarGroup(assets: remaining)
                }
                scanResult = result
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Thumbnail

    func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
            completion(image)
        }
    }
}
