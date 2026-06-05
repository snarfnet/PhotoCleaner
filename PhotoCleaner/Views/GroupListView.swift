import SwiftUI

struct GroupListView: View {
    @ObservedObject var service: PhotoScanService
    @State private var showDeleteConfirm = false
    @State private var deleteSuccess: Bool?

    private let accentBlue = Color(red: 0.04, green: 0.33, blue: 0.72)
    private let accentGreen = Color(red: 0.06, green: 0.52, blue: 0.36)

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.scanResult?.groups ?? []) { group in
                        NavigationLink {
                            GroupDetailView(group: group, service: service)
                        } label: {
                            GroupRow(group: group, service: service)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if service.safeCandidateCount > 0 || !service.selectedForDeletion.isEmpty {
                actionBar
            }
        }
        .alert("選択した写真を削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) { performDelete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(service.selectedForDeletion.count)枚の写真をゴミ箱に移動します。")
        }
        .alert("削除に失敗しました", isPresented: Binding(
            get: { deleteSuccess == false },
            set: { _ in deleteSuccess = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("写真へのアクセス権限やiCloudの状態を確認してください。")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("再スキャン") {
                    service.startScan()
                }
                .font(.caption)
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(service.scanResult?.groups.count ?? 0)グループ")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("類似写真が見つかりました")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("約\(String(format: "%.0f", service.scanResult?.totalSavingsMB ?? 0))MB")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(accentGreen)
                    Text("整理候補")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Label("信頼度が低いグループは自動で決めず、見比べてから選んでください。", systemImage: "eye")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if service.safeCandidateCount > 0 {
                Button {
                    service.selectSafeCandidates()
                } label: {
                    Label("安全候補を一括選択（\(service.safeCandidateCount)枚）", systemImage: "checkmark.seal")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(accentBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(accentBlue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            if !service.selectedForDeletion.isEmpty {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("\(service.selectedForDeletion.count)枚を削除", systemImage: "trash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
    }

    private func performDelete() {
        Task {
            let ok = await service.deleteSelected()
            deleteSuccess = ok
        }
    }
}

struct GroupRow: View {
    let group: SimilarGroup
    @ObservedObject var service: PhotoScanService

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -12) {
                ForEach(0..<min(3, group.assets.count), id: \.self) { index in
                    PhotoThumbnail(asset: group.assets[index], size: CGSize(width: 50, height: 50), service: service)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white, lineWidth: 2)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("\(group.count)枚の類似写真")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    ConfidenceBadge(confidence: group.confidence)
                }

                let selectedInGroup = group.assets.filter { service.isSelected($0) }.count
                if selectedInGroup > 0 {
                    Text("\(selectedInGroup)枚を選択中")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("最大距離 \(String(format: "%.2f", group.maxDistance))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }
}

struct ConfidenceBadge: View {
    let confidence: SimilarityConfidence

    var body: some View {
        Text(confidence.title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch confidence {
        case .high: return Color(red: 0.06, green: 0.52, blue: 0.36)
        case .medium: return Color(red: 0.04, green: 0.33, blue: 0.72)
        case .needsReview: return .orange
        }
    }
}
