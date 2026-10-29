# tools/ 스크립트들이 함께 쓰는 함수. 직접 실행하지 않고 source로 불러온다.
# 리눅스, macOS, Windows(Git Bash)에서 동작한다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 운영체제: linux, macos, windows
detect_platform() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    Darwin) echo macos ;;
    *) echo linux ;;
  esac
}

# Godot 실행 파일을 $GODOT, PATH의 godot, tools/setup_godot.sh 설치 위치 순서로 찾는다.
# Windows에서는 테스트 결과가 터미널에 보이도록 _console.exe 판을 쓴다.
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

# zip 파일을 푼다. Windows Git Bash에는 unzip이 없을 수 있어 PowerShell로 대신한다.
#   extract_zip <zip> <대상 폴더> [zip 안의 경로...]
# 경로를 주면 그 파일들만 폴더 구조 없이 꺼낸다.
extract_zip() {
  local zip="$1" dest="$2"
  shift 2
  mkdir -p "$dest"
  if command -v unzip >/dev/null 2>&1; then
    if [[ $# -gt 0 ]]; then
      unzip -ojq "$zip" "$@" -d "$dest"
    else
      unzip -oq "$zip" -d "$dest"
    fi
    return
  fi
  local win_zip win_dest
  win_zip="$(cygpath -w "$zip")"
  win_dest="$(cygpath -w "$dest")"
  if [[ $# -eq 0 ]]; then
    powershell -NoProfile -Command "Expand-Archive -Force -LiteralPath '$win_zip' -DestinationPath '$win_dest'"
    return
  fi
  local list
  list="$(printf "'%s'," "$@")"
  powershell -NoProfile -Command "
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    \$zip = [System.IO.Compression.ZipFile]::OpenRead('$win_zip')
    foreach (\$name in @(${list%,})) {
      \$entry = \$zip.GetEntry(\$name)
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile(\$entry, (Join-Path '$win_dest' \$entry.Name), \$true)
    }
    \$zip.Dispose()"
}

# 폴더 안의 파일들을 zip으로 묶는다. Windows Git Bash에는 zip이 없을 수 있어 PowerShell로 대신한다.
#   make_zip <zip> <폴더> <파일...>
make_zip() {
  local zip="$1" dir="$2"
  shift 2
  rm -f "$zip"
  if command -v zip >/dev/null 2>&1; then
    (cd "$dir" && zip -q -9 "$zip" "$@")
    return
  fi
  local paths=()
  for file in "$@"; do
    paths+=("'$(cygpath -w "$dir/$file")'")
  done
  local joined
  joined="$(IFS=,; echo "${paths[*]}")"
  powershell -NoProfile -Command "Compress-Archive -Force -Path $joined -DestinationPath '$(cygpath -w "$zip")'"
}
