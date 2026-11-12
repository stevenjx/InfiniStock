#!/bin/zsh
# 业务层自检：把 Model + Store 编译成独立可执行文件并跑断言。
# 不依赖 Xcode 工程，不启动界面，秒级完成。

set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

swiftc -disable-sandbox -parse-as-library -O \
	-o "$OUT/verify" \
	InfiniStock/Model/*.swift \
	InfiniStock/Store/*.swift \
	InfiniStock/Receipt/*.swift \
	InfiniStock/Security/BiometricGate.swift \
	InfiniStock/Search/SpotlightIndexer.swift \
	InfiniStock/Backup/BackupSnapshot.swift \
	InfiniStock/Backup/BackupService.swift \
	Verification/main.swift

"$OUT/verify"
