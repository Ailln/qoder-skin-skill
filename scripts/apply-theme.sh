#!/bin/zsh
# 把皮肤的颜色主题写进 Qoder 的 settings.json，省掉手工在菜单里选。
#
# 关键：workbench.colorTheme 匹配的是主题的 id，不是 label。
# 写 label（比如「Qoder 像素猫」）会解析失败并静默回落到默认主题。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/apply-theme.sh <皮肤名或目录>"
source "$ROOT_DIR/scripts/_lib.sh"
parse_args "$@"
require_cmd jq
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"

PKG="$SKIN_DIR/extension/package.json"
THEME_ID="$(jq -r '.contributes.themes[0].id // .contributes.themes[0].label' "$PKG")"
THEME_LABEL="$(jq -r '.contributes.themes[0].label' "$PKG")"

# 中文版是 QoderCN，英文版是 Qoder；按最近修改时间挑正在用的那个。
SETTINGS="${QODER_SETTINGS:-}"
if [[ -z "$SETTINGS" ]]; then
  CANDIDATES=($HOME/Library/Application\ Support/QoderCN/User/settings.json(Nom) \
              $HOME/Library/Application\ Support/Qoder/User/settings.json(Nom))
  if (( ${#CANDIDATES} == 0 )); then
    print -u2 -r -- "找不到 Qoder 的 settings.json，可用 QODER_SETTINGS 环境变量指定。"
    exit 1
  fi
  SETTINGS="${CANDIDATES[1]}"
fi

if [[ ! -f "$SETTINGS" ]]; then
  print -u2 -r -- "settings.json 不存在：$SETTINGS"
  exit 1
fi

BACKUP="$SETTINGS.qoder-skin-backup"
if [[ ! -f "$BACKUP" ]]; then
  cp "$SETTINGS" "$BACKUP"
  print -r -- "已备份原设置到 ${BACKUP:t}"
fi

PREVIOUS="$(jq -r '."workbench.colorTheme" // "(未设置)"' "$SETTINGS")"
TMP="$(mktemp)"
jq --arg id "$THEME_ID" '."workbench.colorTheme" = $id' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

print -r -- "颜色主题已切换：$PREVIOUS → $THEME_ID（$THEME_LABEL）"
print -r -- "  配置文件：$SETTINGS"
print -r -- "  Qoder 正在运行时会立即生效；若主题是刚安装的，需要重载窗口才注册。"
