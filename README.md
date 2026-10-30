# CyberUniverse: 사이버펑크 1인칭 액션 RPG

1인칭 사이버펑크 액션 RPG(구역형 반오픈월드, 싱글 + LAN 코옵) 프로젝트입니다. 엔진은 Godot 4.5이고, 아트풍은 서브컬처풍입니다. 가족끼리 즐기기 위한 비상업 프로젝트입니다.

현재 단계: **M2 (전투 기초) 완료**, 다음은 M3 (적 AI와 잠입)

- 검수 체크리스트: [M1](docs/dev/review/m1.md), [M2](docs/dev/review/m2.md), [3인칭과 캐릭터 모델](docs/dev/review/third-person.md), [설정](docs/dev/review/settings.md)

## 기획 문서
- 기초 구상서: [docs/design/00-foundation.md](docs/design/00-foundation.md)
- 세계관: [docs/design/01-world.md](docs/design/01-world.md)
- 네오 부산과 세력: [docs/design/02-city-factions.md](docs/design/02-city-factions.md)

## 개발 문서
- 실행과 테스트 방법: [docs/dev/testing.md](docs/dev/testing.md)
- 개발 규칙: [docs/dev/conventions.md](docs/dev/conventions.md)
- 사용 에셋 목록: [docs/assets.md](docs/assets.md)

## 빠른 시작
- **실행 파일로 플레이 (Windows):** GitHub의 **Releases**에서 가장 최근 "빌드 N"의 `CyberUniverse-windows.zip`을 받아 압축을 풀고 `CyberUniverse.exe`를 실행합니다. 캐릭터 모델은 따로 넣어야 합니다([docs/assets.md](docs/assets.md)).
- **자동 업데이트:** 기본 브랜치에 푸시하면 CI가 새 릴리스를 올리고, 게임은 켤 때 새 빌드를 받아 스스로 바꿉니다. 메뉴에 있으면 바로 다시 시작하고, 게임 중이면 끝낼 때 설치합니다.
- 에디터로 플레이: Godot 4.5.1 표준판으로 `project.godot`를 열고 F5
- 캐릭터 모델은 저장소에 없습니다. 넣는 방법은 [docs/assets.md](docs/assets.md)의 "저장소에 없는 에셋"을 봅니다. 없으면 캡슐 몸으로 돌아갑니다.
- 테스트: `tools/test.sh`
- 실행 파일 직접 만들기: `tools/export_windows.sh` → `build/CyberUniverse-windows.zip` (이 PC에 모델이 있으면 모델을 넣은 `build/CyberUniverse-windows-with-model.zip`도 생김)
