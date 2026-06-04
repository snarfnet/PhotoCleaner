import Foundation
import Photos
import UIKit

struct SimilarGroup: Identifiable {
    let id = UUID()
    var assets: [PHAsset]

    var count: Int { assets.count }

    /// Estimated savings in MB
    var estimatedSavings: Double {
        // Rough estimate: each duplicate ~2MB
        Double(max(0, count - 1)) * 2.0
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
