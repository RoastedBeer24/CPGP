# 크로스필드 (Crossfield)

아크나이츠: 엔드필드의 캐릭터로 싸우는 **3인칭 협동 액션 로그라이트**입니다. 혼자 하거나, 같은 와이파이에서 최대 3명이 함께 합니다. 엔진은 Godot 4.5이고, 가족끼리 즐기기 위한 비상업 프로젝트입니다.

- 기획: [docs/design/00-foundation.md](docs/design/00-foundation.md)
- 개발 규칙: [docs/dev/conventions.md](docs/dev/conventions.md), 실행·테스트·빌드: [docs/dev/testing.md](docs/dev/testing.md)
- 에셋 출처와 모델 넣는 법: [docs/assets.md](docs/assets.md)

## 현재 단계
**시점·이펙트 다듬기** (검수 대기, [체크리스트](docs/dev/review/camera.md)): 기본 시점은 3인칭(정해진 거리)이고 V로 1인칭, ` 자유 시점은 휠로 얼굴까지 확대. 충격파 고리·화면 왜곡, 궁극기·대시 공격 이펙트.
**원작 동작·무기·이펙트** (검수 대기, [체크리스트](docs/dev/review/motions.md)): 원작 대기 동작(쉬는 자세, 무기 꺼내기·거두기, 캐릭터 화면), 전투 무기를 오른손으로, 원작 칼빛·불꽃 이펙트.
**M3 한 판** (검수 대기, [체크리스트](docs/dev/review/m3.md)): 로비에서 캐릭터를 보고 고른 뒤 출발해 방 다섯 개(중간·최종 보스 포함)를 깨고, 방마다 보상을 고른다. 원작 무기 타르 11과 효과음·보이스.
이전 단계: **M1 첫 전투 방** ([체크리스트](docs/dev/review/m1.md)): 관리자(여·남)의 원작 칼 동작으로 기본 공격 5연속·대시 공격·처형·배틀 스킬·궁극기·회피, 경직과 원석 결정, 예고하는 적, 협동.

## 실행
- **실행 파일로 플레이 (Windows):** GitHub의 **Releases**에서 가장 최근 "빌드 N"의 `Crossfield-windows.zip`을 받아 풀고 `Crossfield.exe`를 실행합니다. 캐릭터 모델은 따로 넣어야 합니다([docs/assets.md](docs/assets.md)). 게임을 켤 때 새 버전을 스스로 받습니다.
- **소스로 실행:** Godot 4.5.1로 이 폴더를 열고 실행하거나 `godot --path . -- --single`
- 테스트: `tools/test.sh`
- 실행 파일 직접 만들기: `tools/export_windows.sh` → `build/Crossfield-windows.zip`

## 이전 게임
이 저장소는 원래 사이버펑크 1인칭 RPG(CyberUniverse)였습니다. 그 마지막 상태는 git 태그 `cyberuniverse-final`에 있습니다.
