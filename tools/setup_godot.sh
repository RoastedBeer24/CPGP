#!/usr/bin/env bash
# Godot 에디터(리눅스)를 내려받고 공식 SHA-512 체크섬으로 검증한다.
# 설치 위치: $GODOT_HOME (기본값 ~/.cache/godot/<버전>)
# 완료되면 실행 파일 경로를 출력한다.
set -euo pipefail

VERSION="4.5.1-stable"
ZIP="Godot_v${VERSION}_linux.x86_64.zip"
BIN="Godot_v${VERSION}_linux.x86_64"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}"
GODOT_HOME="${GODOT_HOME:-$HOME/.cache/godot/${VERSION}}"

if [[ -x "$GODOT_HOME/$BIN" ]]; then
  echo "$GODOT_HOME/$BIN"
  exit 0
fi

mkdir -p "$GODOT_HOME"
cd "$GODOT_HOME"
curl -fsSL -o "$ZIP" "$BASE_URL/$ZIP"
curl -fsSL -o SHA512-SUMS.txt "$BASE_URL/SHA512-SUMS.txt"
grep " $ZIP\$" SHA512-SUMS.txt | sha512sum -c --quiet - >&2
unzip -oq "$ZIP"
rm -f "$ZIP"
chmod +x "$BIN"
echo "$GODOT_HOME/$BIN"
