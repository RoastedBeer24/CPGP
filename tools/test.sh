#!/usr/bin/env bash
# 자동 테스트를 실행한다. 인자를 주면 그 문자열이 들어간 테스트만 실행한다.
#   tools/test.sh            모든 테스트
#   tools/test.sh project    이름에 project가 들어간 테스트만
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

godot_bin="$(find_godot)"
import_project "$godot_bin"
# --fixed-fps: 물리 시간을 실제 시간과 분리해 테스트를 빠르고 결정적으로 만든다.
"$godot_bin" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/run_tests.gd -- "$@"
