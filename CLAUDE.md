# CyberUniverse: Claude 작업 안내

이 파일은 Claude Code가 세션을 시작할 때 자동으로 읽는다. 새 세션은 여기부터 읽고 이어서 작업한다.

## 절대 규칙
- **모든 응답은 한국어로만 한다.** 진행 상황 한 줄 알림, 질문, 요약까지 전부 한국어다. 사용자가 정한 절대 규칙이다.
- 코드 식별자와 커밋 메시지는 영어, 코드 주석과 문서는 한국어로 쓴다.

## 사용자와 일하는 방식
- 개발은 Claude가 **알아서 진행**한다. 단계마다 허락을 구하지 않는다.
- **기획 판단**(세계관, 이야기, 수치의 큰 방향처럼 사용자만 정할 수 있는 것)만 사용자에게 묻는다. 임의로 정한 것은 검수 체크리스트의 "제가 임의로 정한 것" 표에 적어 알린다.
- 사용자는 검수와 기획을 맡는다. 마일스톤마다 `docs/dev/review/mN.md` 검수 체크리스트를 만든다.
- **억지스러운 한국 지역색을 넣지 않는다.** (예: 산동네, 달동네 같은 것). 세계관에 있는 것(네오조선, 친군영 등)은 사용자가 정한 것이다.
- **그래픽보다 게임성이 우선**이다. 시각 요소는 가독성이 목표다.
- 에셋은 **무료 공개 에셋만** 쓴다. 라이선스 종류는 상관없다(상업화하지 않는 가족용 게임). 출처는 `docs/assets.md`에 적는다.
- 참고작은 **사이버펑크 2077**이다. 조작 기본값, 전투 감각, 성장 방식이 기준이다.

## 기획 문서 (먼저 읽을 것)
- `docs/design/00-foundation.md`: 기초 구상서. 기둥, 범위, 로드맵, 검수 기록
- `docs/design/01-world.md`: 세계관 (2048년, 네오조선, 왕 백건, 하나 테크, 주민등록 임플란트, 죽음의 땅)
- `docs/design/02-city-factions.md`: 네오 부산의 수직 구조와 세력 24개
- `docs/dev/conventions.md`: 개발 규칙 (반드시 지킬 것)
- `docs/dev/testing.md`: 실행, 테스트, 스크린샷, Windows 빌드 방법

## 진행 상황
| 마일스톤 | 상태 | 비고 |
|---|---|---|
| M0 기반 | 완료 | Godot 프로젝트, 테스트 러너, 도구 스크립트 |
| M1 이동 + 네트워크 | 완료 | 1인칭 이동, 시험장, 싱글·LAN 코옵(최대 3명), 메뉴 |
| M2 전투 기초 | 완료 | 무기 3종, 체력·장갑, 허수아비, 단순한 경비병, 전투 HUD, 사망·부활 |
| 3인칭과 캐릭터 모델 | 완료 | V로 1인칭/3인칭 전환, 캐릭터 모델에 코드로 만든 자세, 든 무기 동기화 (`docs/dev/review/third-person.md`) |
| 설정 | 완료 | 소리 5종, 창 모드·크기, 그래픽, 감도·시야각, 키 바꾸기 (`docs/dev/review/settings.md`) |
| 릴리스와 자동 업데이트 | 완료 | 기본 브랜치 푸시 → GitHub 릴리스 `build-<커밋 수>`, 게임이 켤 때 스스로 업데이트 (`docs/dev/testing.md`) |
| **M3 적 AI와 잠입** | **다음 작업** | 아래 계획 참고 |
| M4 해킹 ~ M8 폴리싱 | 예정 | 구상서 §9 |

### M3 계획 (구상서 §7.1 기준)
- 적 AI 상태 머신: 순찰(경로 지점) → 의심 → 수색 → 전투, 경계 단계가 서로 퍼짐
- 감지: 시야 원뿔과 거리, 웅크리면 덜 보임, 소리(총성, 달리기)
- 은신 제압(뒤에서 접근해 상호작용), 시체 옮기기·숨기기
- 이동하는 적: NavigationRegion3D와 NavigationAgent3D, 엄폐 지점 사용
- 적 3종의 기초: 일반 경비, 중장갑병(장갑 높음), 적 넷러너는 M4에서 해킹과 함께
- 지금의 `src/enemies/grunt.gd`(제자리에서 돌아서 쏘기만 함)를 이 AI로 바꾼다
- 코옵: AI 판단은 호스트만, 상태와 위치는 동기화. 테스트는 `NetTestCase`로

## 개발 환경
- **Godot 4.5.1 표준판**(GDScript), Forward+ 렌더러, Jolt Physics
- Windows에서는 Git Bash로 `tools/*.sh`를 실행한다. Godot 위치를 `GODOT` 환경 변수로 알려 주거나(콘솔판 `Godot_v4.5.1-stable_win64_console.exe` 권장), 없으면 `tools/setup_godot.sh`가 내려받는다.

### 자주 쓰는 명령
```bash
tools/test.sh                 # 자동 테스트 전체 (커밋 전에 반드시 통과)
tools/test.sh weapons         # 이름에 weapons가 들어간 테스트만
tools/screenshot.sh "" 40 build/screenshots/game.png --single   # 게임 화면 캡처
tools/export_windows.sh       # build/CyberUniverse-windows.zip 생성
python3 tools/gen_test_range.py   # 그레이박스 시험장 씬 다시 생성
godot --path . -- --single    # 메뉴 건너뛰고 혼자 하기 (--host, --join=주소, --third-person)
```
- 푸시하면 GitHub Actions(`.github/workflows/build.yml`)가 테스트를 돌리고 Windows 실행 파일을 Artifacts로 올린다.

## 작업 절차
1. 기능을 만들면 같은 커밋에 테스트를 넣는다. 물리는 `await tree.physics_frame`, 코옵은 `NetTestCase`.
2. `tools/test.sh`가 통과해야 커밋한다. 무작위 요소가 있는 테스트는 여러 번 돌려 흔들리지 않는지 본다.
3. 화면에 보이는 변경은 `tools/screenshot.sh`로 찍어서 직접 확인한다.
4. 마일스톤이 끝나면 검수 체크리스트를 쓰고, 구상서 로드맵에 ✅를 표시하고, README의 현재 단계를 고친다.

## 이미 겪은 함정 (다시 빠지지 말 것)
- **preload 순환:** 서로 참조하는 스크립트(Player ↔ WeaponHolder)에서 `.tres`를 `preload`하면 리소스가 깨진다. `_ready()`에서 `load()`한다.
- **테스트 러너:** `before_each()`는 await까지 기다린 뒤 테스트를 시작한다. 첫 프레임 전에는 노드가 트리에 들어가지 않는다.
- **시간 판정:** 테스트는 `--fixed-fps 60`으로 돌아서 실제 시간보다 빠르다. 연사 제한 같은 판정은 `Engine.get_physics_frames()`로 잰다.
- **RPC 인자:** `Array[Vector3]` 같은 타입 배열은 못 쓴다. `PackedVector3Array`를 쓴다.
- **세션 종료 순서:** 복제 중인 노드를 먼저 지우고 나서 연결을 닫는다(`Session.leave()`). 반대로 하면 복제 시스템 오류가 난다.
- **체력 권한:** 플레이어 노드는 조종하는 피어 권한이지만 `Health`와 `HealthSync`는 호스트(1) 권한으로 되돌린다(`Session._spawn_player`).
- **tscn의 Transform3D:** 기저 행렬은 행 우선으로 적는다. 생성 스크립트에서 한 번 전치 실수를 했다.
- **피격 판정:** 물리 레이어 1 world, 2 character, 3 hitbox. 총알은 world와 hitbox만 맞고, 같은 팀의 Hitbox는 통과한다.
- **죽었을 때:** 몸 충돌을 끄면 바닥 아래로 떨어진다. Hitbox의 collision_layer만 0으로 만든다.
- **저장소에 없는 캐릭터 모델:** `assets/characters/endministrator_f/`는 재배포 불가라 gitignore 대상이다(`docs/assets.md`). CI와 다른 PC에는 없으므로, 모델이 필요한 테스트는 `has_model`이 false면 건너뛰고, 모델 없이도 전체 테스트가 통과해야 한다. `data/player/default_appearance.tres`의 경로를 잠시 바꿔서 확인한다.
- **조준 판정:** 무기는 `player.camera`가 아니라 `aim_origin()`/`aim_direction()`을 쓴다. 3인칭 카메라 위치에서 쏘면 캐릭터 뒤의 물체를 맞힌다.
- **자동 업데이트:** 빌드 번호는 커밋 수다. `src/core/build_info.gd`의 `NUMBER`는 저장소에서 항상 0이어야 한다(내보낼 때만 바뀜, 테스트가 확인함). 실행 중인 exe는 덮어쓸 수 없어 PowerShell 스크립트가 종료를 기다렸다 바꾼다. `CyberUniverse.console.exe`는 게임이 도는 동안 잠겨 있으므로 내용이 같은 파일은 건너뛴다. 설치 스크립트는 영어로만 쓴다(PowerShell 5.1이 BOM 없는 파일을 시스템 코드 페이지로 읽음).
- **저장소는 공개여야 한다:** 게임은 로그인 없이 GitHub API로 릴리스를 받는다. 비공개 저장소면 404가 와서 업데이트가 조용히 멈춘다(2026-10-30에 공개로 바꿈). 그래서 재배포할 수 없는 에셋은 절대 커밋하지 않는다.
- **업데이트 실패는 조용히:** `JSON.parse_string`은 실패하면 엔진 오류를 남기므로 `JSON.new().parse()`를 쓴다. 릴리스가 없을 때의 404는 "받을 것 없음"으로 처리한다.
- **내보내기와 자체 포함 Godot:** 옆에 `_sc_` 파일이 있는 Godot는 템플릿을 자기 폴더에서만 찾는다. `tools/export_windows.sh`가 알아서 표준 Godot를 받아 쓴다.
- **캐릭터 모델은 exe에 넣지 않는다:** `export_presets.cfg`에서 `assets/characters/*`를 뺀다. 내보낸 게임은 exe 옆 `characters/`에서 실행 중에 glTF를 읽는다(`CharacterAppearance.load_gltf_file`).
- **사용자 설정:** `GameSettings`는 정적 변수 클래스다(자동 로드 아님). 테스트 러너가 경로를 `user://test_settings.cfg`로 바꾸므로 사용자 설정을 건드리지 않는다. 설정을 바꾸는 테스트는 `after_each`에서 `reset_to_defaults()`로 되돌린다. 마우스 감도·시야각·웅크리기 방식은 `MovementConfig`가 아니라 여기 있다.
- **정적 함수와 자동 로드:** 정적 함수 안에서는 자동 로드 이름(`InputActions`)을 못 쓴다. 스크립트를 `preload`해서 쓴다.
- **화면 없는 실행:** `DisplayServer.keyboard_get_keycode_from_physical`, 창 크기·모드 같은 창 기능은 headless에서 오류가 난다. `DisplayServer.get_name() == "headless"`면 건너뛴다.
- **컴파일 오류면 테스트가 멈춘다:** 스크립트에 문법 오류가 있으면 러너가 끝나지 않는다. `timeout 500 tools/test.sh > build/test_all.log`처럼 시간 제한을 걸고 파일로 받아 확인한다.
- **코드로 만드는 자세:** 이 모델은 뼈 축이 제각각(3ds Max Biped, 뼈대 공간은 Z가 위)이라 각도 대신 "몸 기준 방향"으로 뼈를 돌린다(`PlayerBody._point_bone`). `Basis.looking_at`은 방향이 위쪽 기준과 나란하거나 0이면 오류가 난다.
