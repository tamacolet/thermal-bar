# 熱モニター

Mac の温度・ファン・消費電力とサーマルスロットリング状態をメニューバーに表示する小さなアプリです。

![screenshot](docs/screenshot.png)

## 動作環境

- Apple Silicon 搭載 Mac
- macOS 14 以降

## インストール

1. [Releases](../../releases) から `ThermalBar.dmg` をダウンロードして開く
2. `熱モニター.app` を横の「Applications」へドラッグ
3. 「アプリケーション」から開く。初回だけ「開けません」と出るので、「システム設定 > プライバシーとセキュリティ」の下にある「このまま開く」を押す（Apple の公証をしていない無料配布のため。2回目からは普通に起動します）

## 使い方

- 左クリック: 詳細パネルを開閉
- 右クリック（または control+クリック）: メニュー（「ログイン時に起動」「終了」）

## 表示の意味

- 状態: macOS の熱の段階（Nominal〜Sleeping）を日本語で表示。「速度低下中」以上がサーマルスロットリングです
- メニューバーの丸: 🟢正常 🟡やや高い 🔴速度低下中〜 ⚪不明
- 温度のセンサー名は機種により異なり、取れない項目は「—」と表示します

## ソースからビルド

```sh
brew install macmon
./build.sh          # ~/Applications/熱モニター.app へ配置
./build.sh --selftest  # センサー単体の動作確認
```

## 同梱物のライセンス

- macmon: MIT License — https://github.com/vladkens/macmon

## ライセンス

MIT
