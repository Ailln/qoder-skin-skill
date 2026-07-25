# 由各脚本 source，调用前需要已设置 ROOT_DIR。

SKIN_ARG=""
PORT_ARG=""

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --port)
        PORT_ARG="${2:-}"
        shift 2
        ;;
      --port=*)
        PORT_ARG="${1#--port=}"
        shift
        ;;
      -h|--help)
        print -r -- "$USAGE"
        exit 0
        ;;
      -*)
        print -u2 -r -- "未知参数：$1"
        print -u2 -r -- "$USAGE"
        exit 1
        ;;
      *)
        if [[ -n "$SKIN_ARG" ]]; then
          print -u2 -r -- "只能指定一个皮肤：$SKIN_ARG / $1"
          exit 1
        fi
        SKIN_ARG="$1"
        shift
        ;;
    esac
  done
}

# 皮肤既可以写目录名（skins/ 下的），也可以写任意路径。
resolve_skin_dir() {
  local arg="$1"
  local dir=""

  if [[ -z "$arg" ]]; then
    print -u2 -r -- "请指定皮肤。可用皮肤："
    list_skins >&2
    exit 1
  fi

  if [[ -d "$ROOT_DIR/skins/$arg" ]]; then
    dir="$ROOT_DIR/skins/$arg"
  elif [[ -d "$arg" ]]; then
    dir="$(cd "$arg" && pwd)"
  else
    print -u2 -r -- "找不到皮肤目录：$arg"
    list_skins >&2
    exit 1
  fi

  if [[ ! -f "$dir/skin.json" ]]; then
    print -u2 -r -- "$dir 缺少 skin.json，不是一个皮肤目录。"
    exit 1
  fi

  print -r -- "$dir"
}

list_skins() {
  print -r -- "  （skins/ 下）"
  local d
  for d in "$ROOT_DIR"/skins/*/skin.json(N); do
    print -r -- "  - ${${d:h}:t}"
  done
}

skin_field() {
  jq -r --arg key "$1" '.[$key] // empty' "$SKIN_DIR/skin.json"
}

# 端口优先级：--port > 环境变量 > skin.json > 9333
resolve_port() {
  local port="${PORT_ARG:-${QODER_SKIN_PORT:-$(skin_field port)}}"
  port="${port:-9333}"
  if [[ ! "$port" =~ '^[0-9]+$' ]] || (( port < 1024 || port > 65535 )); then
    print -u2 -r -- "端口非法：$port"
    exit 1
  fi
  print -r -- "$port"
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      print -u2 -r -- "缺少依赖命令：$cmd"
      exit 1
    fi
  done
}
