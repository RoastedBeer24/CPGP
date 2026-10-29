# 테스트와 실행 방법

## 사용자 PC에서 플레이하기 (Windows)
1. [Godot 4.5.1 표준판](https://godotengine.org/download/archive/4.5.1-stable/)을 내려받습니다. .NET판이 아닌 **표준판(Standard)**입니다.
2. Godot를 실행하고 **가져오기(Import)**에서 이 저장소 폴더의 `project.godot`를 선택합니다.
3. 에디터 오른쪽 위의 ▶ 버튼(또는 F5)을 누르면 게임이 실행됩니다.

마일스톤마다 무엇을 확인하면 되는지는 검수 체크리스트로 따로 드립니다.

## 자동 테스트
### 리눅스, macOS, 개발 환경
```bash
tools/test.sh            # 모든 테스트
tools/test.sh project    # 파일 경로나 테스트 이름에 project가 들어간 것만
```
- Godot 실행 파일은 `$GODOT`, PATH의 `godot`, `tools/setup_godot.sh`가 설치한 위치 순서로 찾습니다.
- 찾지 못하면 `tools/setup_godot.sh`가 공식 배포본을 내려받고 **SHA-512 체크섬을 검증**한 뒤 씁니다.
- 실패한 테스트가 있으면 종료 코드 1로 끝납니다.

### Windows (명령 프롬프트)
```bat
Godot_v4.5.1-stable_win64.exe --headless --path . --import
Godot_v4.5.1-stable_win64.exe --headless --fixed-fps 60 --path . --script res://tests/run_tests.gd
```

## 테스트 작성법
`tests/` 아래에 `test_`로 시작하는 `.gd` 파일을 만들고 `TestCase`를 상속합니다. `test_`로 시작하는 메서드가 하나의 테스트입니다.

```gdscript
extends TestCase


func test_damage_reduces_health() -> void:
	var health := Health.new()
	health.max_value = 100
	health.apply_damage(30)
	assert_eq(health.value, 70)


func test_enemy_spawns_in_tree() -> void:
	var enemy := add_child_autofree(Enemy.new())  # 테스트가 끝나면 자동 해제
	await tree.process_frame                       # 프레임 기다리기
	assert_true(enemy.is_inside_tree())
```

- 테스트마다 새 인스턴스가 만들어지고, `before_each()`와 `after_each()`가 앞뒤로 호출됩니다.
- 쓸 수 있는 검사: `assert_true`, `assert_false`, `assert_eq`, `assert_ne`, `assert_almost_eq`, `assert_not_null`, `fail`
- 테스트 도중 **엔진 오류나 스크립트 오류가 나면** 검사문이 없어도 그 테스트는 실패로 처리됩니다.
- `test_project.gd`는 `src/` 아래의 모든 스크립트와 씬을 불러와서, 문법 오류나 타입 누락이 있으면 실패합니다.
- 물리 테스트는 `await tree.physics_frame`으로 프레임을 진행합니다. `--fixed-fps 60` 덕분에 실제 시간을 기다리지 않습니다.

## 코옵 테스트
`tests/net/test_session.gd`는 한 프로세스 안에서 호스트와 클라이언트 2~3개를 띄워 실제 ENet으로 접속시킵니다.
- 피어마다 독립된 `SubViewport`(별도 3D 월드·물리 공간)와 `MultiplayerAPI`를 줍니다. 서로의 사본끼리 부딪히지 않습니다.
- 확인하는 것: 접속, 이동·시점·웅크림 동기화, 3인 플레이, 4번째 접속 거부, 퇴장 처리, 호스트 종료 시 클라이언트 정리

## 메뉴를 건너뛰고 바로 시작하기
게임 실행 파일 뒤에 `--`와 옵션을 붙이면 메인 메뉴를 건너뜁니다.
```bash
godot --path . -- --single                # 혼자 하기
godot --path . -- --host                  # 방 만들기
godot --path . -- --join=192.168.0.12     # 참여하기
```
한 PC에서 창 두 개로 코옵을 시험하려면 한 창은 `--host`, 다른 창은 `--join=127.0.0.1`로 띄웁니다.

## 화면 확인 (스크린샷)
```bash
tools/screenshot.sh                                   # 메인 씬
tools/screenshot.sh res://src/boot/main.tscn 30 build/screenshots/boot.png
tools/screenshot.sh "" 30 build/screenshots/game.png --single   # 4번째 인자부터는 게임 옵션
```
- 가상 화면(Xvfb)에서 씬을 정해진 프레임 수만큼 실행하고, 마지막 프레임을 PNG로 저장합니다.
- GPU가 없는 환경에서는 OpenGL(Compatibility) 렌더러로 대체됩니다. 배치와 UI는 확인할 수 있지만, 조명과 후처리는 실제 PC 화면과 다를 수 있습니다.
