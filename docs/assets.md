# 사용 에셋 목록

게임에 쓰는 모든 외부 에셋의 출처와 라이선스를 기록합니다. 정책은 [기초 구상서 §1](design/00-foundation.md)을 따릅니다.

| 에셋 | 저장소 내 경로 | 출처 (URL) | 작가 | 라이선스 | 비고 |
|---|---|---|---|---|---|
| Noto Sans KR (Regular, Bold) | `assets/fonts/noto_sans_kr/` | https://github.com/notofonts/noto-cjk | Google, Adobe | SIL Open Font License 1.1 (`LICENSE.txt` 동봉) | 게임 기본 한글 폰트 |
| 관리자(여) 모델 (Endministrator_F) | `assets/characters/endministrator_f/endministrator_f.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (studio.warfarin.wiki에서 추출) | 원작: 명일방주: 엔드필드 (Hypergryph) | 상용 게임 자산. 재배포 불가 | 아래 "저장소에 없는 에셋" 참고 |
| 관리자(남) 모델 (Endministrator_M) | `assets/characters/endministrator_m/endministrator_m.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, 같은 사이트에서 추출) | 원작: 명일방주: 엔드필드 (Hypergryph) | 상용 게임 자산. 재배포 불가 | 원본은 `!File/endministrator_m/` |
| 관리자 소리·보이스 꾸러미 | `assets/characters/endministrator_{f,m}/*_fx.zip` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, `!File/Endministrator_Extras/`) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | `tools/extract_character_fx.py`로 쓰는 동작의 것만 묶음 |
| 무기 타르 11 (wpn_sword_0003) | `assets/weapons/tarr_11.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, `!File/Tarr_11.glb`) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | 싸울 때 오른손(wep_R)에 쥔다 |
| 아케쿠리 모델 (chr_0019_karin) | `assets/characters/akekuri/akekuri.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, `!File/Akekuri_Complete_Assets.zip`, studio.warfarin.wiki에서 추출) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | 원본은 `!File/Akekuri_Assets/models/`. 저해상도 메시(lod1~3)와 그림자 대용 메시는 뺀다 |
| 아케쿠리 소리·보이스·이펙트 꾸러미 | `assets/characters/akekuri/akekuri_fx.zip` (**저장소에 없음**) | 같은 파일 | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | `tools/extract_character_fx.py "!File/Akekuri_Assets" Akekuri ...` |
| 무기 O.B.J. 엣지 오브 라이트 (wpn_sword_0019) | `assets/weapons/edge_of_lightness.glb` (**저장소에 없음**) | 같은 파일 (`weapons/OBJ_Edge_of_Lightness.glb`) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | 아케쿠리의 무기. 오른손(wep_R)에 쥔다 |
| 본 크러셔 적 모델 (eny_0029_lbmob, 0033_lbhunt, 0018_lbtough, 0068_lbtough2, 0051_rodin) | `assets/enemies/*.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, `!File/Bonekrusher_Complete_Assets.zip`, studio.warfarin.wiki에서 추출) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | `tools/extract_enemy.py`로 쓰는 동작만 뽑는다(공격의 몸 이동·회전 곡선은 `data/enemies/*.tres`의 travel·turn에 넣고 동작에서는 뺀다). 로댄은 소리 꾸러미(`assets/enemies/rodin_fx.zip`)도 만든다. 원본은 `!File/Bonekrusher_Assets/` |
| 진천우·아크라이트·포그라니치니크 모델 (chr_0005_chen, chr_0007_ikut, chr_0029_pograni) | `assets/characters/{chen_qianyu,arclight,pogranichnik}/*.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 (2026-10-31, `!File/Chen_Arclight_Pogranichnik_Complete_Assets.zip`, studio.warfarin.wiki에서 추출) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | 원본은 `!File/Chen_Arclight_Pogranichnik_Assets/` |
| 세 캐릭터 소리·보이스·이펙트 꾸러미 | `assets/characters/<이름>/<이름>_fx.zip` (**저장소에 없음**) | 같은 파일 | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | `tools/extract_character_fx.py "!File/Chen_Arclight_Pogranichnik_Assets" chr_0005_chen ...` |
| 무기 숭배의 시선·십이문·끝없는 방랑 (wpn_sword_0015, 0018, 0016) | `assets/weapons/{aspirant,twelve_questions,never_rest}.glb` (**저장소에 없음**) | 같은 파일 (`weapons/`) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | 세 캐릭터의 전용 무기. 오른손(wep_R)에 쥔다 |
| 캐릭터 고르기 아이콘 (공식 초상화) | `assets/characters/<이름>/<이름>_icon.png` (**저장소에 없음**) | 사용자가 직접 준 그림 (2026-10-31, 원본은 `!File/Portraits/`) | 원작: 명일방주: 엔드필드 | 상용 게임 자산. 재배포 불가 | `python tools/make_icons.py`로 얼굴 부분을 256px로 자른다(Pillow 필요) |

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
| 아케쿠리 모델·꾸러미 | `assets/characters/akekuri/akekuri.glb`, `akekuri_fx.zip` | `characters/akekuri.glb`, `characters/akekuri_fx.zip` |
| 아케쿠리 무기 | `assets/weapons/edge_of_lightness.glb` | `weapons/edge_of_lightness.glb` |
| 캐릭터 고르기 아이콘 | `assets/characters/<이름>/<이름>_icon.png` | `characters/<이름>_icon.png` |
| 진천우·아크라이트·포그라니치니크 | `assets/characters/<이름>/<이름>.glb`, `<이름>_fx.zip` | `characters/<이름>.glb`, `characters/<이름>_fx.zip` |
| 세 캐릭터 무기 | `assets/weapons/{aspirant,twelve_questions,never_rest}.glb` | `weapons/<이름>.glb` |
| 적 모델 (본 크러셔) | `assets/enemies/<이름>.glb` (lbmob, lbhunt, lbtough, lbtough_elite, rodin), `rodin_fx.zip` | `Crossfield.exe`가 있는 폴더의 `enemies/<이름>.glb`, `enemies/rodin_fx.zip` |
| (모든 모델) 구운 장면 | `build/baked/<종류>/<이름>.scn` (`tools/publish_assets.py`가 만든다) | glb 자리의 같은 이름 `.scn` (예: `characters/akekuri.scn`). 있으면 glb 대신 읽는다 |

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
- **올리기 (모델을 다시 뽑았을 때):** `python3 tools/publish_assets.py`. 저장소는 2026-10-30에 비공개로 만들어 두었습니다(없으면 `--create`가 비공개로 만듭니다). 저장소가 공개면 올리지 않습니다. 릴리스에 있는 목록과 비교해 바뀐 파일만 올립니다.
- **구운 모델(.scn):** 모델은 glb 대신 미리 구운 Godot 장면을 올립니다(2026-10-31부터). 올리기 전에 도구가 `tools/bake_models.gd`로 `build/baked/`에 굽습니다(원본이나 굽는 코드가 더 새로울 때만, Godot 위치를 `GODOT` 환경 변수로). 큰 색·법선·설정·발광 텍스처는 BC7로 압축하고 모든 텍스처에 밉맵을 넣습니다. 내보낸 게임(Godot 내보내기 템플릿)에는 텍스처 압축기가 없어서 glb를 그대로 읽으면 텍스처가 압축되지 않은 채 그래픽 메모리를 4배 쓰고(모델 전부 약 2GB → 구우면 약 0.5GB), 그림을 풀고 밉맵을 만드느라 캐릭터 하나에 1~2초 멈췄습니다(구운 장면은 0.2초). 게임은 `characters/<이름>.glb` 자리에서 같은 이름의 `.scn`을 먼저 찾고, 없거나 못 읽으면 glb를 읽습니다(`CharacterAppearance.model_entry`).
- **받기:** PC마다 게임 설정 → 게임 → "에셋 키"에 그 저장소를 읽을 수 있는 GitHub 토큰을 한 번 넣습니다. 키가 없으면 모델을 받지 않고 있던 모델을 그대로 씁니다.
  - 토큰 만들기: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. Repository access는 "Only select repositories"로 `CPGP-assets` 하나만, Permissions는 Contents: Read-only만 줍니다.
- 공개 저장소(이 저장소)의 릴리스나 커밋에는 절대 넣지 않습니다.
