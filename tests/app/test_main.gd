extends TestCase
## 메인 메뉴 → 게임 → 일시정지 → 메뉴 복귀 흐름을 확인한다.

const MAIN_SCENE := preload("res://src/boot/main.tscn")

var main: Node


func before_each() -> void:
	main = MAIN_SCENE.instantiate()
	add_child_autofree(main)


func after_each() -> void:
	tree.paused = false
	if main.session != null:
		main.leave_session()


func test_starts_on_main_menu() -> void:
	assert_true(main.menu.visible)
	assert_false(main.hud.visible)
	assert_eq(main.session, null)


func test_single_play_starts_game() -> void:
	main.start_session(Session.Mode.SINGLE)
	await tree.process_frame
	assert_not_null(main.session)
	assert_false(main.menu.visible, "메뉴가 닫혀야 함")
	assert_true(main.hud.visible, "HUD가 보여야 함")
	assert_eq(main.session.players.get_child_count(), 1)


func test_single_play_pause_stops_game() -> void:
	main.start_session(Session.Mode.SINGLE)
	await tree.process_frame
	main.open_pause_menu()
	assert_true(tree.paused, "혼자 할 때는 게임이 멈춰야 함")
	assert_true(main.pause_menu.visible)
	main.resume()
	assert_false(tree.paused)
	assert_false(main.pause_menu.visible)


func test_hosting_does_not_pause_game() -> void:
	main.start_session(Session.Mode.HOST)
	await tree.process_frame
	assert_eq(main.session.mode, Session.Mode.HOST)
	main.open_pause_menu()
	assert_false(tree.paused, "코옵 중에는 게임이 멈추지 않아야 함")


func test_leaving_returns_to_menu() -> void:
	main.start_session(Session.Mode.SINGLE)
	await tree.process_frame
	main.leave_session()
	await tree.process_frame
	assert_eq(main.session, null)
	assert_true(main.menu.visible)
	assert_false(main.hud.visible)
	assert_eq(main.get_node_or_null("Session"), null, "세션 노드가 정리되어야 함")


func test_invalid_join_address_shows_error() -> void:
	main.start_session(Session.Mode.CLIENT, "")
	await tree.process_frame
	assert_eq(main.session, null)
	assert_true(main.menu.visible)
	assert_ne(main.menu.status_label.text, "", "오류 메시지가 보여야 함")
