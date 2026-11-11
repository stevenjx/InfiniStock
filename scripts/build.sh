#!/bin/zsh
# 构建一个可直接双击运行的 InfiniStock.app 到 ./build
#
# 用法：
#   ./scripts/build.sh            # Debug
#   ./scripts/build.sh Release    # Release
#
# 若命令行编译报宏插件错误（"malformed response"），说明当前环境禁止 sandbox-exec：
#   SWIFT_NO_SANDBOX=1 ./scripts/build.sh

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"

CMD=(
	xcodebuild
	-project InfiniStock.xcodeproj
	-scheme InfiniStock
	-configuration "$CONFIG"
	-destination "platform=macOS"
	CONFIGURATION_BUILD_DIR="$PWD/build"
	CODE_SIGN_IDENTITY=-
	CODE_SIGN_STYLE=Manual
)

if [[ "${SWIFT_NO_SANDBOX:-0}" == "1" ]]; then
	CMD+=(OTHER_SWIFT_FLAGS=-disable-sandbox)
fi

CMD+=(build)
"${CMD[@]}"

APP="$PWD/build/InfiniStock.app"
echo ""
echo "构建完成：$APP"
echo "打开方式：open \"$APP\""
