#!/usr/bin/env bash
# Windows 실행 파일(.exe)을 만들고 zip으로 묶는다.
#   tools/export_windows.sh            -> build/CyberUniverse-windows.zip
# 내보내기 템플릿이 없으면 공식 배포본을 내려받아 SHA-512로 검증한 뒤 Windows용만 꺼내 둔다.
#
# 빌드 번호는 커밋 수(git rev-list --count HEAD)다. 자동 업데이트가 이 번호로 새 버전을 판단한다.
# 이 PC에 캐릭터 모델(저장소에 없는 에셋)이 있으면 모델을 함께 넣은 zip도 만든다:
#   build/CyberUniverse-windows-with-model.zip   (가족 PC에 처음 설치할 때 쓴다. 어디에도 올리지 않는다)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="4.5.1-stable"
# Godot가 내보내기 템플릿을 찾는 위치 (운영체제마다 다르다)
case "$(detect_platform)" in
  windows) DEFAULT_TEMPLATE_ROOT="$(cygpath -u "$APPDATA")/Godot/export_templates" ;;
  macos) DEFAULT_TEMPLATE_ROOT="$HOME/Library/Application Support/Godot/export_templates" ;;
  *) DEFAULT_TEMPLATE_ROOT="$HOME/.local/share/godot/export_templates" ;;
esac
TEMPLATE_DIR="${GODOT_TEMPLATES:-$DEFAULT_TEMPLATE_ROOT/${VERSION/-/.}}"
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
  local entries=(templates/version.txt)
  for file in "${TEMPLATE_FILES[@]}"; do
    entries+=("templates/$file")
  done
  extract_zip "$tmp/$tpz" "$TEMPLATE_DIR" "${entries[@]}"
  rm -r "$tmp"
}

# 내보내는 동안만 빌드 번호를 써 넣고, 끝나면(실패해도) 원래대로 되돌린다.
stamp_build_info() {
  local build_info="$ROOT/src/core/build_info.gd"
  local number commit
  number="$(git -C "$ROOT" rev-list --count HEAD)"
  commit="$(git -C "$ROOT" rev-parse --short HEAD)"
  cp "$build_info" "$build_info.orig"
  trap 'mv "$ROOT/src/core/build_info.gd.orig" "$ROOT/src/core/build_info.gd"' EXIT
  sed -i "s/^const NUMBER := .*/const NUMBER := $number/; s/^const COMMIT := .*/const COMMIT := \"$commit\"/" "$build_info"
  echo "빌드 번호 $number ($commit)" >&2
}

godot_bin="$(find_godot)"
# 자체 포함 모드 Godot(옆에 _sc_ 파일이 있음)는 내보내기 템플릿을 자기 폴더에서만 찾는다.
# 그런 Godot면 내보내기에는 표준 설치본을 따로 받아 쓴다 (테스트는 그대로 그 Godot로 돌려도 된다).
if [[ -f "$(dirname "$godot_bin")/_sc_" || -f "$(dirname "$godot_bin")/._sc_" ]]; then
  echo "자체 포함 모드 Godot라 내보내기용 Godot를 따로 준비합니다." >&2
  godot_bin="$("$ROOT/tools/setup_godot.sh")"
fi
ensure_templates
stamp_build_info
import_project "$godot_bin"

out_dir="$ROOT/build/windows"
rm -rf "$out_dir"
mkdir -p "$out_dir"
export_log="$ROOT/build/export.log"
if ! "$godot_bin" --headless --path "$ROOT" --export-release "Windows Desktop" "$out_dir/CyberUniverse.exe" >"$export_log" 2>&1; then
  echo "내보내기에 실패했습니다. 기록: $export_log" >&2
  grep -i "error" "$export_log" | tail -n 20 >&2
  exit 1
fi
cp "$ROOT/tools/windows_readme.txt" "$out_dir/README.txt"

zip_path="$ROOT/build/CyberUniverse-windows.zip"
make_zip "$zip_path" "$out_dir" CyberUniverse.exe CyberUniverse.console.exe README.txt
echo "$zip_path"

model="$ROOT/assets/characters/endministrator_f/endministrator_f.glb"
if [[ -f "$model" ]]; then
  mkdir -p "$out_dir/characters"
  cp "$model" "$out_dir/characters/endministrator_f.glb"
  make_zip "$ROOT/build/CyberUniverse-windows-with-model.zip" "$out_dir" CyberUniverse.exe CyberUniverse.console.exe README.txt characters
  echo "$ROOT/build/CyberUniverse-windows-with-model.zip"
fi
