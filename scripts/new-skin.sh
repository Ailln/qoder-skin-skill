#!/bin/zsh
# 以已有皮肤为基线，脚手架出一套新皮肤目录。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE='用法：scripts/new-skin.sh <slug> <显示名> [--desc 描述] [--publisher 发布者] [--from 基线皮肤] [--port 9333]

示例：scripts/new-skin.sh qoder-deep-ocean "Qoder 深海" --desc "冷色调深海主题"'

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || { print -u2 -r -- "缺少依赖命令：$cmd"; exit 1 }
  done
}
require_cmd jq

SLUG=""
DISPLAY=""
DESC=""
PUBLISHER="local"
FROM="qoder-moonlit-sakura"
PORT="9333"

while (( $# > 0 )); do
  case "$1" in
    --desc) DESC="${2:-}"; shift 2 ;;
    --publisher) PUBLISHER="${2:-}"; shift 2 ;;
    --from) FROM="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    -h|--help) print -r -- "$USAGE"; exit 0 ;;
    -*) print -u2 -r -- "未知参数：$1"; print -u2 -r -- "$USAGE"; exit 1 ;;
    *)
      if [[ -z "$SLUG" ]]; then SLUG="$1"
      elif [[ -z "$DISPLAY" ]]; then DISPLAY="$1"
      else print -u2 -r -- "多余参数：$1"; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$SLUG" || -z "$DISPLAY" ]]; then
  print -u2 -r -- "$USAGE"
  exit 1
fi

# slug 会进 DOM id、CSS 选择器和 VSIX Identity，字符集必须收紧。
if [[ ! "$SLUG" =~ '^[a-z0-9][a-z0-9-]{0,63}$' ]]; then
  print -u2 -r -- "slug 非法：$SLUG（只允许小写字母、数字和连字符）"
  exit 1
fi
if [[ ! "$PORT" =~ '^[0-9]+$' ]] || (( PORT < 1024 || PORT > 65535 )); then
  print -u2 -r -- "端口非法：$PORT"
  exit 1
fi
[[ -n "$DESC" ]] || DESC="为 Qoder CN 1.8.x 制作的 $DISPLAY 主题。"

TARGET="$ROOT_DIR/skins/$SLUG"
BASE="$ROOT_DIR/skins/$FROM"
if [[ -e "$TARGET" ]]; then
  print -u2 -r -- "皮肤已存在：$TARGET"
  exit 1
fi
BASE_THEME=("$BASE"/extension/themes/*.json(N))
if (( ${#BASE_THEME} == 0 )); then
  print -u2 -r -- "基线皮肤没有主题文件：$BASE/extension/themes/"
  exit 1
fi

mkdir -p "$TARGET/extension/themes" "$TARGET/assets" "$TARGET/screenshots"

# 扩展清单：用 jq 写值，避免显示名里的特殊字符破坏模板。
jq --arg id "$SLUG" --arg name "$DISPLAY" --arg desc "$DESC" --arg pub "$PUBLISHER" '
  .name = $id
  | .displayName = $name
  | .description = $desc
  | .publisher = $pub
  | .contributes.themes[0].id = $id
  | .contributes.themes[0].label = $name
  | .contributes.themes[0].path = "./themes/\($id)-color-theme.json"
' "$ROOT_DIR/templates/extension/package.json" > "$TARGET/extension/package.json"

# 主题 JSON 直接继承基线的完整颜色键集合（含已验证的 aicoding.* 键），
# 色值交给后续步骤按新配色逐项改写。
jq --arg id "$SLUG" '.name = $id' "${BASE_THEME[1]}" > "$TARGET/extension/themes/$SLUG-color-theme.json"

jq -n --arg id "$SLUG" --argjson port "$PORT" '
  { id: $id, background: "assets/\($id).webp", css: "skin.css", port: $port }
' > "$TARGET/skin.json"

cp "$ROOT_DIR/templates/skin.css" "$TARGET/skin.css"

README_TEMPLATE="$(<"$ROOT_DIR/templates/extension/README.md")"
print -r -- "${README_TEMPLATE//__SKIN_DISPLAY_NAME__/$DISPLAY}" > "$TARGET/extension/README.md"

print -r -- "已创建皮肤骨架：skins/$SLUG（基线：$FROM）"
print -r -- ""
print -r -- "接下来："
print -r -- "  1. 改写 skins/$SLUG/extension/themes/$SLUG-color-theme.json 的全部色值"
print -r -- "  2. 调整 skins/$SLUG/skin.css 顶部六个变量"
print -r -- "  3. 放入背景图 skins/$SLUG/assets/$SLUG.webp"
print -r -- "  4. scripts/validate.sh $SLUG"
