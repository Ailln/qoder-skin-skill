#!/bin/zsh
# 交付前静态自检：JSON / Node / Shell 语法、皮肤字段一致性、颜色键白名单、VSIX 可解压。
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/validate.sh <皮肤名或目录>"
source "$ROOT_DIR/scripts/_lib.sh"
parse_args "$@"
require_cmd jq node zip unzip
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"

ERRORS=0
WARNINGS=0
ok()   { print -r -- "  ✓ $1" }
warn() { print -r -- "  ! $1"; (( WARNINGS++ )) }
fail() { print -r -- "  ✗ $1"; (( ERRORS++ )) }

PKG="$SKIN_DIR/extension/package.json"
SKIN_JSON="$SKIN_DIR/skin.json"

print -r -- "校验 ${SKIN_DIR:t}"

print -r -- "[1/7] JSON 语法"
THEME_REL="$(jq -r '.contributes.themes[0].path' "$PKG" 2>/dev/null || print -r -- "")"
THEME="$SKIN_DIR/extension/${THEME_REL#./}"
for f in "$PKG" "$SKIN_JSON" "$THEME"; do
  if [[ -f "$f" ]] && jq empty "$f" 2>/dev/null; then
    ok "${f:t}"
  else
    fail "$f 缺失或不是合法 JSON"
  fi
done

print -r -- "[2/7] 运行时与脚本语法"
for f in "$ROOT_DIR"/runtime/*.mjs; do
  node --check "$f" 2>/dev/null && ok "${f:t}" || fail "${f:t} 语法错误"
done
for f in "$ROOT_DIR"/scripts/*.sh; do
  zsh -n "$f" 2>/dev/null && ok "${f:t}" || fail "${f:t} 语法错误"
done

print -r -- "[3/7] 字段一致性"
SKIN_ID="$(jq -r '.id // empty' "$SKIN_JSON")"
PKG_NAME="$(jq -r '.name // empty' "$PKG")"
if [[ -n "$SKIN_ID" && "$SKIN_ID" == "$PKG_NAME" ]]; then
  ok "skin.json id 与扩展 name 一致（$SKIN_ID）"
else
  fail "skin.json id ($SKIN_ID) 与扩展 name ($PKG_NAME) 不一致"
fi
if [[ "$SKIN_ID" =~ '^[a-z0-9][a-z0-9-]{0,63}$' ]]; then
  ok "id 字符集合法"
else
  fail "id 非法：$SKIN_ID"
fi

print -r -- "[4/7] 资源文件"
BG="$SKIN_DIR/$(jq -r '.background // empty' "$SKIN_JSON")"
CSS="$SKIN_DIR/$(jq -r '.css // "skin.css"' "$SKIN_JSON")"
if [[ -f "$BG" ]]; then
  BG_KB=$(( $(stat -f%z "$BG") / 1024 ))
  if (( BG_KB > 1024 )); then
    warn "背景图 ${BG:t} 有 ${BG_KB}KB，建议压成几百 KB 的 WebP（会整段编成 data URL 注入）"
  else
    ok "背景图 ${BG:t}（${BG_KB}KB）"
  fi
else
  fail "背景图缺失：$BG"
fi
if [[ -f "$CSS" ]]; then
  ok "运行时 CSS ${CSS:t}"
  grep -q -- '--qoder-skin-image' "$CSS" && ok "CSS 引用了 --qoder-skin-image" \
    || fail "CSS 没有引用 --qoder-skin-image，注入的背景图不会显示"
  if grep -q 'html::after' "$CSS" && ! grep -q 'pointer-events: none' "$CSS"; then
    fail "存在覆盖层但缺少 pointer-events: none，界面会点不动"
  else
    ok "覆盖层不拦截鼠标事件"
  fi
else
  fail "运行时 CSS 缺失：$CSS"
fi

print -r -- "[5/7] Qoder 私有颜色键白名单"
UNKNOWN="$(jq -r '.colors | keys[] | select(startswith("aicoding."))' "$THEME" 2>/dev/null \
  | sort | comm -23 - "$ROOT_DIR/references/aicoding-keys.txt")"
if [[ -z "$UNKNOWN" ]]; then
  COUNT="$(jq -r '[.colors | keys[] | select(startswith("aicoding."))] | length' "$THEME" 2>/dev/null)"
  ok "aicoding.* 键全部在白名单内（$COUNT 个）"
else
  fail "存在未注册的 aicoding.* 键，Qoder 会报未知配置：$(print -r -- $UNKNOWN | tr '\n' ' ')"
fi

print -r -- "[6/7] 与基线配色的重复度"
BASE_THEME="$ROOT_DIR/skins/qoder-moonlit-sakura/extension/themes/qoder-moonlit-sakura-color-theme.json"
if [[ -f "$BASE_THEME" && "$THEME" != "$BASE_THEME" ]]; then
  TOTAL="$(jq -r '.colors | length' "$THEME")"
  SAME="$(comm -12 \
    <(jq -r '.colors | to_entries[] | "\(.key)=\(.value)"' "$THEME" | sort) \
    <(jq -r '.colors | to_entries[] | "\(.key)=\(.value)"' "$BASE_THEME" | sort) | wc -l | tr -d ' ')"
  if (( TOTAL > 0 && SAME * 5 > TOTAL )); then
    warn "$SAME/$TOTAL 个色值与月夜樱基线完全相同，可能有大片配色忘了改写"
  else
    ok "配色已充分改写（与基线重合 $SAME/$TOTAL）"
  fi
else
  ok "跳过（当前就是基线皮肤）"
fi

print -r -- "[7/7] VSIX 打包"
if VSIX="$("$ROOT_DIR/scripts/package-vsix.sh" "$SKIN_DIR" 2>&1)"; then
  if unzip -tq "$VSIX" >/dev/null 2>&1; then
    ok "${VSIX:t} 打包并校验通过"
  else
    fail "VSIX 解压校验失败：$VSIX"
  fi
else
  fail "打包失败：$VSIX"
fi

print -r -- ""
if (( ERRORS > 0 )); then
  print -r -- "校验未通过：$ERRORS 个错误，$WARNINGS 个警告。"
  exit 1
fi
print -r -- "校验通过（$WARNINGS 个警告）。静态检查只保证文件正确，仍需实机验证编辑器与 Quest。"
