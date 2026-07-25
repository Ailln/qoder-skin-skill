#!/bin/zsh
# 通过 CDP 给所有 Qoder 渲染页面截图，用于换肤后自己核对效果。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/screenshot.sh <皮肤名或目录> [--port 9333]"
source "$ROOT_DIR/scripts/_lib.sh"
parse_args "$@"
require_cmd jq node
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"
PORT="$(resolve_port)"

if ! curl --silent --fail --max-time 2 "http://127.0.0.1:$PORT/json/list" >/dev/null 2>&1; then
  print -u2 -r -- "127.0.0.1:$PORT 上没有 CDP 服务。"
  print -u2 -r -- "截图需要用 scripts/launch-themed-qoder.sh 启动的 Qoder，从 Dock 点开的没有调试端口。"
  exit 1
fi

node "$ROOT_DIR/runtime/screenshot.mjs" --port "$PORT" --out "$SKIN_DIR/screenshots"
