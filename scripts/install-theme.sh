#!/bin/zsh
# 打包并通过 Qoder 自带的 VS Code CLI 安装颜色主题（第一层）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/install-theme.sh <皮肤名或目录>"
source "$ROOT_DIR/scripts/_lib.sh"
parse_args "$@"
require_cmd jq
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"

QODER_CLI="${QODER_CLI:-/Applications/Qoder CN.app/Contents/Resources/app/bin/code}"
if [[ ! -x "$QODER_CLI" ]]; then
  print -u2 -r -- "找不到 Qoder CLI：$QODER_CLI"
  print -u2 -r -- "可用 QODER_CLI 环境变量指定，例如 /Applications/Qoder.app/Contents/Resources/app/bin/code"
  exit 1
fi

VSIX_PATH="$("$ROOT_DIR/scripts/package-vsix.sh" "$SKIN_DIR")"
"$QODER_CLI" --install-extension "$VSIX_PATH" --force

LABEL="$(jq -r '.contributes.themes[0].label' "$SKIN_DIR/extension/package.json")"
print -r -- "主题已安装。请在 Qoder 中选择：文件 → 首选项 → 主题 → 颜色主题 → $LABEL"
