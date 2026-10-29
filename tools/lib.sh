# tools/ 스크립트들이 함께 쓰는 함수. 직접 실행하지 않고 source로 불러온다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Godot 실행 파일을 $GODOT, PATH의 godot, tools/setup_godot.sh 설치 위치 순서로 찾는다.
find_godot() {
  if [[ -n "${GODOT:-}" ]]; then
    echo "$GODOT"
  elif command -v godot >/dev/null 2>&1; then
    command -v godot
  else
    "$ROOT/tools/setup_godot.sh"
  fi
}

# class_name 등록과 리소스 가져오기를 끝낸다.
import_project() {
  "$1" --headless --path "$ROOT" --import >/dev/null 2>&1
}
