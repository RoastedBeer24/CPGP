class_name BuildInfo
extends RefCounted
## 실행 파일의 빌드 번호. 자동 업데이트가 새 버전인지 판단할 때 쓴다.
## 개발 중에는 0이고, tools/export_windows.sh가 내보내는 동안만 커밋 수로 바꿔 쓴 뒤 되돌린다.
## 같은 커밋에서 만든 실행 파일은 어디서 만들든(CI, 각자 PC) 번호가 같다.

const NUMBER := 0
const COMMIT := ""
