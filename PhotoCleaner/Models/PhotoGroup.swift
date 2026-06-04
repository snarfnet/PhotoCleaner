import Foundation
import Photos
import UIKit

struct SimilarGroup: Identifiable {
    let id = UUID()
    var assets: [PHAsset]
    var averageDistance: Float
    var maxDistance: Float
    var recommendedKeepIdentifier: String

    var count: Int { assets.count }
    var recommendedKeepAsset: PHAsset? {
        assets.first { $0.localIdentifier == recommendedKeepIdentifier } ?? assets.first
    }

    var confidence: SimilarityConfidence {
        if maxDistance <= 0.36 { return .high }
        if maxDistance <= 0.48 { return .medium }
        return .needsReview
    }

    /// Estimated savings in MB
    var estimatedSavings: Double {
        // Rough estimate: each duplicate ~2MB
        Double(max(0, count - 1)) * 2.0
    }
}

enum SimilarityConfidence {
    case high
    case medium
    case needsReview

    var title: String {
        switch self {
        case .high: return "かなり近い"
        case .medium: return "似ている"
        case .needsReview: return "要確認"
        }
    }

    var note: String {
        switch self {
        case .high: return "同じ場面の可能性が高いです。"
        case .medium: return "似ています。消す前に見比べてください。"
        case .needsReview: return "誤検出を避けるため、手動確認をおすすめします。"
        }
    }
}

struct ScanResult {
    var groups: [SimilarGroup]

    var totalDuplicates: Int {
        groups.reduce(0) { $0 + max(0, $1.count - 1) }
    }

    var totalSavingsMB: Double {
        groups.reduce(0.0) { $0 + $1.estimatedSavings }
    }
}
