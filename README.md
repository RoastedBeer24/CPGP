# 크로스필드 (Crossfield)

아크나이츠: 엔드필드의 캐릭터로 싸우는 **3인칭 협동 액션 로그라이트**입니다. 혼자 하거나, 같은 와이파이에서 최대 3명이 함께 합니다. 엔진은 Godot 4.5이고, 가족끼리 즐기기 위한 비상업 프로젝트입니다.

- 기획: [docs/design/00-foundation.md](docs/design/00-foundation.md)
- 개발 규칙: [docs/dev/conventions.md](docs/dev/conventions.md), 실행·테스트·빌드: [docs/dev/testing.md](docs/dev/testing.md)
- 에셋 출처와 모델 넣는 법: [docs/assets.md](docs/assets.md)

## 현재 단계
**M1 첫 전투 방** (검수 대기, [체크리스트](docs/dev/review/m1.md)): 관리자(여·남)의 원작 칼 동작으로 기본 공격 5연속·대시 공격·처형·배틀 스킬·궁극기·회피, 경직과 원석 결정, 예고하는 적 3종, 웨이브 3개, 협동.

## 실행
- **실행 파일로 플레이 (Windows):** GitHub의 **Releases**에서 가장 최근 "빌드 N"의 `Crossfield-windows.zip`을 받아 풀고 `Crossfield.exe`를 실행합니다. 캐릭터 모델은 따로 넣어야 합니다([docs/assets.md](docs/assets.md)). 게임을 켤 때 새 버전을 스스로 받습니다.
- **소스로 실행:** Godot 4.5.1로 이 폴더를 열고 실행하거나 `godot --path . -- --single`
- 테스트: `tools/test.sh`
- 실행 파일 직접 만들기: `tools/export_windows.sh` → `build/Crossfield-windows.zip`

## 이전 게임
이 저장소는 원래 사이버펑크 1인칭 RPG(CyberUniverse)였습니다. 그 마지막 상태는 git 태그 `cyberuniverse-final`에 있습니다.
