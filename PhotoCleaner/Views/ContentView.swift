import SwiftUI

struct ContentView: View {
    @StateObject private var service = PhotoScanService()

    private let accentBlue = Color(red: 0.04, green: 0.33, blue: 0.72)
    private let accentGreen = Color(red: 0.06, green: 0.52, blue: 0.36)

    var body: some View {
        NavigationStack {
            ZStack {
                background

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
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("ピクチャおそうじ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var background: some View {
        ZStack {
            if case .idle = service.scanState {
                Image("top_background")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .black.opacity(0.1),
                        .black.opacity(0.38),
                        .black.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.98, blue: 1.0),
                        Color(red: 0.90, green: 0.96, blue: 0.93)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("ピクチャおそうじ")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text("似ている写真を見つけて、残す1枚を選びやすくします。")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("端末内で写真を解析", systemImage: "lock.shield")
                Label("信頼度つきで候補を表示", systemImage: "checkmark.seal")
                Label("削除前に必ず確認", systemImage: "hand.tap")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))

            Button {
                service.startScan()
            } label: {
                Label("スキャン開始", systemImage: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
            }

            Text("写真はサーバーへ送りません。似ている候補だけをまとめ、削除は自分で選べます。")
                .font(.caption)
                .foregroundColor(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    private var scanningView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "photo.stack")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(accentBlue)

            Text("写真を確認中")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            ProgressView(value: service.progress)
                .tint(accentGreen)
                .padding(.horizontal, 48)

            Text("\(Int(service.progress * 100))%")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Text("類似候補を探しています。枚数が多いと少し時間がかかります。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var noResultView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(accentGreen)

            Text("類似写真は見つかりませんでした")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text("写真ライブラリはすっきりしています。")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("もう一度スキャン") {
                service.startScan()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(accentBlue)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text(message)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("再試行") {
                service.startScan()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(accentBlue)

            Spacer()
        }
    }
}
