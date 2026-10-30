extends TestCase
## 사용자 설정: 저장·불러오기, 엔진 적용, 키 바꾸기, 설정 화면, 플레이어 반영을 확인한다.
## 테스트 러너가 설정 파일 경로를 테스트용으로 바꿔 두므로 사용자의 실제 설정은 건드리지 않는다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")


func after_each() -> void:
	GameSettings.reset_to_defaults()
	GameSettings.apply_audio()
	GameSettings.apply_keys()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.path))


func test_save_and_load_round_trip() -> void:
	GameSettings.reset_to_defaults()
	GameSettings.volumes[&"SFX"] = 0.3
	GameSettings.window_mode = GameSettings.WindowMode.BORDERLESS
	GameSettings.window_size = Vector2i(1920, 1080)
	GameSettings.mouse_sensitivity = 1.7
	GameSettings.invert_y = true
	GameSettings.fov = 95.0
	GameSettings.key_overrides[InputActions.JUMP] = KEY_J
	GameSettings.auto_update = false
	GameSettings.visor_on = false
	GameSettings.character_id = &"endministrator_m"
	GameSettings.asset_key = "github_pat_test"
	assert_eq(GameSettings.save(), OK)

	GameSettings.reset_to_defaults()
	GameSettings.load_settings()
	assert_almost_eq(GameSettings.volume(&"SFX"), 0.3, 0.001)
	assert_eq(GameSettings.window_mode, GameSettings.WindowMode.BORDERLESS)
	assert_eq(GameSettings.window_size, Vector2i(1920, 1080))
	assert_almost_eq(GameSettings.mouse_sensitivity, 1.7, 0.001)
	assert_true(GameSettings.invert_y)
	assert_almost_eq(GameSettings.fov, 95.0, 0.001)
	assert_eq(GameSettings.key_overrides.get(InputActions.JUMP), KEY_J)
	assert_false(GameSettings.auto_update)
	assert_false(GameSettings.visor_on, "바이저를 벗은 채로 저장")
	assert_eq(GameSettings.character_id, &"endministrator_m", "고른 캐릭터")
	assert_eq(GameSettings.asset_key, "github_pat_test")


func test_save_keeps_other_sections() -> void:
	var config := ConfigFile.new()
	config.set_value("network", "last_address", "192.168.0.12")
	config.save(GameSettings.path)
	GameSettings.save()
	config = ConfigFile.new()
	config.load(GameSettings.path)
	assert_eq(config.get_value("network", "last_address", ""), "192.168.0.12", "마지막 접속 주소가 남아 있음")


func test_out_of_range_values_are_clamped() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "Master", 5.0)
	config.set_value("controls", "fov", 300.0)
	config.set_value("display", "window_mode", 99)
	config.set_value("display", "render_scale", 0.01)
	config.save(GameSettings.path)
	GameSettings.load_settings()
	assert_almost_eq(GameSettings.volume(&"Master"), 1.0, 0.001)
	assert_almost_eq(GameSettings.fov, 100.0, 0.001)
	assert_eq(GameSettings.window_mode, GameSettings.WindowMode.FULLSCREEN)
	assert_almost_eq(GameSettings.render_scale, 0.5, 0.001)


func test_missing_file_gives_defaults() -> void:
	GameSettings.fov = 100.0
	GameSettings.load_settings()
	assert_almost_eq(GameSettings.fov, 70.0, 0.001)
	assert_eq(GameSettings.character_id, &"endministrator_f")


func test_volume_is_applied_to_audio_buses() -> void:
	GameSettings.reset_to_defaults()
	GameSettings.volumes[&"Music"] = 0.5
	GameSettings.volumes[&"SFX"] = 0.0
	GameSettings.apply_audio()
	var music := AudioServer.get_bus_index(&"Music")
	var sfx := AudioServer.get_bus_index(&"SFX")
	assert_true(music > 0 and sfx > 0, "소리 버스가 있어야 함")
	assert_almost_eq(AudioServer.get_bus_volume_db(music), linear_to_db(0.5), 0.01)
	assert_true(AudioServer.is_bus_mute(sfx), "0이면 음소거")


func test_look_delta_uses_sensitivity_and_invert() -> void:
	GameSettings.mouse_sensitivity = 2.0
	var normal := GameSettings.look_delta(Vector2(10, 10))
	assert_almost_eq(normal.x, 10 * GameSettings.BASE_MOUSE_SENSITIVITY * 2.0, 0.00001)
	GameSettings.invert_y = true
	var inverted := GameSettings.look_delta(Vector2(10, 10))
	assert_almost_eq(inverted.y, -normal.y, 0.00001)
	assert_almost_eq(inverted.x, normal.x, 0.00001)


func test_rebinding_replaces_keys_and_reset_restores() -> void:
	GameSettings.key_overrides[InputActions.SKILL] = KEY_E
	GameSettings.apply_keys()
	assert_true(_action_has_key(InputActions.SKILL, KEY_E))
	assert_false(_action_has_key(InputActions.SKILL, KEY_1), "원래 키는 빠짐")
	GameSettings.reset_to_defaults()
	GameSettings.apply_keys()
	assert_true(_action_has_key(InputActions.SKILL, KEY_1))
	assert_false(_action_has_key(InputActions.SKILL, KEY_E))


func test_rebinding_keeps_mouse_buttons() -> void:
	GameSettings.apply_keys()
	var mouse_events := 0
	for event in InputMap.action_get_events(InputActions.ATTACK):
		if event is InputEventMouseButton:
			mouse_events += 1
	assert_eq(mouse_events, 1, "공격은 마우스 왼쪽 그대로")
	assert_true(_action_has_key(InputActions.DODGE, KEY_SHIFT), "회피는 Shift와")
	var right_click := false
	for event in InputMap.action_get_events(InputActions.DODGE):
		var mouse := event as InputEventMouseButton
		right_click = right_click or (mouse != null and mouse.button_index == MOUSE_BUTTON_RIGHT)
	assert_true(right_click, "마우스 오른쪽 (엔드필드 PC판 기본값)")


func test_settings_menu_rebinds_and_swaps_conflicting_key() -> void:
	GameSettings.apply_keys()
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	menu.open()
	await tree.process_frame
	# 점프를 W로 바꾸면, W를 쓰던 "앞으로"는 점프의 원래 키(Space)를 받는다.
	menu._start_rebind(InputActions.JUMP, menu._key_buttons[InputActions.JUMP])
	menu._input(_key_press(KEY_W))
	assert_true(_action_has_key(InputActions.JUMP, KEY_W))
	assert_true(_action_has_key(InputActions.MOVE_FORWARD, KEY_SPACE), "겹친 키는 맞바꿈")
	assert_false(_action_has_key(InputActions.MOVE_FORWARD, KEY_W))


func test_settings_menu_escape_cancels_rebind_then_closes_and_saves() -> void:
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	var closed: Array[bool] = []
	menu.closed.connect(func() -> void: closed.append(true))
	menu.open()
	await tree.process_frame
	menu._start_rebind(InputActions.JUMP, menu._key_buttons[InputActions.JUMP])
	menu._input(_key_press(KEY_ESCAPE))
	assert_true(menu.visible, "첫 Esc는 키 바꾸기만 취소")
	assert_false(GameSettings.key_overrides.has(InputActions.JUMP))
	menu._input(_key_press(KEY_ESCAPE))
	assert_false(menu.visible, "두 번째 Esc로 닫힘")
	assert_eq(closed.size(), 1)
	assert_true(FileAccess.file_exists(GameSettings.path), "닫을 때 저장")


func test_settings_menu_has_all_tabs() -> void:
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	menu.open()
	await tree.process_frame
	var titles: Array[String] = []
	for i in menu._tabs.get_tab_count():
		titles.append(menu._tabs.get_tab_title(i))
	assert_eq(titles, ["소리", "화면", "그래픽", "조작", "게임"] as Array[String])


func test_player_uses_fov() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	add_child_autofree(floor_body)
	GameSettings.fov = 100.0
	var player := PLAYER_SCENE.instantiate() as Player
	player.use_device_input = false
	var intent := PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	for i in 60:
		await tree.physics_frame
	assert_almost_eq(player.camera.fov, 100.0, 0.5, "설정한 시야각")



func test_mouse_buttons_can_be_bound_and_labelled() -> void:
	GameSettings.key_overrides[InputActions.INTERACT] = -MOUSE_BUTTON_MIDDLE
	GameSettings.key_overrides[InputActions.ATTACK] = KEY_ENTER
	GameSettings.apply_keys()
	var mouse_bound := false
	for event in InputMap.action_get_events(InputActions.INTERACT):
		var mouse := event as InputEventMouseButton
		mouse_bound = mouse_bound or (mouse != null and mouse.button_index == MOUSE_BUTTON_MIDDLE)
	assert_true(mouse_bound, "상호작용을 마우스 가운데 버튼에")
	assert_eq(GameSettings.key_label(InputActions.INTERACT), "마우스 가운데")
	assert_true(_action_has_key(InputActions.ATTACK, KEY_ENTER), "공격을 키보드 키에")
	assert_eq(GameSettings.key_label(InputActions.ATTACK), GameSettings.code_label(KEY_ENTER))
	GameSettings.reset_to_defaults()
	GameSettings.apply_keys()
	assert_eq(GameSettings.key_label(InputActions.ATTACK), "마우스 왼쪽", "기본값으로 돌아오면 마우스 왼쪽")


func test_settings_menu_binds_mouse_button() -> void:
	GameSettings.apply_keys()
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	menu.open()
	await tree.process_frame
	menu._start_rebind(InputActions.ULTIMATE, menu._key_buttons[InputActions.ULTIMATE])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_XBUTTON1
	click.pressed = true
	menu._input(click)
	assert_eq(GameSettings.key_overrides.get(InputActions.ULTIMATE), -MOUSE_BUTTON_XBUTTON1)


func test_legacy_settings_are_copied_once() -> void:
	# 이름을 바꾸기 전(CyberUniverse)의 설정 파일은 새 설정이 없을 때 한 번 가져온다(에셋 키를 다시 넣지 않게).
	var legacy := ProjectSettings.globalize_path("user://test_legacy_settings.cfg")
	var target := "user://test_copied_settings.cfg"
	var config := ConfigFile.new()
	config.set_value("game", "asset_key", "github_pat_legacy")
	config.save(legacy)
	assert_true(GameSettings.copy_legacy_settings(legacy, target), "새 설정이 없으면 가져온다")
	var copied := ConfigFile.new()
	assert_eq(copied.load(target), OK)
	assert_eq(copied.get_value("game", "asset_key", ""), "github_pat_legacy")
	assert_false(GameSettings.copy_legacy_settings(legacy, target), "이미 있으면 덮어쓰지 않는다")
	DirAccess.remove_absolute(legacy)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(target))


func _key_press(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	return event


func _action_has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null and key.physical_keycode == keycode:
			return true
	return false
