#!/usr/bin/env bash
# 게임을 화면 밖 창에서 정한 시간(초) 동안 돌리며 1초마다 성능을 기록한다(src/dev/perf_log.gd).
# 수직 동기화를 꺼서 남는 여유까지 잰다. 쓰는 사람을 방해하지 않게 창은 화면 밖에 뜨고 소리를 내지 않는다.
#   tools/perf.sh <기록 파일> <초> [게임 인자...]
#   tools/perf.sh build/perf/combat.tsv 40 --single --autoplay
# 렌더링 단계별 GPU 시간은 build/perf.log에 남는다(--gpu-profile).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

out="$1"
seconds="$2"
shift 2

godot_bin="$(find_godot)"
import_project "$godot_bin"
hide_game_window
trap restore_game_window EXIT

mkdir -p "$ROOT/build"
"$godot_bin" --path "$ROOT" --audio-driver Dummy --disable-vsync --gpu-profile --resolution 1x1 -- "$@" --no-update \
  --perf-log="$out" --perf-seconds="$seconds" > "$ROOT/build/perf.log" 2>&1
cat "$out"
