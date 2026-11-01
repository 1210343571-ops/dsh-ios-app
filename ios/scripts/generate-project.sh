#!/usr/bin/env bash
# 用 XcodeGen 从 project.yml 生成 DSHMobile.xcodeproj。
# 生成的 .xcodeproj 不入库（见 .gitignore），唯一工程描述是 project.yml。
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  cat <<'EOF'
未找到 xcodegen。请先安装（三选一）：
  brew install xcodegen
  mint run yonaskolb/XcodeGen
  # 或下载 release 二进制：https://github.com/yonaskolb/XcodeGen/releases
EOF
  exit 1
fi

echo "==> xcodegen $(xcodegen --version 2>/dev/null || true)"
echo "==> 正在根据 project.yml 生成工程"
xcodegen generate --spec project.yml

echo "==> 完成：DSHMobile.xcodeproj"
echo "    open DSHMobile.xcodeproj"
echo "    或： xcodebuild -project DSHMobile.xcodeproj -scheme DSHMobile -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO"
