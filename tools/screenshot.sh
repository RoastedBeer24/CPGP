#!/usr/bin/env bash
# 씬을 가상 화면(Xvfb)에서 실행하고 마지막 프레임을 PNG로 저장한다. 화면 확인용.
#   tools/screenshot.sh [씬 경로] [프레임 수] [저장 경로]
#   tools/screenshot.sh res://src/boot/main.tscn 30 build/screenshots/boot.png
#   tools/screenshot.sh "" 90 build/screenshots/game.png --single   # 4번째 인자부터는 게임에 전달
# 씬 경로를 생략하면(빈 문자열) 메인 씬을 쓴다.
# GPU가 없는 환경에서는 OpenGL(Compatibility) 렌더러로 대체되므로,
# 조명과 후처리는 실제 PC의 Forward+ 화면과 다를 수 있다. 배치와 UI 확인용으로 쓴다.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

scene="${1:-}"
frames="${2:-10}"
out="${3:-$ROOT/build/screenshots/shot.png}"
game_args=("${@:4}")

godot_bin="$(find_godot)"
import_project "$godot_bin"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

args=(--path "$ROOT" --resolution 1280x720 --write-movie "$tmp_dir/frame.png" --quit-after "$frames")
[[ -n "$scene" ]] && args+=("$scene")
[[ ${#game_args[@]} -gt 0 ]] && args+=(-- "${game_args[@]}")
xvfb-run -a -s "-screen 0 1280x720x24" "$godot_bin" "${args[@]}" >/dev/null 2>&1

mkdir -p "$(dirname "$out")"
last_frame="$(ls "$tmp_dir"/frame*.png | sort | tail -n 1)"
mv "$last_frame" "$out"
echo "$out"
