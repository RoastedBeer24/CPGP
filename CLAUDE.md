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
- 모델 추출은 사용자가 해서 준다(GPT로 사이트에서 추출, 형식은 `!File/` 아래 원본과 같다). 사이트를 브라우저로 열지 않는다.

## 기획 문서 (먼저 읽을 것)
- `docs/design/00-foundation.md`: 기초 구상서. 전제, 전투 규칙, 조작, 협동, 로드맵, 검수 기록
- `docs/dev/conventions.md`: 개발 규칙 (반드시 지킬 것)
- `docs/dev/testing.md`: 실행, 테스트, 스크린샷, Windows 빌드 방법
- `docs/assets.md`: 에셋 출처, 모델 넣는 법, 비공개 에셋 저장소

## 진행 상황
| 마일스톤 | 상태 | 비고 |
|---|---|---|
| M0 정리 | 완료 | 이름 변경(설치된 게임의 자동 업데이트 유지), 옛 게임 코드 삭제. 메뉴·설정·자동 업데이트·협동 연결·캐릭터 모델 처리·만화풍 셰이더는 다시 씀 |
| **M1 첫 전투 방** | **검수 대기** | 관리자(여·남) 검 5연속·대시 공격·처형·배틀 스킬(원석 결정)·궁극기(결정 파쇄)·회피(완벽한 회피)·경직, 적 3종(임시 도형 몸), 웨이브 3개, HUD, 협동, 캐릭터 고르기 (`docs/dev/review/m1.md`) |
| M2 적 모델 ~ M6 다듬기 | 예정 | 구상서 §6 |

### 지금 구조
- `src/player/player.gd`: 3인칭 액션 조작. 카메라(CameraRig, 몸과 따로 돈다), 카메라 기준 이동, 공격 연속·스킬·회피·대상 고정·쓰러짐·동료 일으키기. 동작은 `action_id`/`action_count`, 회피는 `dodge_count`로 동기화
- `src/player/player_body.gd`: 모델·만화풍 재질·옷자락·발 IK, 이동 동작 고르기, 동작 층(공격·스킬·회피·맞음·쓰러짐), 코드로 만든 검(`wep_R`에 붙임)
- `src/combat/`: `KitData`(캐릭터 전투 구성) → `AttackData`(동작 하나: 길이, 이어지는 시각, 내디딤 거리) → `HitData`(타격 하나: 시각, 배율, 경직, 범위, 원석 결정 효과). `Health`, `Hitbox`, `CombatQuery.melee`, `DamageNumber`, `HitSpark`
- `src/enemies/`: `Enemy`(호스트가 판단: 쫓기 → 예고 → 맞히기 → 쉬기, 움찔·경직·원석 결정), `EnemyBody`(예고 표시, 모델 또는 도형 몸), `EnemyProjectile`, `EnemyData`/`EnemyAttackData`(`data/enemies/*.tres`)
- `src/zones/combat_room/`: 웨이브, 방 정리, 전멸 뒤 다시 시작. 적은 방 안의 `EnemySpawner`가 복제한다. 씬은 `tools/gen_combat_room.py`로 만든다
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
tools/export_windows.sh       # build/Crossfield-windows.zip (+ 옛 이름 CyberUniverse-windows.zip) 생성
python3 tools/gen_combat_room.py   # 전투 방 씬 다시 생성
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
- **캐릭터 고르기와 스폰:** 참여한 피어는 접속한 뒤 고른 캐릭터를 `Session._register`로 알리고, 호스트가 그때 스폰한다(접속 즉시 스폰하지 않는다). 캐릭터 이름은 스폰 정보로 모든 피어에 간다.
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
- **에셋 자동 업데이트:** 모델은 비공개 에셋 저장소(`RoastedBeer24/CPGP-assets`)의 릴리스 `assets`에만 올린다. 파일 목록은 `tools/publish_assets.py`의 `FILES`. 그 도구는 저장소가 공개면 거부한다. 게임은 설정의 에셋 키(GitHub 토큰)로 받는데, 키는 GitHub API에만 보낸다. 실제 파일은 다른 호스트로 넘겨받으므로 `max_redirects = 0`으로 직접 따라가며 키를 뺀다(`AssetUpdater._download`). 모델의 동작 이름이 바뀌면 옛 게임이 새 모델을 받아 깨질 수 있으니 **게임 푸시와 에셋 올리기를 함께** 한다.
- **코드로 만드는 자세:** 이 모델은 뼈 축이 제각각(3ds Max Biped)이라 각도 대신 "몸 기준 방향"으로 뼈를 돌린다(`PlayerBody._point_bone`). `Basis.looking_at`은 방향이 위쪽 기준과 나란하거나 0이면 오류가 난다.
