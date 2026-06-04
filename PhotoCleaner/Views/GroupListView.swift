import SwiftUI

struct GroupListView: View {
    @ObservedObject var service: PhotoScanService
    @State private var showDeleteConfirm = false
    @State private var deleteSuccess: Bool?

    private let accentPink = Color(red: 1.0, green: 0.5, blue: 0.6)

    var body: some View {
        VStack(spacing: 0) {
            // Summary header
            summaryHeader

            // Groups list
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

            // Delete button
            if !service.selectedForDeletion.isEmpty {
                deleteBar
            }
        }
        .alert("選択した写真を削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) { performDelete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(service.selectedForDeletion.count)枚の写真をゴミ箱に移動します")
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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(service.scanResult?.groups.count ?? 0)グループ")
                    .font(.system(size: 22, weight: .bold))
                Text("類似写真が見つかりました")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("約\(String(format: "%.0f", service.scanResult?.totalSavingsMB ?? 0))MB")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accentPink)
                Text("節約できます")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var deleteBar: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("\(service.selectedForDeletion.count)枚を削除")
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func performDelete() {
        Task {
            let ok = await service.deleteSelected()
            deleteSuccess = ok
        }
    }
}

// MARK: - Group row
struct GroupRow: View {
    let group: SimilarGroup
    @ObservedObject var service: PhotoScanService

    var body: some View {
        HStack(spacing: 12) {
            // Preview thumbnails (first 3)
            HStack(spacing: -12) {
                ForEach(0..<min(3, group.assets.count), id: \.self) { i in
                    PhotoThumbnail(asset: group.assets[i], size: CGSize(width: 50, height: 50), service: service)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white, lineWidth: 2)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(group.count)枚の類似写真")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                let selectedInGroup = group.assets.filter { service.isSelected($0) }.count
                if selectedInGroup > 0 {
                    Text("\(selectedInGroup)枚選択中")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("約\(String(format: "%.0f", group.estimatedSavings))MB節約")
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
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }
}
