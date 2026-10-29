#!/usr/bin/env bash
# Godot 에디터를 내려받고 공식 SHA-512 체크섬으로 검증한다. 리눅스, macOS, Windows(Git Bash) 지원.
# 설치 위치: $GODOT_HOME (기본값 ~/.cache/godot/<버전>)
# 완료되면 실행 파일 경로를 출력한다.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="4.5.1-stable"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}"
GODOT_HOME="${GODOT_HOME:-$HOME/.cache/godot/${VERSION}}"

case "$(detect_platform)" in
  windows)
    ZIP="Godot_v${VERSION}_win64.exe.zip"
    BIN="Godot_v${VERSION}_win64_console.exe"
    ;;
  macos)
    ZIP="Godot_v${VERSION}_macos.universal.zip"
    BIN="Godot.app/Contents/MacOS/Godot"
    ;;
  *)
    ZIP="Godot_v${VERSION}_linux.x86_64.zip"
    BIN="Godot_v${VERSION}_linux.x86_64"
    ;;
esac

if [[ -x "$GODOT_HOME/$BIN" || -f "$GODOT_HOME/$BIN" ]]; then
  echo "$GODOT_HOME/$BIN"
  exit 0
fi

mkdir -p "$GODOT_HOME"
curl -fsSL -o "$GODOT_HOME/$ZIP" "$BASE_URL/$ZIP"
curl -fsSL -o "$GODOT_HOME/SHA512-SUMS.txt" "$BASE_URL/SHA512-SUMS.txt"
(cd "$GODOT_HOME" && grep " $ZIP\$" SHA512-SUMS.txt | sha512sum -c --quiet - >&2)
extract_zip "$GODOT_HOME/$ZIP" "$GODOT_HOME"
rm -f "$GODOT_HOME/$ZIP"
chmod +x "$GODOT_HOME/$BIN" 2>/dev/null || true
echo "$GODOT_HOME/$BIN"
