#!/bin/zsh
# 手工打包 VSIX，不依赖 vsce / npm。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="用法：scripts/package-vsix.sh <皮肤名或目录>"
source "$ROOT_DIR/scripts/_lib.sh"
parse_args "$@"
require_cmd jq zip
SKIN_DIR="$(resolve_skin_dir "$SKIN_ARG")"

PKG="$SKIN_DIR/extension/package.json"
if [[ ! -f "$PKG" ]]; then
  print -u2 -r -- "找不到扩展清单：$PKG"
  exit 1
fi

NAME="$(jq -r '.name' "$PKG")"
VERSION="$(jq -r '.version' "$PKG")"
PUBLISHER="$(jq -r '.publisher' "$PKG")"
DISPLAY_NAME="$(jq -r '.displayName | @html' "$PKG")"
DESCRIPTION="$(jq -r '.description | @html' "$PKG")"
TAGS="$(jq -r '(.keywords // []) | join(",") | @html' "$PKG")"

if [[ ! "$NAME" =~ '^[a-z0-9][a-z0-9-]*$' ]]; then
  print -u2 -r -- "扩展 name 非法：$NAME（只允许小写字母、数字和连字符）"
  exit 1
fi

BUILD_DIR="$SKIN_DIR/.vsix-build"
VSIX_PATH="$SKIN_DIR/dist/$NAME-$VERSION.vsix"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/extension" "$SKIN_DIR/dist"
cp -R "$SKIN_DIR/extension/." "$BUILD_DIR/extension/"

cat > "$BUILD_DIR/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json"/>
  <Default Extension="md" ContentType="text/markdown"/>
  <Default Extension="png" ContentType="image/png"/>
  <Default Extension="webp" ContentType="image/webp"/>
  <Default Extension="vsixmanifest" ContentType="text/xml"/>
</Types>
XML

cat > "$BUILD_DIR/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="zh-CN" Id="$NAME" Version="$VERSION" Publisher="$PUBLISHER"/>
    <DisplayName>$DISPLAY_NAME</DisplayName>
    <Description xml:space="preserve">$DESCRIPTION</Description>
    <Tags>$TAGS</Tags>
    <Categories>Themes</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.103.0"/>
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
XML

# zip 默认追加，重复打包会把旧条目留在包里，必须先删。
rm -f "$VSIX_PATH"
(
  cd "$BUILD_DIR"
  zip -q -r "$VSIX_PATH" .
)

rm -rf "$BUILD_DIR"
print -r -- "$VSIX_PATH"
