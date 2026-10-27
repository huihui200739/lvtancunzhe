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
if [ ! -d "$DEVECO_SDK_HOME/24/ets" ]; then
  echo "未找到 API 24 SDK：$DEVECO_SDK_HOME/24/ets。请先配置SDK，macOS可运行 scripts/setup-sdk.sh。" >&2
  exit 1
fi
if [ ! -d oh_modules ]; then ohpm install; fi
printf '[build] mode=%s task=%s\n' "$BUILD_MODE" "$TASK"
exec hvigorw --mode module -p module=entry@default -p product=default -p "buildMode=$BUILD_MODE" "$TASK" --no-daemon "$@"
