#!/usr/bin/env bash
# 씬을 실행하고 마지막 프레임을 PNG로 저장한다. 화면 확인용. 화면이 없는 리눅스에서는 Xvfb를 쓴다.
#   tools/screenshot.sh [씬 경로] [프레임 수] [저장 경로]
#   tools/screenshot.sh res://src/boot/main.tscn 30 build/screenshots/boot.png
#   tools/screenshot.sh "" 90 build/screenshots/game.png --single   # 4번째 인자부터는 게임에 전달
# 씬 경로를 생략하면(빈 문자열) 메인 씬을 쓴다.
# GPU가 없는 환경에서는 OpenGL(Compatibility) 렌더러로 대체되므로,
# 조명과 후처리는 실제 PC의 Forward+ 화면과 다를 수 있다. 배치와 UI 확인용으로 쓴다.
# 쓰는 사람을 방해하지 않게 창은 화면 밖에 뜨고 포커스를 뺏지 않으며, 소리를 내지 않는다(tools/lib.sh hide_game_window).
# 메인 씬은 tools/capture.sh(정한 프레임만 저장)로 찍고, 다른 씬은 화면 녹화(--write-movie)로 찍는다.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

scene="${1:-}"
frames="${2:-10}"
out="${3:-$ROOT/build/screenshots/shot.png}"
game_args=("${@:4}")

tmp_dir="$(mktemp -d)"
mkdir -p "$(dirname "$out")"

if [[ -z "$scene" ]]; then
  trap 'rm -rf "$tmp_dir"' EXIT
  "$ROOT/tools/capture.sh" "$tmp_dir/frames" "$frames" "${game_args[@]}" >/dev/null
  mv "$tmp_dir/frames/$(printf 'frame_%05d.png' "$frames")" "$out"
  echo "$out"
  exit 0
fi

godot_bin="$(find_godot)"
import_project "$godot_bin"
hide_game_window
trap 'rm -rf "$tmp_dir"; restore_game_window' EXIT

args=(--path "$ROOT" --audio-driver Dummy --resolution 1280x720 --write-movie "$tmp_dir/frame.png" --quit-after "$frames" "$scene")
[[ ${#game_args[@]} -gt 0 ]] && args+=(-- "${game_args[@]}")
# 화면이 없는 리눅스에서는 가상 화면(Xvfb)을 쓰고, 그 밖에는 그대로 창을 띄운다.
if command -v xvfb-run >/dev/null 2>&1 && [[ -z "${DISPLAY:-}" ]]; then
  xvfb-run -a -s "-screen 0 1280x720x24" "$godot_bin" "${args[@]}" >/dev/null 2>&1
else
  "$godot_bin" "${args[@]}" >/dev/null 2>&1
fi

last_frame="$(ls "$tmp_dir"/frame*.png | sort | tail -n 1)"
mv "$last_frame" "$out"
echo "$out"
