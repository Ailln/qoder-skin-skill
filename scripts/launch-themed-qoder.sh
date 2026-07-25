#!/bin/zsh
# 启动带本地调试端口的 Qoder，并拉起背景图注入器（第二层）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/launch-themed-qoder.sh <皮肤名或目录> [--port 9333]"
source "$ROOT_DIR/scripts/_lib.sh"
parse_args "$@"
require_cmd jq node
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"

SKIN_ID="$(skin_field id)"
PORT="$(resolve_port)"
IMAGE="$SKIN_DIR/$(skin_field background)"
CSS="$SKIN_DIR/${$(skin_field css):-skin.css}"
PID_FILE="$SKIN_DIR/.injector.pid"
LOG_DIR="$ROOT_DIR/logs"
LOG_FILE="$LOG_DIR/$SKIN_ID-injector.log"
QODER_LOG_FILE="$LOG_DIR/$SKIN_ID-qoder.log"

APP_PATH="${QODER_APP_PATH:-/Applications/Qoder CN.app}"
QODER_EXECUTABLE="$APP_PATH/Contents/MacOS/Electron"

for f in "$IMAGE" "$CSS"; do
  if [[ ! -f "$f" ]]; then
    print -u2 -r -- "皮肤资源缺失：$f"
    exit 1
  fi
done

if [[ ! -x "$QODER_EXECUTABLE" ]]; then
  print -u2 -r -- "找不到 Qoder 可执行文件：$QODER_EXECUTABLE"
  print -u2 -r -- "可用 QODER_APP_PATH 环境变量指定应用路径。"
  exit 1
fi

# Electron 单实例：已有实例会吞掉 --remote-debugging-port，必须先 ⌘Q 全退。
if pgrep -f "$APP_PATH/Contents/MacOS/Electron" >/dev/null 2>&1; then
  print -u2 -r -- "Qoder 已在运行。请先用 ⌘Q 完全退出（含 Quest 窗口），再重新运行本脚本。"
  exit 2
fi

# 两个注入器同时跑会互相覆盖 style 节点。
if pgrep -f "runtime/injector.mjs" >/dev/null 2>&1; then
  print -u2 -r -- "已有注入器在运行，请先执行 scripts/restore.sh 停掉它："
  pgrep -fl "runtime/injector.mjs" >&2
  exit 3
fi

mkdir -p "$LOG_DIR"

nohup node "$ROOT_DIR/runtime/injector.mjs" \
  --id "$SKIN_ID" \
  --port "$PORT" \
  --image "$IMAGE" \
  --css "$CSS" \
  >"$LOG_FILE" 2>&1 &
print -r -- $! > "$PID_FILE"

nohup "$QODER_EXECUTABLE" \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$PORT" \
  >"$QODER_LOG_FILE" 2>&1 &

print -r -- "已启动 $SKIN_ID（CDP 127.0.0.1:$PORT）"
print -r -- "  注入日志：$LOG_FILE"
print -r -- "  Qoder 日志：$QODER_LOG_FILE（应出现 DevTools listening 才说明调试端口生效）"
