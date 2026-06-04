import SwiftUI

struct ContentView: View {
    @StateObject private var service = PhotoScanService()

    // Cute pastel colors
    private let bgGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.95, blue: 0.97),
            Color(red: 0.95, green: 0.95, blue: 1.0)
        ],
        startPoint: .top, endPoint: .bottom
    )
    private let accentPink = Color(red: 1.0, green: 0.5, blue: 0.6)

    var body: some View {
        NavigationStack {
            ZStack {
                bgGradient.ignoresSafeArea()

                switch service.scanState {
                case .idle, .requesting:
                    idleView
                case .scanning:
                    scanningView
                case .done:
                    if let result = service.scanResult, !result.groups.isEmpty {
                        GroupListView(service: service)
                    } else {
                        noResultView
                    }
                case .error(let msg):
                    errorView(msg)
                }
            }
            .navigationTitle("写真おそうじ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Idle
    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("🧹")
                .font(.system(size: 80))

            Text("類似写真をスキャンして\nスマホをスッキリ！")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.7))

            Button {
                service.startScan()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("スキャン開始")
                        .fontWeight(.bold)
                }
                .font(.system(size: 18))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(accentPink)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: accentPink.opacity(0.4), radius: 8, y: 4)
            }
            .padding(.horizontal, 40)

            Text("写真ライブラリをスキャンして\n似ている写真をグループ化します")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Scanning
    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🔍")
                .font(.system(size: 60))

            Text("スキャン中...")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)

            ProgressView(value: service.progress)
                .tint(accentPink)
                .padding(.horizontal, 50)

            Text("\(Int(service.progress * 100))%")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - No results
    private var noResultView: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("✨")
                .font(.system(size: 60))

            Text("類似写真は見つかりませんでした")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)

            Text("写真ライブラリはスッキリです！")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("もう一度スキャン") {
                service.startScan()
            }
            .foregroundColor(accentPink)
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - Error
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Text("⚠️")
                .font(.system(size: 50))

            Text(msg)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("再試行") {
                service.startScan()
            }
            .foregroundColor(accentPink)

            Spacer()
        }
    }
}
