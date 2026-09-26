# 熱モニター

`./build.sh` で `~/Applications/熱モニター.app` をビルド・配置し、`open ~/Applications/熱モニター.app` で起動。
メニューバーの丸＋温度をクリックすると詳細パネル。要 `/opt/homebrew/bin/macmon`（無くても温度以外は動く）。
`./build.sh --selftest` でセンサー単体の動作確認。
