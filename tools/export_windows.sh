#!/usr/bin/env bash
# Windows 실행 파일(.exe)을 만들고 zip으로 묶는다.
#   tools/export_windows.sh            -> build/CyberUniverse-windows.zip
# 내보내기 템플릿이 없으면 공식 배포본을 내려받아 SHA-512로 검증한 뒤 Windows용만 꺼내 둔다.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="4.5.1-stable"
TEMPLATE_DIR="${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates/${VERSION/-/.}}"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}"
TEMPLATE_FILES=(windows_release_x86_64.exe windows_release_x86_64_console.exe windows_debug_x86_64.exe windows_debug_x86_64_console.exe)

ensure_templates() {
  if [[ -f "$TEMPLATE_DIR/windows_release_x86_64.exe" && -f "$TEMPLATE_DIR/windows_release_x86_64_console.exe" ]]; then
    return
  fi
  local tmp
  tmp="$(mktemp -d)"
  local tpz="Godot_v${VERSION}_export_templates.tpz"
  echo "내보내기 템플릿을 내려받는 중 (약 1.3GB)..." >&2
  curl -fsSL -o "$tmp/$tpz" "$BASE_URL/$tpz"
  curl -fsSL -o "$tmp/SHA512-SUMS.txt" "$BASE_URL/SHA512-SUMS.txt"
  (cd "$tmp" && grep " $tpz\$" SHA512-SUMS.txt | sha512sum -c --quiet - >&2)
  mkdir -p "$TEMPLATE_DIR"
  local entries=(templates/version.txt)
  for file in "${TEMPLATE_FILES[@]}"; do
    entries+=("templates/$file")
  done
  unzip -ojq "$tmp/$tpz" "${entries[@]}" -d "$TEMPLATE_DIR"
  rm -r "$tmp"
}

godot_bin="$(find_godot)"
ensure_templates
import_project "$godot_bin"

out_dir="$ROOT/build/windows"
mkdir -p "$out_dir"
"$godot_bin" --headless --path "$ROOT" --export-release "Windows Desktop" "$out_dir/CyberUniverse.exe" >/dev/null 2>&1
cp "$ROOT/tools/windows_readme.txt" "$out_dir/README.txt"

zip_path="$ROOT/build/CyberUniverse-windows.zip"
rm -f "$zip_path"
(cd "$out_dir" && zip -q -9 "$zip_path" CyberUniverse.exe CyberUniverse.console.exe README.txt)
echo "$zip_path"
