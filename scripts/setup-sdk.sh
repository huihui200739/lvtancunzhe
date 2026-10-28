#!/usr/bin/env bash
# 将DevEco随附SDK映射到hvigor支持的版本目录；已有真实目录不会被删除。
set -euo pipefail
DEVECO_PATH="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
SDK_SOURCE="${ARKTS_SDK_HOME:-$DEVECO_PATH/sdk/default/openharmony}"
SDK_DEST="${OPENHARMONY_SDK_HOME:-${OHOS_BASE_SDK_HOME:-${DEVECO_SDK_HOME:-$HOME/Library/OpenHarmony/Sdk}}}"
if [ ! -f "$SDK_SOURCE/ets/oh-uni-package.json" ]; then
  echo "未找到SDK元数据：$SDK_SOURCE/ets/oh-uni-package.json" >&2; exit 1
fi
SDK_NODE="${NODE_HOME:-$DEVECO_PATH/tools/node}/bin/node"
if [ ! -x "$SDK_NODE" ]; then SDK_NODE="$(command -v node)"; fi
API_VERSION="$("$SDK_NODE" -e 'console.log(require(process.argv[1]).apiVersion)' "$SDK_SOURCE/ets/oh-uni-package.json")"
BUILD_PRODUCT="${GREEN_BUILD_PRODUCT:-default}"
case "$BUILD_PRODUCT" in
  default) EXPECTED_API=24; SDK_DIRECTORY=24 ;;
  api26) EXPECTED_API=26; SDK_DIRECTORY=26.0.0 ;;
  *) echo "未知构建产品：$BUILD_PRODUCT（支持 default 或 api26）。" >&2; exit 1 ;;
esac
if [ "$API_VERSION" != "$EXPECTED_API" ]; then
  echo "构建产品 $BUILD_PRODUCT 需要 API $EXPECTED_API，随附 SDK 为 $API_VERSION；请安装匹配 SDK 或显式配置 SDK 路径。" >&2; exit 1
fi
mkdir -p "$SDK_DEST/$SDK_DIRECTORY"
for component in ets js native toolchains previewer; do
  [ -d "$SDK_SOURCE/$component" ] || continue
  target="$SDK_DEST/$SDK_DIRECTORY/$component"
  if [ -L "$target" ]; then
    ln -sfn "$SDK_SOURCE/$component" "$target"
  elif [ -e "$target" ]; then
    echo "保留已有SDK目录：$target"
  else
    ln -s "$SDK_SOURCE/$component" "$target"
  fi
done
# 仅沿用使用者已经接受的SDK许可文件，不代替使用者接受协议。
LICENSE_SOURCE="$HOME/Library/Huawei/Sdk/licenses/HarmonyOS-SDK"
if [ -f "$LICENSE_SOURCE" ]; then
  mkdir -p "$SDK_DEST/licenses"
  cp -n "$LICENSE_SOURCE" "$SDK_DEST/licenses/" || true
fi
printf 'SDK ready: %s/%s\n' "$SDK_DEST" "$SDK_DIRECTORY"
