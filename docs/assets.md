# 사용 에셋 목록

게임에 쓰는 모든 외부 에셋의 출처와 라이선스를 기록합니다. 정책은 [기초 구상서 §7.3](design/00-foundation.md)을 따릅니다.

| 에셋 | 저장소 내 경로 | 출처 (URL) | 작가 | 라이선스 | 비고 |
|---|---|---|---|---|---|
| Noto Sans KR (Regular, Bold) | `assets/fonts/noto_sans_kr/` | https://github.com/notofonts/noto-cjk | Google, Adobe | SIL Open Font License 1.1 (`LICENSE.txt` 동봉) | 게임 기본 한글 폰트 |
| 플레이어 캐릭터 모델 (Endministrator_F) | `assets/characters/endministrator_f/endministrator_f.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 | 원작: 명일방주: 엔드필드 (Hypergryph) | 상용 게임 자산. 재배포 불가 | 아래 "저장소에 없는 에셋" 참고 |

## 저장소에 없는 에셋
공개 저장소에 올릴 수 없는 에셋입니다(구상서 §7.3). 각자 PC에 직접 넣고, `.gitignore`로 커밋에서 뺍니다.
파일이 없으면 게임은 대신할 것(캡슐 몸 등)으로 그대로 돌아가고, 자동 테스트도 모두 통과합니다.
실행 파일(exe)에도 넣지 않습니다(`export_presets.cfg`에서 제외). 공개 릴리스에 섞여 나가지 않게 하고, 자동 업데이트가 exe만 바꿔도 각자 넣어 둔 모델이 남게 하기 위함입니다.

| 에셋 | 개발할 때 넣는 곳 | 실행 파일로 할 때 넣는 곳 |
|---|---|---|
| 플레이어 캐릭터 모델 | `assets/characters/endministrator_f/endministrator_f.glb` | `CyberUniverse.exe`가 있는 폴더의 `characters/endministrator_f.glb` |

- **애니메이션이 든 원본(`Endministrator_F_Animated.glb`, 약 450MB)이 있으면** 게임에 쓰는 동작만 골라 가벼운 파일(약 23MB)을 만들어 넣습니다. 고르는 동작 목록은 도구 안의 `ROLES`에 있습니다.
  ```bash
  python3 tools/extract_character.py "!File/Endministrator_F_Animated.glb" assets/characters/endministrator_f/endministrator_f.glb
  ```
- 애니메이션이 없는 `Endministrator_F.glb`를 그대로 위 이름으로 복사해도 됩니다. 그때는 걷기·달리기 자세를 코드로 만듭니다. 텍스처는 glb 안에 들어 있어 따로 넣지 않아도 됩니다.
- 개발용 위치에 넣으면 에디터를 열거나 `tools/test.sh`를 돌릴 때 Godot가 자동으로 가져옵니다.
- 실행 파일은 켤 때 `characters/` 폴더의 모델을 직접 읽습니다. 모델이 있는 PC에서 `tools/export_windows.sh`를 돌리면 모델까지 넣은 `build/CyberUniverse-windows-with-model.zip`이 생기므로, 가족 PC에 처음 설치할 때는 이것을 풀면 됩니다. 이 zip은 어디에도 올리지 않습니다.
