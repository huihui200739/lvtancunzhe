#!/usr/bin/env bash
# 下载拍照辅助记账使用的 MindSpore Lite 端侧模型（11MB，超出仓库单文件上限，不纳入Git）。
set -euo pipefail
DEST="$(cd "$(dirname "$0")/.." && pwd)/entry/src/main/resources/rawfile/model/mobilenetv2_openimage.ms"
URL="https://download.mindspore.cn/model_zoo/official/lite/mobilenetv2_openimage_lite/1.5/mobilenetv2.ms"
SHA="d2e92f251021d17ed29f0d4484f050285534873b644e7dfa4cbd4e26ce999d94"
if [ ! -f "$DEST" ]; then curl -fL --retry 2 -o "$DEST.part" "$URL" && mv "$DEST.part" "$DEST"; fi
ACTUAL="$(shasum -a 256 "$DEST" | cut -d' ' -f1)"
[ "$ACTUAL" = "$SHA" ] || { echo "模型哈希不符：$ACTUAL" >&2; exit 1; }
echo "模型就绪：$DEST"
