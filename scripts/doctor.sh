#!/bin/zsh
# 换肤环境体检：应用完整性、CDP 状态、注入器、当前主题、已装主题扩展。
# 换肤效果不对时先跑这个，很多“皮肤没生效”其实是环境问题。
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${QODER_APP_PATH:-/Applications/Qoder CN.app}"
PORT="${QODER_SKIN_PORT:-9333}"

ISSUES=0
ok()   { print -r -- "  ✓ $1" }
warn() { print -r -- "  ! $1" }
bad()  { print -r -- "  ✗ $1"; (( ISSUES++ )) }

print -r -- "[1/5] 应用完整性"
if [[ ! -d "$APP_PATH" ]]; then
  bad "找不到 Qoder：$APP_PATH（可用 QODER_APP_PATH 指定）"
else
  WB="$APP_PATH/Contents/Resources/app/out/vs/code/electron-browser/workbench/workbench.html"
  PRODUCT="$APP_PATH/Contents/Resources/app/product.json"
  if [[ -f "$WB" && -f "$PRODUCT" ]] && command -v jq >/dev/null 2>&1; then
    WANT="$(jq -r '.checksums["vs/code/electron-browser/workbench/workbench.html"] // empty' "$PRODUCT")"
    GOT="$(shasum -a 256 -b "$WB" | cut -d' ' -f1 | xxd -r -p | base64 | tr -d '=')"
    if [[ -z "$WANT" ]]; then
      warn "product.json 没有记录 workbench.html 校验和，跳过"
    elif [[ "$WANT" == "$GOT" ]]; then
      ok "workbench.html 未被改动"
    else
      bad "workbench.html 被改过（期望 ${WANT:0:12}… 实际 ${GOT:0:12}…）"
      grep -o 'qoder-background\|custom-css\|vscode-custom' "$WB" 2>/dev/null | sort -u | while read -r m; do
        print -r -- "      发现注入标记：$m"
      done
      print -r -- "      这会触发「安装似乎损坏」提示并使代码签名失效。"
      print -r -- "      本 skill 从不改应用包内文件，这类改动来自其他改文件式的换肤方案。"
    fi
  fi
  if codesign --verify --no-strict "$APP_PATH" 2>/dev/null; then
    ok "代码签名完好"
  else
    bad "代码签名校验失败（应用包被修改过）"
  fi
fi

print -r -- "[2/5] CDP 调试端口"
if curl --silent --fail --max-time 2 "http://127.0.0.1:$PORT/json/list" >/dev/null 2>&1; then
  COUNT="$(curl -s "http://127.0.0.1:$PORT/json/list" | grep -c '"type": "page"' || true)"
  ok "127.0.0.1:$PORT 可用（$COUNT 个 page target）"
else
  if pgrep -f "$APP_PATH/Contents/MacOS/Electron" >/dev/null 2>&1; then
    warn "Qoder 在运行但没有调试端口——多半是从 Dock 点开的，只有颜色主题没有背景图"
  else
    warn "Qoder 未运行"
  fi
fi

print -r -- "[3/5] 注入器进程"
if pgrep -f "runtime/injector.mjs" >/dev/null 2>&1; then
  RUNNING="$(pgrep -f 'runtime/injector.mjs' | wc -l | tr -d ' ')"
  if (( RUNNING > 1 )); then
    bad "有 $RUNNING 个注入器在跑，它们会互相覆盖样式"
  else
    ok "1 个注入器在运行"
  fi
  pgrep -fl "runtime/injector.mjs" | sed 's/^/      /'
else
  warn "没有注入器在运行（只有颜色主题生效）"
fi

print -r -- "[4/5] 当前颜色主题"
SETTINGS="${QODER_SETTINGS:-}"
if [[ -z "$SETTINGS" ]]; then
  CANDIDATES=($HOME/Library/Application\ Support/QoderCN/User/settings.json(Nom) \
              $HOME/Library/Application\ Support/Qoder/User/settings.json(Nom))
  (( ${#CANDIDATES} > 0 )) && SETTINGS="${CANDIDATES[1]}"
fi
if [[ -n "$SETTINGS" && -f "$SETTINGS" ]] && command -v jq >/dev/null 2>&1; then
  CURRENT="$(jq -r '."workbench.colorTheme" // "(未设置)"' "$SETTINGS")"
  ok "workbench.colorTheme = $CURRENT"
  print -r -- "      来自 $SETTINGS"
  print -r -- "      注意这里必须填主题 id，填 label 会静默回落到默认主题。"
else
  warn "找不到 settings.json"
fi

print -r -- "[5/5] 已安装的主题扩展"
EXT_DIRS=($HOME/.qoder-cn/extensions(N) $HOME/.qoder/extensions(N))
if (( ${#EXT_DIRS} == 0 )); then
  warn "找不到扩展目录"
else
  for d in $EXT_DIRS; do
    print -r -- "      $d"
    ls "$d" 2>/dev/null | sed 's/^/        - /' | head -20
  done
  # 改文件式的换肤扩展会反复去 patch workbench.html，是上面完整性告警的常见来源。
  PATCHERS="$(ls $EXT_DIRS 2>/dev/null | grep -iE 'background|custom-css|customize-ui' || true)"
  if [[ -n "$PATCHERS" ]]; then
    warn "以下扩展可能会改写应用包内文件，与本 skill 的注入方式冲突："
    print -r -- "$PATCHERS" | sed 's/^/        - /'
  fi
fi

print -r -- ""
if (( ISSUES > 0 )); then
  print -r -- "发现 $ISSUES 个问题。"
  exit 1
fi
print -r -- "环境正常。"
