# 사용 에셋 목록

게임에 쓰는 모든 외부 에셋의 출처와 라이선스를 기록합니다. 정책은 [기초 구상서 §1](design/00-foundation.md)을 따릅니다.

| 에셋 | 저장소 내 경로 | 출처 (URL) | 작가 | 라이선스 | 비고 |
|---|---|---|---|---|---|
| Noto Sans KR (Regular, Bold) | `assets/fonts/noto_sans_kr/` | https://github.com/notofonts/noto-cjk | Google, Adobe | SIL Open Font License 1.1 (`LICENSE.txt` 동봉) | 게임 기본 한글 폰트 |
| 관리자(여) 모델 (Endministrator_F) | `assets/characters/endministrator_f/endministrator_f.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (studio.warfarin.wiki에서 추출) | 원작: 명일방주: 엔드필드 (Hypergryph) | 상용 게임 자산. 재배포 불가 | 아래 "저장소에 없는 에셋" 참고 |
| 관리자(남) 모델 (Endministrator_M) | `assets/characters/endministrator_m/endministrator_m.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, 같은 사이트에서 추출) | 원작: 명일방주: 엔드필드 (Hypergryph) | 상용 게임 자산. 재배포 불가 | 원본은 `!File/endministrator_m/` |
| 관리자 소리·보이스 꾸러미 | `assets/characters/endministrator_{f,m}/*_fx.zip` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, `!File/Endministrator_Extras/`) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | `tools/extract_character_fx.py`로 쓰는 동작의 것만 묶음 |
| 무기 타르 11 (wpn_sword_0003) | `assets/weapons/tarr_11.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, `!File/Tarr_11.glb`) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | 왼손(wep_L)에 쥔다 |

## 저장소에 없는 에셋
공개 저장소에 올릴 수 없는 에셋입니다. 각자 PC에 직접 넣고, `.gitignore`로 커밋에서 뺍니다.
파일이 없으면 게임은 대신할 것(캡슐 몸 등)으로 그대로 돌아가고, 자동 테스트도 모두 통과합니다.
실행 파일(exe)에도 넣지 않습니다(`export_presets.cfg`에서 제외). 공개 릴리스에 섞여 나가지 않게 하고, 자동 업데이트가 exe만 바꿔도 각자 넣어 둔 모델이 남게 하기 위함입니다.

| 에셋 | 개발할 때 넣는 곳 | 실행 파일로 할 때 넣는 곳 |
|---|---|---|
| 관리자(여) 모델 | `assets/characters/endministrator_f/endministrator_f.glb` | `Crossfield.exe`가 있는 폴더의 `characters/endministrator_f.glb` |
| 관리자(남) 모델 | `assets/characters/endministrator_m/endministrator_m.glb` | `Crossfield.exe`가 있는 폴더의 `characters/endministrator_m.glb` |
| 관리자 소리 꾸러미 | `assets/characters/endministrator_{f,m}/endministrator_{f,m}_fx.zip` | `characters/endministrator_{f,m}_fx.zip` |
| 무기 모델 | `assets/weapons/tarr_11.glb` | `weapons/tarr_11.glb` |
| 적 모델 (아직 없음) | `assets/enemies/<이름>.glb` | `Crossfield.exe`가 있는 폴더의 `enemies/<이름>.glb` |

- **애니메이션이 든 원본(`*_Animated.glb`, 약 450MB)에서** 게임에 쓰는 동작(이동·멈추기, 점프·착지, 공격 5단계, 대시 공격, 처형, 낙하 공격, 스킬, 궁극기, 회피, 맞음, 쓰러짐, 쉬는 자세와 특수 대기, 무기 꺼내기·거두기, 캐릭터 화면 동작) 49개만 골라 가벼운 파일(여 약 45MB, 남 약 57MB)을 만들어 넣습니다. 고르는 동작 목록은 도구 안의 `ROLES`에 있고, 여·남은 원본 이름을 보고 알아서 고릅니다.
  ```bash
  python3 tools/extract_character.py "!File/Endministrator_F_Animated.glb" assets/characters/endministrator_f/endministrator_f.glb
  python3 tools/extract_character.py "!File/endministrator_m/Endministrator_M_Animated.glb" assets/characters/endministrator_m/endministrator_m.glb
  ```
- 공격 동작의 타격 시각과 내디디는 거리는 원본에서 재서 `data/characters/*/kit.tres`에 넣었습니다. 동작을 바꾸면 다시 잽니다.
- 텍스처는 glb 안에 들어 있어 따로 넣지 않아도 됩니다.
- **소리·보이스:** 원작 꾸러미에는 동작마다 몇 초에 어떤 소리·보이스가 나는지가 있습니다. 게임이 쓰는 동작의 것만 골라 캐릭터마다 zip 하나(약 32MB)로 묶습니다. 게임은 실행 중에 zip을 읽어 동작에 맞춰 냅니다(`src/player/character_fx.gd`).
  ```bash
  python3 tools/extract_character_fx.py "!File/Endministrator_Extras" F assets/characters/endministrator_f/endministrator_f_fx.zip
  python3 tools/extract_character_fx.py "!File/Endministrator_Extras" M assets/characters/endministrator_m/endministrator_m_fx.zip
  ```
- **연출 카메라:** 원작 궁극기 카메라 컷과 캐릭터 화면용 카메라 자세(`metadata/camera.json`)도 `fx.json`에 넣습니다.
- **이펙트:** 원작 이펙트 모델(glb)과 파티클 설정(json)도 같은 zip의 `effects/`에 넣습니다. 게임이 원작 셰이더와 파티클 시스템을 다시 만들어 그립니다(`docs/dev/effects.md`). 원작 자료에 이펙트가 없는 동작(궁극기, 대시 공격)은 칼날 자리에 남는 빛의 띠(`src/player/weapon_trail.gd`)로 대신합니다.
- 개발용 위치에 넣으면 에디터를 열거나 `tools/test.sh`를 돌릴 때 Godot가 자동으로 가져옵니다.
- 실행 파일은 켤 때 `characters/` 폴더의 모델을 직접 읽습니다. 모델이 있는 PC에서 `tools/export_windows.sh`를 돌리면 모델까지 넣은 `build/Crossfield-windows-with-model.zip`이 생기므로, 가족 PC에 처음 설치할 때는 이것을 풀면 됩니다. 이 zip은 어디에도 올리지 않습니다.

### 모델 자동 업데이트 (비공개 에셋 저장소)
게임 실행 파일은 공개 릴리스로 받지만, 모델은 공개할 수 없어서 **비공개** 에셋 저장소(`RoastedBeer24/CPGP-assets`)의 릴리스 `assets`에 따로 올립니다. 게임은 켤 때 그 릴리스의 목록(`assets.json`, 파일마다 SHA-256)과 자기 `characters/` 파일을 비교해 바뀐 것만 받습니다(`src/core/asset_updater.gd`).
- **올리기 (모델을 다시 뽑았을 때):** `python3 tools/publish_assets.py`. 저장소는 2026-10-30에 비공개로 만들어 두었습니다(없으면 `--create`가 비공개로 만듭니다). 저장소가 공개면 올리지 않습니다.
- **받기:** PC마다 게임 설정 → 게임 → "에셋 키"에 그 저장소를 읽을 수 있는 GitHub 토큰을 한 번 넣습니다. 키가 없으면 모델을 받지 않고 있던 모델을 그대로 씁니다.
  - 토큰 만들기: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. Repository access는 "Only select repositories"로 `CPGP-assets` 하나만, Permissions는 Contents: Read-only만 줍니다.
- 공개 저장소(이 저장소)의 릴리스나 커밋에는 절대 넣지 않습니다.
