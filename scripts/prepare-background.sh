#!/bin/zsh
# 把用户提供的任意图片处理成皮肤可用的背景图：
# 统一格式 → 可选水平镜像 → 缩放 → 压成 WebP，同时丢掉 EXIF（含 GPS）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE='用法：scripts/prepare-background.sh <皮肤名或目录> <图片路径> [--flip] [--width 1672] [--quality 82]

  --flip     水平镜像。当图片主体在左侧时用，把主体翻到右侧让开代码区。
  --width    输出宽度，默认 1672（高度按比例）。
  --quality  WebP 质量，默认 82。

示例：scripts/prepare-background.sh qoder-deep-ocean ~/Downloads/ocean.jpg --flip'

source "$ROOT_DIR/scripts/_lib.sh"

SKIN_ARG=""
IMAGE_SRC=""
FLIP=0
WIDTH=1672
QUALITY=82

while (( $# > 0 )); do
  case "$1" in
    --flip) FLIP=1; shift ;;
    --width) WIDTH="${2:-}"; shift 2 ;;
    --quality) QUALITY="${2:-}"; shift 2 ;;
    -h|--help) print -r -- "$USAGE"; exit 0 ;;
    -*) print -u2 -r -- "未知参数：$1"; print -u2 -r -- "$USAGE"; exit 1 ;;
    *)
      if [[ -z "$SKIN_ARG" ]]; then SKIN_ARG="$1"
      elif [[ -z "$IMAGE_SRC" ]]; then IMAGE_SRC="$1"
      else print -u2 -r -- "多余参数：$1"; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$SKIN_ARG" || -z "$IMAGE_SRC" ]]; then
  print -u2 -r -- "$USAGE"
  exit 1
fi

require_cmd jq sips
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"
SKIN_ID="$(skin_field id)"

if [[ ! -f "$IMAGE_SRC" ]]; then
  print -u2 -r -- "找不到图片：$IMAGE_SRC"
  exit 1
fi
if [[ ! "$WIDTH" =~ '^[0-9]+$' ]] || (( WIDTH < 800 || WIDTH > 5000 )); then
  print -u2 -r -- "宽度非法：$WIDTH（800–5000）"
  exit 1
fi
if [[ ! "$QUALITY" =~ '^[0-9]+$' ]] || (( QUALITY < 1 || QUALITY > 100 )); then
  print -u2 -r -- "质量非法：$QUALITY（1–100）"
  exit 1
fi

DEST="$SKIN_DIR/$(skin_field background)"
mkdir -p "${DEST:h}"

SRC_INFO="$(sips -g pixelWidth -g pixelHeight "$IMAGE_SRC" 2>/dev/null || true)"
SRC_W="$(print -r -- "$SRC_INFO" | awk '/pixelWidth/ {print $2}')"
SRC_H="$(print -r -- "$SRC_INFO" | awk '/pixelHeight/ {print $2}')"
if [[ -z "$SRC_W" || -z "$SRC_H" ]]; then
  print -u2 -r -- "读不出图片尺寸，可能不是受支持的图片格式：$IMAGE_SRC"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
WORK="$TMP_DIR/work.png"

# 先统一成 PNG，heic / jpg / tiff 等都能进来；这一步也顺带丢掉 EXIF。
sips -s format png "$IMAGE_SRC" --out "$WORK" >/dev/null
if (( FLIP )); then
  sips -f horizontal "$WORK" >/dev/null
fi
if (( SRC_W > WIDTH )); then
  sips --resampleWidth "$WIDTH" "$WORK" >/dev/null
fi

if command -v cwebp >/dev/null 2>&1; then
  cwebp -quiet -q "$QUALITY" "$WORK" -o "$DEST"
else
  # 没有 cwebp 就退回 PNG，注入器同样支持，只是体积大不少。
  DEST="${DEST%.webp}.png"
  cp "$WORK" "$DEST"
  jq --arg bg "${DEST:t}" '.background = "assets/\($bg)"' "$SKIN_DIR/skin.json" > "$TMP_DIR/skin.json"
  mv "$TMP_DIR/skin.json" "$SKIN_DIR/skin.json"
  print -r -- "没有 cwebp，已退回 PNG（brew install webp 可显著减小体积）"
fi

# 原图留一份备二次编辑，同样转成 PNG 以剥掉元数据。
sips -s format png "$IMAGE_SRC" --out "$SKIN_DIR/assets/$SKIN_ID-source.png" >/dev/null

OUT_INFO="$(sips -g pixelWidth -g pixelHeight "$DEST" 2>/dev/null || true)"
OUT_W="$(print -r -- "$OUT_INFO" | awk '/pixelWidth/ {print $2}')"
OUT_H="$(print -r -- "$OUT_INFO" | awk '/pixelHeight/ {print $2}')"
OUT_KB=$(( $(stat -f%z "$DEST") / 1024 ))

print -r -- "背景图已就绪：${DEST#$ROOT_DIR/}"
print -r -- "  原图 ${SRC_W}×${SRC_H} → 输出 ${OUT_W:-?}×${OUT_H:-?}，${OUT_KB}KB$( (( FLIP )) && print -n -- '，已水平镜像')"
print -r -- "  元数据（含 EXIF / GPS）已在转换中丢弃"

RATIO=$(( SRC_W * 100 / SRC_H ))
if (( RATIO < 140 || RATIO > 210 )); then
  print -r -- "  提示：原图比例 $(printf '%.2f' $(( SRC_W * 1.0 / SRC_H )))，偏离 16:9 较多，铺满窗口时会裁掉不少内容"
fi
