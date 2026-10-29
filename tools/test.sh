#!/usr/bin/env bash
# 자동 테스트를 실행한다. 인자를 주면 그 문자열이 들어간 테스트만 실행한다.
#   tools/test.sh            모든 테스트
#   tools/test.sh project    이름에 project가 들어간 테스트만
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

godot_bin="$(find_godot)"
import_project "$godot_bin"
"$godot_bin" --headless --path "$ROOT" --script res://tests/run_tests.gd -- "$@"
