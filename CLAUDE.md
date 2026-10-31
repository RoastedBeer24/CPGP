# 크로스필드 (Crossfield): Claude 작업 안내

이 파일은 Claude Code가 세션을 시작할 때 자동으로 읽는다. 새 세션은 여기부터 읽고 이어서 작업한다.
2026-10-30에 사이버펑크 게임(CyberUniverse)을 그만두고 같은 저장소에서 새 게임을 만들었다. 옛 게임은 태그 `cyberuniverse-final`에 있다.

## 절대 규칙
- **모든 응답은 한국어로만 한다.** 진행 상황 한 줄 알림, 질문, 요약까지 전부 한국어다. 사용자가 정한 절대 규칙이다.
- 코드 식별자와 커밋 메시지는 영어, 코드 주석과 문서는 한국어로 쓴다.

## 사용자와 일하는 방식
- 개발은 Claude가 **알아서 진행**한다. 단계마다 허락을 구하지 않는다.
- **기획 판단**(이야기, 수치의 큰 방향처럼 사용자만 정할 수 있는 것)만 사용자에게 묻는다. 임의로 정한 것은 검수 체크리스트의 "제가 임의로 정한 것" 표에 적어 알린다.
- 사용자는 검수와 기획을 맡는다. 마일스톤마다 `docs/dev/review/mN.md` 검수 체크리스트를 만든다.
- **그래픽보다 게임성이 우선**이다. 시각 요소는 가독성이 목표다(적의 공격 예고, 경직, 원석 결정이 한눈에 보이게).
- 참고작은 **아크나이츠: 엔드필드**다. 조작 기본값(PC판 키), 전투 감각, 캐릭터 기술이 기준이다.
- 캐릭터·적 모델은 원작에서 추출한 것이라 **재배포할 수 없다.** 공개 저장소와 그 릴리스에는 절대 넣지 않고, 비공개 에셋 저장소에만 올린다(`docs/assets.md`). 그 밖의 에셋은 무료 공개 에셋만 쓰고 출처를 `docs/assets.md`에 적는다.
- 모델·소리·이펙트 추출은 사용자가 해서 준다(GPT로 사이트에서 추출, 형식은 `!File/` 아래 원본과 같다). 사이트를 브라우저로 열지 않는다. 준비되면 사용자가 알려 준다.
- 사용자는 작업 중에도 응답을 잘 하길 바란다. 긴 작업 중에도 짧게 진행 상황을 알리고, 사용자 메시지에 바로 답한다.

## 기획 문서 (먼저 읽을 것)
- `docs/design/00-foundation.md`: 기초 구상서. 전제, 전투 규칙, 조작, 협동, 로드맵, 검수 기록
- `docs/dev/conventions.md`: 개발 규칙 (반드시 지킬 것)
- `docs/dev/testing.md`: 실행, 테스트, 스크린샷, Windows 빌드 방법
- `docs/assets.md`: 에셋 출처, 모델 넣는 법, 비공개 에셋 저장소

## 진행 상황
| 마일스톤 | 상태 | 비고 |
|---|---|---|
| M0 정리 | 완료 | 이름 변경(설치된 게임의 자동 업데이트 유지), 옛 게임 코드 삭제. 메뉴·설정·자동 업데이트·협동 연결·캐릭터 모델 처리·만화풍 셰이더는 다시 씀 |
| M1 첫 전투 방 | 검수 대기 | 관리자(여·남) 검 5연속·대시 공격·처형·배틀 스킬(원석 결정)·궁극기(결정 파쇄)·회피(완벽한 회피)·경직, 적 3종(임시 도형 몸), 웨이브, HUD, 협동, 캐릭터 고르기 (`docs/dev/review/m1.md`) |
| M2 적 모델 | 모델 기다림 | 사용자가 적 모델을 추출해 주면 넣는다 |
| **M3 한 판** | **검수 대기** | 로비(캐릭터 화면 C, 출발 Enter), 방 다섯 개(배치 둘 + 보스 방), 보상 12종, 중간·최종 보스(격노), 원작 무기 타르 11·소리·보이스, 검기, 카메라 확대·축소 (`docs/dev/review/m3.md`) |
| 원작 동작·무기 자리 | 검수 대기 | 전투 무기는 오른손(wep_R)으로 고침, 싸우는 동작에서만 무기가 나타남(칼날이 차오르고 지워짐), 무기 꺼내기·거두기, 쉬는 자세·특수 대기, 멈추기, 무거운 착지, 가벼운 피격(윗몸), 캐릭터 화면 동작·무기 보기 (`docs/dev/review/motions.md`) |
| 시점·이펙트 다듬기 | 검수 대기 | 기본 시점(3인칭 고정 거리, V로 1인칭), 자유 시점(`, 얼굴까지 확대), 벽에서 천천히 되돌리기·싸울 때 물러나기, 충격파 고리·화면 왜곡·방사 흐림, 궁극기·대시 공격 이펙트 (`docs/dev/review/camera.md`) |
| 원작 이펙트 | 검수 대기 | 사이트 자료로 원작 셰이더(VFXBaseV2)와 파티클 시스템을 다시 만듦: 기본 공격·처형·배틀 스킬의 칼빛·빛·연기·불꽃 (`docs/dev/effects.md`, 체크리스트는 `docs/dev/review/motions.md`) |
| M4 거점·영구 성장 ~ M6 다듬기 | 예정 | 구상서 §6 |

### 지금 구조
- `src/player/player.gd`: 3인칭 액션 조작. 카메라(CameraRig, 몸과 따로 돈다. `CameraMode`: 3인칭·1인칭·자유 시점), 카메라 기준 이동, 공격 연속·스킬·회피·대상 고정·쓰러짐·동료 일으키기. 동작은 `action_id`/`action_count`, 회피는 `dodge_count`로 동기화
- `src/player/player_body.gd`: 모델·만화풍 재질·옷자락·발 IK, 이동 동작 고르기(서 있을 때는 전투 대기·쉬는 자세·캐릭터 화면 대기), 동작 층(공격·스킬·회피·맞음·쓰러짐과 대기 연출), 윗몸만 움찔하는 가벼운 피격, 무기 자리(오른손·등 뒤·왼손)와 나타나고 사라지기(`weapon.gdshader`)
- `src/combat/`: `KitData`(캐릭터 전투 구성) → `AttackData`(동작 하나: 길이, 이어지는 시각, 내디딤 거리) → `HitData`(타격 하나: 시각, 배율, 경직, 범위, 원석 결정 효과). `Health`, `Hitbox`, `CombatQuery.melee`, `DamageNumber`, `HitSpark`
- `src/enemies/`: `Enemy`(호스트가 판단: 쫓기 → 예고 → 맞히기 → 쉬기, 움찔·경직·원석 결정), `EnemyBody`(예고 표시, 모델 또는 도형 몸), `EnemyProjectile`, `EnemyData`/`EnemyAttackData`(`data/enemies/*.tres`)
- `src/zones/combat_room/`: 웨이브, 방 정리, 전멸. 적은 방 안의 `EnemySpawner`가 복제한다. 씬 세 개(방 A·B, 보스 방)는 `tools/gen_combat_room.py`로 만든다
- `src/zones/lobby/`: 로비(격납고, `tools/gen_lobby.py`). `src/run/`: 작전(`Run`, 세션의 자식): 방 차례, 보상 고르기(`RewardPool`, `data/rewards/pool.tres`), 작전 완료·실패 뒤 로비. 작전 구성은 `data/runs/first_run.tres`
- `src/player/character_fx.gd`: 동작에 맞춘 원작 소리·보이스·이펙트(캐릭터마다 zip, `tools/extract_character_fx.py`). `weapon_trail.gd`: 원작 이펙트가 없는 동작의 임시 검기
- `src/fx/`: 원작 이펙트. `EffectLibrary`(zip에서 읽기) → `FxEffect`(이벤트대로 놓고 재생) → `FxSystem`(파티클 계산, MultiMesh) + `FxMaterial`/`vfx_base.gdshaderinc`(원작 셰이더). 설명은 `docs/dev/effects.md`
- `src/dev/`: `AutoPilot`(--autoplay, --autoplay=combo 제자리 연속 공격), `FrameCapture`(--capture=프레임들: 그 화면만 PNG로 저장)
- `src/ui/character_screen.gd`(로비 캐릭터 화면), `reward_panel.gd`(보상 고르기), `hud.gd`(보스 체력, 작전 진행)
- `src/player/characters.gd` + `data/characters/<이름>/`(character, appearance, kit): 고를 수 있는 캐릭터
- `src/core/roster.gd`: 같은 3D 세계의 플레이어·적 목록

## 개발 환경
- **Godot 4.5.1 표준판**(GDScript), Forward+ 렌더러, Jolt Physics
- Windows에서는 Git Bash로 `tools/*.sh`를 실행한다. Godot 위치를 `GODOT` 환경 변수로 알려 주거나(콘솔판 `Godot_v4.5.1-stable_win64_console.exe` 권장), 없으면 `tools/setup_godot.sh`가 내려받는다.

### 자주 쓰는 명령
```bash
tools/test.sh                 # 자동 테스트 전체 (커밋 전에 반드시 통과)
tools/test.sh combat          # 이름에 combat이 들어간 테스트만
tools/screenshot.sh "" 330 build/screenshots/fight.png --single --autoplay --no-update   # 싸우는 화면 캡처
tools/capture.sh build/screenshots/fx 60,90,120 --single --autoplay=combo   # 정한 프레임들만 저장(이펙트·카메라 확인)
tools/export_windows.sh       # build/Crossfield-windows.zip (+ 옛 이름 CyberUniverse-windows.zip) 생성
python3 tools/gen_combat_room.py   # 전투 방 씬 셋(방 A·B, 보스 방) 다시 생성
python3 tools/gen_lobby.py         # 로비 씬 다시 생성
python3 tools/extract_character_fx.py "!File/Endministrator_Extras" F assets/characters/endministrator_f/endministrator_f_fx.zip   # 소리·보이스 꾸러미
godot --path . -- --single    # 메뉴 건너뛰고 혼자 하기 (--host, --join=주소, --character=endministrator_m, --autoplay)
python3 tools/extract_character.py <원본_Animated.glb> <결과.glb>   # 캐릭터 모델에 쓸 동작만 뽑기 (여·남 자동 구분)
python3 tools/measure_attack_clips.py <원본_Animated.glb> attack_01:1.4   # 공격 동작의 타격 시각과 내디딤 거리 재기
python3 tools/publish_assets.py   # 캐릭터 모델을 비공개 에셋 저장소에 올리기 (게임이 자동으로 받음)
```
- 푸시하면 GitHub Actions(`.github/workflows/build.yml`)가 테스트를 돌리고 Windows 실행 파일을 Artifacts로 올린다. 기본 브랜치면 릴리스로도 올리고, 설치된 게임이 자동 업데이트한다. 그래서 **푸시와 에셋 올리기는 사용자에게 먼저 묻는다**(가족이 쓰는 게임이 바로 바뀐다).

## 작업 절차
1. 기능을 만들면 같은 커밋에 테스트를 넣는다. 물리는 `await tree.physics_frame`, 코옵은 `NetTestCase`.
2. `tools/test.sh`가 통과해야 커밋한다. 무작위 요소가 있는 테스트는 여러 번 돌려 흔들리지 않는지 본다.
3. 화면에 보이는 변경은 `tools/screenshot.sh`로 찍어서 직접 확인한다(`--autoplay`로 저절로 싸우게 할 수 있다).
4. 마일스톤이 끝나면 검수 체크리스트를 쓰고, 구상서 로드맵을 고치고, README의 현재 단계를 고친다.

## 이미 겪은 함정 (다시 빠지지 말 것)
- **preload 순환:** 서로 참조하는 스크립트(Player ↔ PlayerBody, KitData)에서 `.tres`를 `preload`하면 리소스가 깨진다. `_ready()`에서 `load()`한다. 캐릭터 데이터도 경로로 두고 쓸 때 불러온다(`CharacterData`).
- **테스트 러너:** `before_each()`는 await까지 기다린 뒤 테스트를 시작한다. 첫 프레임 전에는 노드가 트리에 들어가지 않는다. 테스트 중에 엔진 오류가 하나라도 나면 그 테스트는 실패다.
- **시간 판정:** 테스트는 `--fixed-fps 60`으로 돌아서 실제 시간보다 빠르다. 네트워크로 퍼지는 값은 정해진 프레임 수가 아니라 `wait_until`로 값이 맞을 때까지 기다린다.
- **RPC 인자:** `Array[Vector3]` 같은 타입 배열은 못 쓴다. `PackedVector3Array`를 쓴다.
- **세션 종료 순서:** 복제 중인 노드를 먼저 지우고 나서 연결을 닫는다(`Session.leave()`). 반대로 하면 복제 시스템 오류가 난다. 느린 시간(Engine.time_scale)도 여기서 되돌린다.
- **권한:** 플레이어 노드는 조종하는 피어 권한이지만 `Health`와 `HealthSync`는 호스트(1) 권한으로 되돌린다(`Session._spawn_player`). 적과 전투 방은 호스트 권한이다. 피해 판정은 호스트: 플레이어의 타격은 `_request_hit` → 호스트 `_resolve_hit` → `_hit_results`로 돌려준다. 적의 공격은 호스트가 `Enemy.strike`로 판정하고 `Player.notify_hit`/`notify_perfect_dodge`로 알린다.
- **그룹과 여러 피어:** `get_nodes_in_group`은 장면 트리 전체에서 찾아서, 한 프로세스에 여러 피어를 띄우는 코옵 테스트에서는 다른 피어의 노드까지 섞인다. `Roster.players()`/`Roster.enemies()`로 같은 3D 세계의 것만 쓴다.
- **캐릭터 고르기와 스폰:** 참여한 피어는 접속한 뒤 고른 캐릭터를 `Session._register`로 알리고, 호스트가 그때 스폰한다(접속 즉시 스폰하지 않는다). 캐릭터 이름은 스폰 정보로 모든 피어에 간다. 로비에서 캐릭터를 바꾸면 호스트가 그 플레이어를 지우고 같은 이름으로 다시 스폰한다(`change_character`).
- **구역 바꾸기:** 호스트가 `Session.change_zone`으로 모든 피어의 구역을 바꾼다. 구역 노드 이름(Zone0, Zone1, ...)은 호스트가 정해 보낸다: 적 복제는 노드 경로로 찾으므로 나중에 들어온 피어도 이름이 같아야 한다. 방을 바꾸기 전에 호스트가 적을 먼저 치우고 0.3초 기다린다(`Run._switch_zone`). 로비에서 나가는 첫 전환은 기다리지 않아 바로 바뀐다.
- **작전 중 참여 거절:** 접속하자마자 복제가 시작되므로, 연결 뒤에 거절하면 그 피어에 지금 방의 적이 복제되어 "Node not found" 오류가 난다. `SceneMultiplayer`의 접속 인증(auth_callback, `peer_authenticating`)에서 호스트가 받을지 먼저 답한다(`Session._on_peer_authenticating`). `refuse_new_connections`는 들어오려는 쪽이 시간 초과까지 기다려서 쓰지 않는다.
- **테스트의 람다:** 지워질 노드를 람다가 붙잡으면 "Lambda capture was freed" 오류가 난다(구역을 바꾸면 옛 구역이 지워진다). 노드 대신 이름을 담는다.
- **tscn의 Transform3D:** 기저 행렬은 행 우선으로 적는다(`m[r][c]`, r이 바깥). 생성 스크립트에서 전치 실수를 두 번 했다.
- **피격 판정:** 물리 레이어 1 world, 2 character, 3 hitbox. 근접 판정(`CombatQuery.melee`)은 hitbox만 보고 벽 너머는 맞지 않는다. 같은 팀의 Hitbox는 맞지 않는다. 적의 공격은 Hitbox 없이 거리와 각도로 판정한다.
- **쓰러졌을 때:** 몸 충돌을 끄면 바닥 아래로 떨어진다. 적이 쓰러지면 Hitbox와 몸 충돌을 끄되 바닥에 붙여 둔다.
- **저장소에 없는 모델:** `assets/characters/*/`, `assets/enemies/`는 재배포 불가라 gitignore 대상이다(`docs/assets.md`). CI와 다른 PC에는 없으므로, 모델이 필요한 테스트는 `has_model`이 false면 건너뛰고, 모델 없이도 전체 테스트가 통과해야 한다.
- **이름 변경과 자동 업데이트:** 설치된 게임은 **자기 실행 파일 이름에 맞는 zip**을 받는다(`Updater.asset_name_for`). 옛 이름(CyberUniverse.exe)으로 설치한 게임이 새 이름의 zip을 받으면 Crossfield.exe만 생기고 다시 켜는 옛 exe가 그대로라 업데이트를 끝없이 되풀이한다. 그래서 릴리스에 두 zip을 다 올린다. 사용자 데이터 폴더도 이름을 따라 바뀌어서 처음 켤 때 옛 설정(에셋 키 포함)을 한 번 복사한다.
- **자동 업데이트:** 빌드 번호는 커밋 수다. `src/core/build_info.gd`의 `NUMBER`는 저장소에서 항상 0이어야 한다(내보낼 때만 바뀜, 테스트가 확인함). 실행 중인 exe는 덮어쓸 수 없어 PowerShell 스크립트가 종료를 기다렸다 바꾼다. 콘솔판 exe는 게임이 도는 동안 잠겨 있으므로 내용이 같은 파일은 건너뛴다. 설치 스크립트는 영어로만 쓴다(PowerShell 5.1이 BOM 없는 파일을 시스템 코드 페이지로 읽음).
- **저장소는 공개여야 한다:** 게임은 로그인 없이 GitHub API로 릴리스를 받는다. 비공개 저장소면 404가 와서 업데이트가 조용히 멈춘다. 그래서 재배포할 수 없는 에셋은 절대 커밋하지 않는다.
- **업데이트 실패는 조용히:** `JSON.parse_string`은 실패하면 엔진 오류를 남기므로 `JSON.new().parse()`를 쓴다. 릴리스가 없을 때의 404는 "받을 것 없음"으로 처리한다.
- **내보내기와 자체 포함 Godot:** 옆에 `_sc_` 파일이 있는 Godot는 템플릿을 자기 폴더에서만 찾는다. `tools/export_windows.sh`가 알아서 표준 Godot를 받아 쓴다.
- **모델은 exe에 넣지 않는다:** `export_presets.cfg`에서 `assets/characters/*`, `assets/enemies/*`를 뺀다. 내보낸 게임은 exe 옆 `characters/`에서 실행 중에 glTF를 읽는다(`CharacterAppearance.load_gltf_file`).
- **사용자 설정:** `GameSettings`는 정적 변수 클래스다(자동 로드 아님). 테스트 러너가 경로를 `user://test_settings.cfg`로 바꾸므로 사용자 설정을 건드리지 않는다. 설정을 바꾸는 테스트는 `after_each`에서 `reset_to_defaults()`로 되돌린다.
- **정적 함수와 자동 로드:** 정적 함수 안에서는 자동 로드 이름(`InputActions`)을 못 쓴다. 스크립트를 `preload`해서 쓴다.
- **화면 없는 실행:** `DisplayServer.keyboard_get_keycode_from_physical`, 창 크기·모드 같은 창 기능은 headless에서 오류가 난다. `DisplayServer.get_name() == "headless"`면 건너뛴다.
- **컴파일 오류면 테스트가 멈춘다:** 스크립트에 문법 오류가 있으면 러너가 끝나지 않는다. `timeout 900 tools/test.sh > build/test_all.log`처럼 시간 제한을 걸고 파일로 받아 확인한다.
- **내장 클래스와 같은 이름:** 새 class_name을 지을 때 Godot 내장 클래스(예: `Noise`)와 겹치지 않는지 본다.
- **길찾기 지도 굽기:** CSG 지형은 트리에 들어간 다음 프레임에 모양이 생긴다. 이미 트리에 있는 NavigationRegion3D에 지도를 바꿔 넣으면 `--fixed-fps`에서 길찾기 서버가 받지 못한다. 그래서 `Zone`은 지역을 트리에서 뺐다가 구운 새 지도를 넣고 다시 붙인다. 구운 지도는 씬마다 한 번만 만든다. 구운 지도 표면은 바닥보다 0.5m 위라서 NavigationAgent3D의 `path_desired_distance`는 1.0으로 둔다.
- **Windows에서 생성 스크립트:** `open()`에 `encoding="utf-8"`을 주지 않으면 시스템 코드 페이지로 써져 한글이 깨진다. 콘솔 출력의 한글은 깨져 보여도 파일은 괜찮다.
- **캐릭터 동작:** 원본(약 450MB, 500~650개)에서 `tools/extract_character.py`로 쓰는 동작만 뽑아 모델 파일에 넣는다(이름은 idle, attack_1 등 역할 이름). 여·남은 원본 이름의 앞부분(endminf/girl, endminm/boy)으로 구분한다. 원본 공격·회피 동작은 몸(뿌리 뼈 Bip001)이 앞으로 1~4m 나가므로 `TRIMS`로 앞부분만 자르고 `ROOT_LOCKED`로 제자리에 묶은 뒤, 같은 거리를 `AttackData.advance`에 넣어 플레이어가 직접 나아간다(벽과 적에 막히고 동기화된다). 실행 중에 glTF를 읽으면 "-loop" 꼬리가 이름에 남고 반복이 꺼져 있으므로 `PlayerBody._normalize_animation_names`가 고친다. 모델 파일을 다시 뽑으면 비공개 에셋 저장소에도 다시 올린다.
- **뼈대의 부모가 움직인다:** 이 모델의 Skeleton3D는 Bip001 노드 아래에 있고, 동작이 Bip001 노드 자체를 움직인다(공격·스킬은 몸을 수십 cm 띄운다). 뼈대 공간 ↔ 몸 공간 변환을 한 번만 구해 두면 손·발 위치가 통째로 어긋난다. `PlayerBody._update_space()`로 매번 구한다.
- **동작 층:** AnimationNodeOneShot은 재생 중에 다시 틀면 섞지 않고 처음으로 튄다. 연속 공격은 Transition(동작 고르기, 섞어서 바꿈) + TimeSeek(같은 동작 되감기) + Blend2(섞는 양은 코드가)로 만든다. Transition은 한 번도 요청을 받지 않으면 아무것도 내보내지 않아 뼈대 뿌리가 초기값으로 돌아가 몸이 눕는다. 만들 때 처음 상태를 꼭 요청한다.
- **이동 동작 고르기:** 걸음 주기가 다른 동작을 섞으면 다리가 엉킨다. 속도 구간마다 하나를 골라(AnimationNodeTransition) 실제 속도/원래 속도로 재생 속도를 맞춘다.
- **몸의 속도 재기:** 그리는 프레임마다 위치 차이로 재면 속도가 0과 큰 값 사이를 오간다. 내 플레이어는 `get_real_velocity()`, 원격 플레이어는 위치가 바뀐 시간 간격으로 잰다.
- **카메라:** 카메라 팔(SpringArm3D)이 매 물리 프레임 카메라 위치를 정한다. 카메라의 position을 직접 바꾸면(흔들림 등) 카메라가 머리 속으로 들어간다. 흔들림은 `h_offset`/`v_offset`으로 준다. 카메라가 머리에 붙으면 내 몸을 그림자만 남긴다.
- **계단 발 맞춤:** 몸은 보이지 않는 경사로를 타고, 보이는 디딤판은 물리 레이어 5(`foot_ground`, 값 16)에만 충돌한다. 발 IK만 이 레이어를 본다. 길찾기 지도는 레이어 1만 읽는다.
- **애니메이션 위에 덧입히기:** 발 IK·얼굴 빛은 `BodyPoseModifier`(SkeletonModifier3D)에서 한다. 수정자 결과는 그리는 프레임에만 남아서, 나중에 뼈를 읽으면 원래 애니메이션 자세가 나온다.
- **옷자락 물리(SpringBoneSimulator3D):** Godot 4.5는 중심(center)을 다른 노드나 뼈로 하면 충돌 모양 위치를 잘못 계산한다. 뼈대(Skeleton3D) 자신을 중심 노드로 하고, 중력 방향은 뼈대 기준이라 매 프레임 넣는다(`_update_cloth_gravity`). 사슬의 끝 뼈가 시작 뼈 아래에 있지 않으면 엔진 오류가 난다(관리자(남)의 `piaodai_back_R`은 마디마다 등뼈에 붙어 있어 사슬이 아니다). `_is_chain`으로 거른다. 망토에 매달린 끈은 부모 사슬 다음에 계산해야 한다.
- **원본 게임 전용 재질:** 원본은 전용 셰이더로 그린다. 그림자 메시는 마스크의 빨간 채널에 세기를 넣어 두어서 그냥 칠하면 하늘색 줄이 생긴다(`shade_overlay.gdshader`로 곱한다). 얼굴은 얼굴이 보는 방향으로 고르게 비춘다. 캐릭터는 만화풍 재질(`toon.gdshader`/반투명 `toon_alpha.gdshader`, 공통 `toon_common.gdshaderinc`, 외곽선 `outline.gdshader`)로 그리고, 얼굴 그림자 지도(SDF)는 파란 채널을 쓴다. 색 띠·발광 마스크는 `CharacterAppearance.texture(이름)`으로 찾는다. 재질은 플레이어끼리 함께 쓰므로 메시마다 덮어쓰는 재질로 바꾼다. **면이 하나뿐인 메시는 `material_override`로 넣는다**: 실행 중에 읽은 glTF의 눈동자 메시에 면별 재질을 넣으면 화면 없는 실행의 렌더러가 "material is null" 오류를 냈다(`_set_material`).
- **셰이더에서 POSITION 쓰지 않기:** 정점 단계에서 POSITION을 한 번이라도 쓰면 엔진이 그 재질의 기본 변환을 통째로 건너뛴다. 눈썹을 카메라 쪽으로 당길 때는 VERTEX를 옮긴다(`toon.gdshader`의 depth_bias).
- **눈:** 흰 마름모 하이라이트는 `hidden_bones`로 그 뼈를 한 점으로 줄여 숨긴다. 원본 동작이 오른쪽 눈 뼈만 움직이므로 추출 도구의 `FROZEN_BONES`로 눈 뼈 트랙을 뺀다.
- **실행 중에 읽은 glTF 텍스처:** 밉맵이 없다. `CharacterAppearance._add_mipmaps`가 원본 크기 그대로 밉맵만 만든다.
- **프로젝트 안에 스크립트 사본을 두지 않는다:** `build/`도 프로젝트 안이다. `class_name`이 있는 스크립트를 거기 복사해 두면 전역 클래스가 사본으로 바뀌어 엉뚱하게 돈다. 백업은 프로젝트 밖(임시 폴더)에 둔다.
- **실행 중에 읽는 소리:** `AudioStreamWAV.load_from_buffer`로 zip 안의 WAV를 읽는다. 이 PC에는 소리 인코더(ffmpeg)가 없어서 WAV 그대로 묶는다. 같은 zip은 플레이어끼리 한 번만 읽는다(`CharacterFx._loaded`).
- **원작 이펙트:** 이펙트 glb의 노드에는 메시가 없다. 원작은 노드마다 파티클 시스템이 메시·판을 그린다(`assets/data/*.json`). 재질 설정은 glb 재질의 extras(`floats`, `colors`, `vfx`)에 있다. 파티클 JSON은 유니티(왼손) 좌표 그대로라 그릴 때 X를 뒤집는다. 인스턴스 변환 자리에 그리기 정보를 담으므로 MultiMesh의 `custom_aabb`를 직접 줘야 화면 밖으로 잘리지 않는다. 이벤트의 `end`에서 남은 파티클까지 한 번에 지운다(원작과 같다). 원작 강도(최대 100)는 원작 화면에서 하얗게 날아가게 만든 값이라 셰이더에서 밝기를 자른다(`max_brightness`).
- **카메라 거리:** SpringArm3D의 충돌은 끄고(`collision_mask = 0`) 거리를 직접 정한다(`Player._camera_clearance`). 막히면 바로 당기고 풀리면 천천히 되돌리기 위해서다. 자유 시점은 얼굴을 가까이 보는 것이 목적이라, 카메라가 정말 머리 속(0.1m)에 들어갔을 때만 몸을 숨긴다(3인칭은 0.35m).
- **1인칭 머리 숨기기:** 머리 뼈를 줄이는 방법은 머리카락 옷자락 물리(머리 뼈 아래 사슬)를 망가뜨릴 수 있어서, 머리 메시(얼굴, 눈썹, 눈동자, 머리카락, 바이저)만 그림자로 남긴다. 카메라 위치는 눈 뼈(`eyeLfJoint`/`eyeRtJoint`) 가운데다.
- **텍스처 시트(연기·파편):** 그림 한 장에 여러 칸이 든 시트는 파티클마다 칸 번호(커스텀 데이터 w)와 함께 칸 수(`sheet_tiles`)를 재질에 넘겨야 한 칸만 그린다. 빠뜨렸더니 그림 전체가 작게 반복되어 스킬을 쓸 때 바닥에 이상한 무늬가 깔렸다(사용자가 찾음). `FxEffect._material`이 시스템마다 넣는다.
- **find_children와 스크립트 클래스:** `find_children(이름, 종류)`의 종류는 엔진 클래스만 알아본다(`FxEffect` 같은 class_name은 안 된다). 종류를 비우고 `is`로 거른다.
- **사이트 자료:** studio.warfarin.wiki의 데이터 서버(assets.warfarin.wiki)는 Cloudflare가 자동 요청을 막는다(우회하지 않는다). 사용자가 준 추출 꾸러미(`!File/Endministrator_Extras/`)에 같은 자료가 있다: `characters/*/weapon_binding.json`(무기 자리), `animation_events.json`(동작별 소리·이펙트 시각), `effect_catalog.json`, `assets/data/*.json`(파티클). 사이트 스크립트는 글자로만 받아 읽는다(실행하지 않는다).
- **무기 자리:** 원작 연결 정보(`weapon_binding.json`의 `battle.copies`)상 전투 무기는 오른손 `wep_R`(fight)이고, 무기를 꺼내는 동작의 처음 0.4초는 등 뒤 `GENERATED_wep_M_...`(idle)다. 왼손 `wep_L`은 캐릭터 화면 무기 보기(`mounts`, 메뉴) 자리인데, 이것을 전투에 써서 무기를 왼손에 쥐는 실수를 했다. 동작마다 자리는 `CharacterAppearance.weapon_timelines`(여·남이 시각이 조금 다르다). 이동·대기 동작에는 무기가 없다(원작처럼 싸우는 동작에서만 나타난다).
- **대기 연출:** 쉬는 자세·무기 꺼내기·멈추기 같은 대기 연출(`PlayerBody.IDLE_CLIPS`)도 동작 층에서 튼다. 움직이면 바로 끊어야 해서 실제 속도(`_raw_speed`)를 본다(이동 동작을 고르는 속도는 부드럽게 따라가서 0.3초쯤 늦다). 섞여 들어오는 동안(0.25초)에도 무기 자리는 그 동작의 것을 따른다(`_action_showing`). 원본 멈추기 동작은 1m쯤 미끄러지므로 제자리로 묶고, 캐릭터 화면에 들어오는 동작(1.6m 앞에서 걸어 들어와 제자리에서 끝남)은 묶지 않는다.
- **화면 확인은 조용히:** 사용자는 작업하는 동안 같은 PC로 다른 일을 한다. 게임 창을 화면에 띄우거나 포커스·마우스·소리를 가져가면 방해가 된다(실제로 그랬다). 화면 확인은 `tools/capture.sh`/`tools/screenshot.sh`로만 한다. 이 도구들은 다음처럼 돈다.
  - override.cfg로 포커스를 뺏지 않는 1x1 창을 띄우고, `main.gd`가 곧바로 화면 밖으로 옮겨 1280x720으로 키운다. 처음부터 화면 밖에 띄우는 설정은 Godot가 화면 안으로 되돌려서 쓸 수 없었다. 최소화로 띄웠다가 되살리면 포커스를 뺏는다.
  - `--audio-driver Dummy`로 소리를 끈다.
  - 마우스는 가두지 않는다(`MouseLock`). 가두면 커서가 화면 밖 창으로 끌려간다.
  - 저장된 창 설정(전체 화면)은 적용하지 않는다(`GameSettings.manage_window`).
  - 화면 확인 중에는 포커스를 잃어도 일시정지하지 않는다(`main.is_recording()`). 캐릭터 화면의 무기 보기는 `--character-weapon`, 1인칭은 `--first-person`, 얼굴 앞 자유 시점은 `--free-face`로 찍는다.
- **Python -I:** `-I`는 `PYTHONIOENCODING` 같은 환경 변수를 무시한다. 한자·한글을 콘솔에 찍을 때는 스크립트에서 `sys.stdout.reconfigure(encoding="utf-8")`를 부른다.
- **도구 쓸 때(Claude 세션):** Bash의 heredoc 안 Python 문자열에 백슬래시(줄바꿈 표시 등)를 쓰면 실행 도구를 거치며 지워진다. 백슬래시가 든 스크립트는 Write로 파일을 만들어 실행하고, 이미 있는 파일은 Edit로 고친다.
- **에셋 자동 업데이트:** 모델은 비공개 에셋 저장소(`RoastedBeer24/CPGP-assets`)의 릴리스 `assets`에만 올린다. 파일 목록은 `tools/publish_assets.py`의 `FILES`. 그 도구는 저장소가 공개면 거부한다. 게임은 설정의 에셋 키(GitHub 토큰)로 받는데, 키는 GitHub API에만 보낸다. 실제 파일은 다른 호스트로 넘겨받으므로 `max_redirects = 0`으로 직접 따라가며 키를 뺀다(`AssetUpdater._download`). 모델의 동작 이름이 바뀌면 옛 게임이 새 모델을 받아 깨질 수 있으니 **게임 푸시와 에셋 올리기를 함께** 한다.
- **코드로 만드는 자세:** 이 모델은 뼈 축이 제각각(3ds Max Biped)이라 각도 대신 "몸 기준 방향"으로 뼈를 돌린다(`PlayerBody._point_bone`). `Basis.looking_at`은 방향이 위쪽 기준과 나란하거나 0이면 오류가 난다.
