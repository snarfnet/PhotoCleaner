# ピクチャおそうじ Android

個人使用向けのAndroid版です。端末内の写真を読み込み、dHashで似ている写真をまとめます。写真は外部サーバーへ送りません。

## できること

- 端末内の画像を最大2,000枚までスキャン
- 類似写真グループを表示
- 「かなり近い」「似ている」「要確認」の目安を表示
- 解像度、日付、お気に入りを見て「残す候補」を表示
- 削除はAndroid標準の確認画面を通して実行

## ビルド

Android Studioでこのフォルダを開くか、PowerShellで次を実行します。

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME='C:\Users\Windows\AppData\Local\Android\Sdk'
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
.\gradlew.bat :app:assembleDebug
```

APKはここに出ます。

```text
app\build\outputs\apk\debug\app-debug.apk
```

## インストール

端末をUSB接続してUSBデバッグを有効にし、次を実行します。

```powershell
C:\Users\Windows\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r app\build\outputs\apk\debug\app-debug.apk
```

## 注意

今の版は個人使用向けMVPです。Google Play公開用には、リリース署名、プライバシーポリシー、対象SDKに合わせた権限説明、実機での大量写真テストを追加してください。
