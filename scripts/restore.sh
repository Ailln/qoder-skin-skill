#!/bin/zsh
# 移除运行时注入并停掉注入器。不传皮肤名时清理本项目注入的所有皮肤样式。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/restore.sh [皮肤名或目录] [--port 9333]"
source "$ROOT_DIR/scripts/_lib.sh"
parse_args "$@"
require_cmd node

SKIN_ID=""
SKIN_DIR=""
if [[ -n "$SKIN_ARG" ]]; then
  require_cmd jq
  SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"
  SKIN_ID="$(skin_field id)"
fi
PORT="${PORT_ARG:-${QODER_SKIN_PORT:-9333}}"
if [[ -n "$SKIN_DIR" ]]; then
  PORT="$(resolve_port)"
fi

if curl --silent --fail --max-time 2 "http://127.0.0.1:$PORT/json/list" >/dev/null 2>&1; then
  if [[ -n "$SKIN_ID" ]]; then
    node "$ROOT_DIR/runtime/restore.mjs" --port "$PORT" --id "$SKIN_ID"
  else
    node "$ROOT_DIR/runtime/restore.mjs" --port "$PORT"
  fi
else
  print -r -- "127.0.0.1:$PORT 上没有 CDP 服务，跳过样式移除。"
fi

kill_injector() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 0
  local pid
  pid="$(tr -dc '0-9' < "$pid_file")"
  if [[ -n "$pid" ]] && ps -p "$pid" -o command= 2>/dev/null | grep -q 'runtime/injector.mjs'; then
    kill "$pid"
    print -r -- "已停止注入器进程 $pid"
  fi
  rm -f "$pid_file"
}

if [[ -n "$SKIN_DIR" ]]; then
  kill_injector "$SKIN_DIR/.injector.pid"
else
  for f in "$ROOT_DIR"/skins/*/.injector.pid(N); do
    kill_injector "$f"
  done
fi

print -r -- "背景和玻璃化注入已移除。若要恢复配色，请在 Qoder 中切回内置主题（如 Qoder Dark）。"
