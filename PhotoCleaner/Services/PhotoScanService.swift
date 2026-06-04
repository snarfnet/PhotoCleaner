import Foundation
import Photos
import Vision
import UIKit

@MainActor
class PhotoScanService: ObservableObject {
    @Published var scanState: ScanState = .idle
    @Published var progress: Double = 0
    @Published var scanResult: ScanResult?
    @Published var selectedForDeletion: Set<String> = []

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
        opts.isNetworkAccessAllowed = true
        return opts
    }()

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

        let prints = await buildFeaturePrints(from: allPhotos, totalCount: totalCount)
        progress = 0.8

        let groups = await groupSimilarPhotos(prints)
        progress = 1.0
        scanResult = ScanResult(groups: groups)
        scanState = .done
    }

    private func buildFeaturePrints(
        from allPhotos: PHFetchResult<PHAsset>,
        totalCount: Int
    ) async -> [(PHAsset, VNFeaturePrintObservation)] {
        await withCheckedContinuation { continuation in
            Task.detached { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }

                var results: [(PHAsset, VNFeaturePrintObservation)] = []
                let targetSize = CGSize(width: 224, height: 224)

                for index in 0..<totalCount {
                    let asset = allPhotos.object(at: index)
                    guard let image = self.thumbnailForScan(asset: asset, targetSize: targetSize),
                          let cgImage = image.cgImage else {
                        continue
                    }

                    let request = VNGenerateImageFeaturePrintRequest()
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try? handler.perform([request])

                    if let result = request.results?.first as? VNFeaturePrintObservation {
                        results.append((asset, result))
                    }

                    if index % 10 == 0 {
                        let currentProgress = Double(index) / Double(totalCount) * 0.8
                        Task { @MainActor in
                            self.progress = currentProgress
                        }
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }

    private nonisolated func thumbnailForScan(asset: PHAsset, targetSize: CGSize) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        var image: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            image = result
        }
        return image
    }

    private func groupSimilarPhotos(
        _ prints: [(PHAsset, VNFeaturePrintObservation)]
    ) async -> [SimilarGroup] {
        await withCheckedContinuation { continuation in
            Task.detached {
                var used = Set<Int>()
                var groups: [SimilarGroup] = []
                let candidateThreshold: Float = 0.52

                for index in prints.indices {
                    guard !used.contains(index) else { continue }

                    var groupAssets = [prints[index].0]
                    var distances: [Float] = []
                    used.insert(index)

                    for candidateIndex in prints.indices where candidateIndex > index {
                        guard !used.contains(candidateIndex) else { continue }

                        var distance: Float = 0
                        do {
                            try prints[index].1.computeDistance(&distance, to: prints[candidateIndex].1)
                        } catch {
                            continue
                        }

                        if distance <= candidateThreshold {
                            groupAssets.append(prints[candidateIndex].0)
                            distances.append(distance)
                            used.insert(candidateIndex)
                        }
                    }

                    guard groupAssets.count >= 2 else { continue }

                    let recommended = Self.recommendedKeepAsset(in: groupAssets)
                    let average = distances.isEmpty ? 0 : distances.reduce(0, +) / Float(distances.count)
                    let maximum = distances.max() ?? 0
                    groups.append(
                        SimilarGroup(
                            assets: groupAssets,
                            averageDistance: average,
                            maxDistance: maximum,
                            recommendedKeepIdentifier: recommended.localIdentifier
                        )
                    )
                }

                groups.sort {
                    if $0.confidenceRank != $1.confidenceRank {
                        return $0.confidenceRank < $1.confidenceRank
                    }
                    if $0.count != $1.count {
                        return $0.count > $1.count
                    }
                    return $0.averageDistance < $1.averageDistance
                }
                continuation.resume(returning: groups)
            }
        }
    }

    func selectAllInGroup(_ group: SimilarGroup, keepRecommended: Bool = true) {
        let toSelect = keepRecommended
            ? group.assets.filter { $0.localIdentifier != group.recommendedKeepIdentifier }
            : group.assets

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

    func deleteSelected() async -> Bool {
        let identifiers = Array(selectedForDeletion)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            selectedForDeletion.removeAll()

            if var result = scanResult {
                result.groups = result.groups.compactMap { group in
                    let remaining = group.assets.filter { !identifiers.contains($0.localIdentifier) }
                    guard remaining.count >= 2 else { return nil }
                    let recommended = Self.recommendedKeepAsset(in: remaining)
                    return SimilarGroup(
                        assets: remaining,
                        averageDistance: group.averageDistance,
                        maxDistance: group.maxDistance,
                        recommendedKeepIdentifier: recommended.localIdentifier
                    )
                }
                scanResult = result
            }
            return true
        } catch {
            return false
        }
    }

    func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
            completion(image)
        }
    }

    private nonisolated static func recommendedKeepAsset(in assets: [PHAsset]) -> PHAsset {
        assets.max { lhs, rhs in
            qualityScore(for: lhs) < qualityScore(for: rhs)
        } ?? assets[0]
    }

    private nonisolated static func qualityScore(for asset: PHAsset) -> Double {
        let pixels = Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000
        let favoriteBonus = asset.isFavorite ? 100 : 0
        let recentBonus = (asset.creationDate?.timeIntervalSince1970 ?? 0) / 10_000_000_000
        return Double(favoriteBonus) + pixels + recentBonus
    }
}

private extension SimilarGroup {
    var confidenceRank: Int {
        switch confidence {
        case .high: return 0
        case .medium: return 1
        case .needsReview: return 2
        }
    }
}
