#!/usr/bin/env bash
# DevEco Studio macOS/Linux 构建入口；Windows 可用 DevEco 的终端，见README。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"
DEVECO_PATH="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
export NODE_HOME="${NODE_HOME:-$DEVECO_PATH/tools/node}"
export PATH="$NODE_HOME/bin:$DEVECO_PATH/tools/ohpm/bin:$DEVECO_PATH/tools/hvigor/bin:$PATH"
export DEVECO_SDK_HOME="${OPENHARMONY_SDK_HOME:-${OHOS_BASE_SDK_HOME:-${DEVECO_SDK_HOME:-$HOME/Library/OpenHarmony/Sdk}}}"
export OHOS_BASE_SDK_HOME="$DEVECO_SDK_HOME"
BUILD_PRODUCT="${GREEN_BUILD_PRODUCT:-default}"
case "$BUILD_PRODUCT" in
  default) SDK_API=24 ;;
  api26) SDK_API=26.0.0 ;;
  *) echo "未知构建产品：$BUILD_PRODUCT（支持 default 或 api26）。" >&2; exit 1 ;;
esac
if [ "${1:-}" = "prod" ]; then
  shift
  BUILD_MODE=release
else
  BUILD_MODE=debug
fi
TASK="${1:-assembleHap}"
if [ "$#" -gt 0 ]; then shift; fi
for tool in node ohpm hvigorw; do
  if ! command -v "$tool" >/dev/null; then
    echo "未找到 $tool；请设置 DEVECO_HOME 或使用已配置SDK的DevEco终端。" >&2
    exit 1
  fi
done
if [ "$BUILD_PRODUCT" = api26 ] && [ -f local.properties ]; then
  SDK_CONFIGURED="$(node -e 'const fs=require("fs");const m=fs.readFileSync("local.properties","utf8").match(/^\s*sdk\.dir\s*=\s*(.*?)\s*$/m);if(m)process.stdout.write(m[1].replace(/\\([ :\\])/g,"$1"))')"
  if [ -n "$SDK_CONFIGURED" ] && [ "$SDK_CONFIGURED" != "$DEVECO_SDK_HOME" ]; then
    echo "local.properties 的 sdk.dir 指向 $SDK_CONFIGURED，优先于当前 SDK 路径 $DEVECO_SDK_HOME；请先统一配置，避免使用错误版本。" >&2
    exit 1
  fi
fi
if [ ! -d "$DEVECO_SDK_HOME/$SDK_API/ets" ]; then
  echo "未找到 API $SDK_API SDK：$DEVECO_SDK_HOME/$SDK_API/ets。请先配置SDK，macOS可运行 scripts/setup-sdk.sh。" >&2
  exit 1
fi
if [ ! -d oh_modules ]; then ohpm install; fi
printf '[build] product=%s mode=%s task=%s\n' "$BUILD_PRODUCT" "$BUILD_MODE" "$TASK"
exec hvigorw --mode module -p module=entry@default -p "product=$BUILD_PRODUCT" -p "buildMode=$BUILD_MODE" "$TASK" --no-daemon "$@"
