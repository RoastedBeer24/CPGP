# 사용 에셋 목록

게임에 쓰는 모든 외부 에셋의 출처와 라이선스를 기록합니다. 정책은 [기초 구상서 §7.3](design/00-foundation.md)을 따릅니다.

| 에셋 | 저장소 내 경로 | 출처 (URL) | 작가 | 라이선스 | 비고 |
|---|---|---|---|---|---|
| Noto Sans KR (Regular, Bold) | `assets/fonts/noto_sans_kr/` | https://github.com/notofonts/noto-cjk | Google, Adobe | SIL Open Font License 1.1 (`LICENSE.txt` 동봉) | 게임 기본 한글 폰트 |
| 플레이어 캐릭터 모델 (Endministrator_F) | `assets/characters/endministrator_f/endministrator_f.glb` (**저장소에 없음**) | 사용자가 직접 준 파일 | 원작: 명일방주: 엔드필드 (Hypergryph) | 상용 게임 자산. 재배포 불가 | 아래 "저장소에 없는 에셋" 참고 |

## 저장소에 없는 에셋
공개 저장소에 올릴 수 없는 에셋입니다(구상서 §7.3). 각자 PC에 직접 넣고, `.gitignore`로 커밋에서 뺍니다.
파일이 없으면 게임은 대신할 것(캡슐 몸 등)으로 그대로 돌아가고, 자동 테스트도 모두 통과합니다.
GitHub Actions가 만드는 실행 파일에도 들어가지 않으므로, 모델이 들어간 실행 파일은 이 파일이 있는 PC에서 `tools/export_windows.sh`로 만듭니다.

| 에셋 | 넣는 곳 | 넣는 방법 |
|---|---|---|
| 플레이어 캐릭터 모델 | `assets/characters/endministrator_f/endministrator_f.glb` | 받은 `Endministrator_F.glb`를 이 이름으로 복사합니다. 텍스처는 glb 안에 들어 있어 따로 넣지 않아도 됩니다. 에디터를 열거나 `tools/test.sh`를 돌리면 Godot가 자동으로 가져옵니다. |
