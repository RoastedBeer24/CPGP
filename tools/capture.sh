#!/usr/bin/env bash
# 게임을 띄워 정한 프레임들의 화면만 PNG로 저장한다(FrameCapture). 이펙트·카메라처럼 몇 장면을 연달아 볼 때 쓴다.
# 쓰는 사람을 방해하지 않게 창은 화면 밖에 뜨고 포커스를 뺏지 않으며, 소리를 내지 않고 마우스도 잡지 않는다.
#   tools/capture.sh <저장 폴더> <프레임,프레임,...> [게임 인자...]
#   tools/capture.sh build/screenshots/fx 60,90,120 --single --autoplay=combo
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

out="$1"
frames="$2"
shift 2

godot_bin="$(find_godot)"
import_project "$godot_bin"
hide_game_window
trap restore_game_window EXIT

rm -rf "$out"
mkdir -p "$ROOT/build"
"$godot_bin" --path "$ROOT" --audio-driver Dummy --fixed-fps 60 --resolution 1x1 -- "$@" --no-update \
  --capture="$frames" --capture-dir="$out" > "$ROOT/build/capture.log" 2>&1
ls "$out"
