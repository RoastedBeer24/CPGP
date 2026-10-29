# 개발 규칙

## 엔진
- **Godot 4.5.1** (표준판, GDScript)으로 고정합니다. 버전을 올릴 때는 따로 합의합니다.
- 렌더러는 **Forward+**, 3D 물리는 **Jolt Physics**를 씁니다.

## 폴더 구조
```
project.godot
src/            # 게임 코드와 씬. 기능별 폴더에 스크립트와 씬을 함께 둔다
  boot/         # 부팅 씬
  core/         # 이벤트 버스, 저장, 구역 전환 (M1~)
  net/          # 호스트·참여, 동기화 (M1~)
  player/  combat/  ai/  hacking/  cyberware/  inventory/  narrative/  ui/
  zones/        # 구역 씬
data/           # 데이터 파일(.tres): 무기, 임플란트, 아이템, 대화 등
assets/         # 공개 에셋. 출처는 docs/assets.md에 기록
tests/          # 자동 테스트 (framework/, unit/, ...)
tools/          # 개발용 셸 스크립트
docs/           # 기획 문서(design/), 개발 문서(dev/)
```
- 폴더는 필요해질 때 만듭니다. 빈 폴더를 미리 만들어 두지 않습니다.

## 이름 짓기
| 대상 | 형식 | 예 |
|---|---|---|
| 파일, 폴더 | snake_case | `player_controller.gd`, `zones/freight_docks/` |
| `class_name` | PascalCase | `PlayerController` |
| 함수, 변수 | snake_case | `apply_damage()`, `move_speed` |
| 상수, enum 값 | UPPER_SNAKE_CASE | `MAX_RAM`, `AlertState.SEARCHING` |
| 시그널 | 과거형 snake_case | `enemy_killed`, `alert_changed` |
| 내부용 멤버 | `_` 접두사 | `_velocity` |

## 코드
- **정적 타입 필수.** 타입 없는 변수와 인자는 프로젝트 설정에서 오류로 처리됩니다. 타입이 분명할 때는 `:=`로 추론해도 됩니다.
- **주석은 한국어로** 씁니다. 클래스와 공개 함수에는 `##` 문서 주석을 답니다. 코드가 무엇을 하는지보다 **왜 그렇게 하는지**를 적습니다.
- 들여쓰기는 탭(Godot 기본)입니다.
- **데이터와 로직 분리:** 수치와 정의는 `Resource`(.tres)로 두고 코드에 박아 넣지 않습니다.
- **느슨한 결합:** 시스템끼리 직접 참조하기보다 시그널로 통신합니다.

## 네트워크 (M1부터)
- 싱글 플레이도 "혼자 호스트하는 코옵"과 같은 경로로 돌아갑니다.
- 자기 캐릭터의 이동과 시점은 각 플레이어가 계산하고, **피해·AI·상호작용 결과의 판정은 호스트가** 합니다.
- 판정용 RPC는 `@rpc("any_peer", "call_local")`로 두고 받는 쪽에서 보낸 피어를 확인합니다(`_sender_is_owner()` 참고).
- RPC 인자에 타입이 붙은 배열(`Array[Vector3]`)을 쓰지 않습니다. `PackedVector3Array` 같은 패킹 배열을 씁니다.
- 체력처럼 호스트가 정하는 값은 해당 노드의 권한을 호스트(1)로 두고 MultiplayerSynchronizer로 퍼뜨립니다.
- 시간 판정(연사 제한 등)은 실제 시간 대신 물리 프레임 수로 잽니다.
- 새 기능은 코옵 상황(참여자 2~3명)에서도 동작하는지 테스트합니다.

## 리소스 불러오기
- 서로 참조하는 스크립트(예: Player ↔ WeaponHolder) 안에서 `.tres`를 `preload`하지 않습니다. 컴파일 도중 리소스가 깨질 수 있으므로 `_ready()`에서 `load()`합니다.

## 테스트와 커밋
- 새 시스템은 테스트와 함께 추가합니다. 테스트 작성법은 [testing.md](testing.md)에 있습니다.
- 커밋 전에 `tools/test.sh`가 통과해야 합니다.
- 생성되는 `*.uid` 파일은 함께 커밋합니다. `.godot/` 폴더는 커밋하지 않습니다.
