#!/bin/zsh
# 通过 CDP 量化所有 Qoder 渲染页面的正文对比度，不达标就非零退出。
# 用来兜住「背景改深了但 Quest 的文字色没跟着改」这类必然不可读的 bug。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/check-contrast.sh <皮肤名或目录> [--port 9333] [--min 4.5]"
source "$ROOT_DIR/scripts/_lib.sh"

MIN_ARG=""
ARGS=()
while (( $# > 0 )); do
  case "$1" in
    --min)   MIN_ARG="${2:-}"; shift 2 ;;
    --min=*) MIN_ARG="${1#--min=}"; shift ;;
    *)       ARGS+=("$1"); shift ;;
  esac
done
parse_args "${ARGS[@]}"
require_cmd node curl
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"
PORT="$(resolve_port)"
MIN="${MIN_ARG:-4.5}"

if ! curl --silent --fail --max-time 2 "http://127.0.0.1:$PORT/json/list" >/dev/null 2>&1; then
  print -u2 -r -- "127.0.0.1:$PORT 上没有 CDP 服务。"
  print -u2 -r -- "对比度检查需要用 scripts/launch-themed-qoder.sh 启动的 Qoder，从 Dock 点开的没有调试端口。"
  exit 1
fi

print -r -- "检查 ${SKIN_DIR:t} 的正文对比度（阈值 ${MIN}:1，大字 3:1）"
node "$ROOT_DIR/runtime/contrast.mjs" --port "$PORT" --min "$MIN"
