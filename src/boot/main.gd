extends Node
## 앱의 뿌리. 메인 메뉴와 게임 세션 사이를 오가고, 일시정지 메뉴와 마우스 고정을 맡는다.
##
## 명령줄로 메뉴를 건너뛸 수 있다 (개발·테스트용):
##   godot --path . -- --single
##   godot --path . -- --host
##   godot --path . -- --join=192.168.0.12
##   godot --path . -- --single --character=endministrator_m   # 캐릭터 고르기
##   godot --path . -- --single --autoplay        # 내 플레이어가 저절로 싸운다 (화면 확인용, AutoPilot)
##   godot --path . -- --single --autoplay=combo  # 로비에서 제자리 공격·배틀 스킬만 되풀이 (이펙트 확인용)
##   godot --path . -- --single --autoplay=run    # 로비에서 원을 그리며 달리기·질주, 옆에서 비춤 (옷자락 확인용)
##   godot --path . -- --single --autoplay=plunge # 로비에서 점프 → 낙하 공격만 되풀이 (낙하 공격 확인용)
##   godot --path . -- --single --autoplay=finisher # 로비에서 앞의 적을 경직시켜 처형만 되풀이 (처형 확인용)
##   godot --path . -- --single --character-screen   # 로비에서 캐릭터 화면을 연 채로 시작 (화면 확인용)
##   godot --path . -- --single --character-weapon   # 캐릭터 화면에서 무기 보기를 켠 채로 시작 (화면 확인용)
##   --capture=700,720,740 --capture-dir=폴더    # 그 프레임들의 화면을 PNG로 저장하고 끝냄 (화면 확인용, FrameCapture)
##   --first-person / --free-face                # 1인칭으로, 또는 자유 시점으로 얼굴 앞에서 시작 (화면 확인용, 저장 안 함)
##   --no-update                                 # 자동 업데이트를 하지 않음
##   --update-url=http://127.0.0.1:8000/latest   # 업데이트 확인 주소 바꾸기 (시험용)
##
## 내보낸 Windows 게임은 켤 때 GitHub 릴리스에서 새 버전을 찾아 받는다(Updater).
## 메뉴에 있으면 바로 설치하고 다시 시작하고, 게임 중이면 게임을 끝낼 때 설치한다.
## 캐릭터 모델 같은 에셋은 비공개 에셋 저장소에서 따로 받는다(AssetUpdater, 설정의 에셋 키가 있을 때).

const SESSION_SCENE := preload("res://src/net/session.tscn")

var session: Session
## 명령줄로 고른 캐릭터 (--character=이름). 비어 있으면 설정의 캐릭터.
var command_line_character := &""
## true면 내 플레이어를 자동 조종한다 (명령줄 --autoplay).
var autoplay := false
## 자동 업데이트. 업데이트할 수 없는 실행 환경이면 null.
var updater: Updater
## 에셋(캐릭터 모델) 자동 업데이트. 업데이트할 수 없는 실행 환경이면 null.
var asset_updater: AssetUpdater
var settings_menu: SettingsMenu

@onready var menu: MainMenu = $MainMenu
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var hud: Hud = $Hud


func _ready() -> void:
	# 일시정지 중에도 Esc를 받아야 하므로 앱 뿌리는 항상 동작한다. 세션만 멈춘다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu.single_requested.connect(start_session.bind(Session.Mode.SINGLE))
	menu.host_requested.connect(start_session.bind(Session.Mode.HOST))
	menu.join_requested.connect(func(address: String) -> void: start_session(Session.Mode.CLIENT, address))
	menu.quit_requested.connect(quit_game)
	menu.settings_requested.connect(open_settings)
	pause_menu.settings_requested.connect(open_settings)
	get_window().title = "크로스필드"
	# 사용자 설정을 가장 먼저 적용한다 (창 크기, 소리, 키). 이름을 바꾸기 전의 설정이 있으면 한 번 가져온다.
	if GameSettings.path == GameSettings.DEFAULT_PATH:
		GameSettings.copy_legacy_settings(GameSettings.legacy_path(), GameSettings.path)
	GameSettings.load_settings()
	GameSettings.manage_window = not is_recording()
	GameSettings.apply_all(get_tree().root)
	if is_recording():
		_hide_window()
	settings_menu = SettingsMenu.new()
	settings_menu.name = "SettingsMenu"
	settings_menu.closed.connect(_on_settings_closed)
	add_child(settings_menu)
	pause_menu.resume_requested.connect(resume)
	pause_menu.leave_requested.connect(leave_session)
	hud.hide()
	menu.open()
	_start_updater()
	_apply_command_line()


func _unhandled_input(event: InputEvent) -> void:
	if session == null or settings_menu.visible or not event.is_action_pressed(InputActions.PAUSE):
		return
	if pause_menu.visible:
		resume()
	elif session.mode != Session.Mode.NONE:
		open_pause_menu()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# 창이 포커스를 잃으면 마우스를 풀어 준다.
	# 자동 조종과 화면 확인(--write-movie, --capture)은 창이 포커스를 잃어도 멈추지 않는다.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and session != null and not pause_menu.visible and not autoplay and not is_recording():
		open_pause_menu()
	# 창을 닫을 때 받아 둔 업데이트가 있으면 설치한다.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_install_pending_update(false)


## 게임을 끝낸다. 받아 둔 업데이트가 있으면 설치하고 끝낸다.
func quit_game() -> void:
	_install_pending_update(false)
	get_tree().quit()


func start_session(mode: Session.Mode, address: String = "") -> void:
	if session != null:
		return
	session = SESSION_SCENE.instantiate() as Session
	session.name = "Session"
	session.process_mode = Node.PROCESS_MODE_PAUSABLE
	session.started.connect(_on_session_started)
	session.ended.connect(_on_session_ended)
	session.character_id = command_line_character if command_line_character != &"" else GameSettings.character_id
	session.player_spawned.connect(_on_player_spawned)
	add_child(session)

	var error := OK
	match mode:
		Session.Mode.SINGLE:
			error = session.start_single()
		Session.Mode.HOST:
			error = session.host()
		Session.Mode.CLIENT:
			menu.set_busy(true)
			menu.set_status("%s 에 연결하는 중..." % address)
			error = session.join(address)

	if error != OK:
		var reason := "방을 만들지 못했습니다. 포트 %d이 이미 쓰이고 있을 수 있습니다." % Session.DEFAULT_PORT
		if mode == Session.Mode.CLIENT:
			reason = "주소가 올바르지 않습니다: %s" % address
		_close_session(reason)


func open_pause_menu() -> void:
	pause_menu.open(session)
	get_tree().paused = session.can_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 설정 화면을 연다. 메인 메뉴나 일시정지 메뉴 위에 겹쳐 뜬다.
func open_settings() -> void:
	settings_menu.open()


func _on_settings_closed() -> void:
	# 설정에서 바이저를 바꿨으면 지금 내 캐릭터에도 바로 입힌다.
	var mine := session.get_local_player() if session != null else null
	if mine != null and mine.visor_on != GameSettings.visor_on:
		mine.set_visor(GameSettings.visor_on)
	if pause_menu.visible:
		pause_menu.resume_button.grab_focus()
	elif menu.visible:
		menu.settings_button.grab_focus()


func resume() -> void:
	pause_menu.close()
	get_tree().paused = false
	MouseLock.capture()


func leave_session() -> void:
	_close_session("")


func _on_session_started() -> void:
	menu.hide()
	hud.session = session
	hud.show()
	MouseLock.capture()


func _on_player_spawned(player: Player) -> void:
	var args := OS.get_cmdline_user_args()
	if (args.has("--character-screen") or args.has("--character-weapon")) and player.is_multiplayer_authority():
		hud.character_screen.session = session
		hud.character_screen.open_screen.call_deferred()
		if args.has("--character-weapon"):
			hud.character_screen.toggle_weapon.call_deferred()
	if args.has("--first-person") and player.is_multiplayer_authority():
		player.set_camera_mode(Player.CameraMode.FIRST_PERSON, false)
	if args.has("--free-face") and player.is_multiplayer_authority():
		# 자유 시점으로 얼굴 앞 0.25m에서 본다.
		player.set_camera_mode(Player.CameraMode.FREE, false)
		player.camera_distance = 0.25
		player.camera_yaw = player.rotation.y + PI
		player.camera_pitch = 0.0
	if autoplay and player.is_multiplayer_authority():
		var pilot := AutoPilot.new()
		pilot.name = "AutoPilot"
		pilot.player = player
		pilot.combo_only = OS.get_cmdline_user_args().has("--autoplay=combo")
		pilot.run_only = OS.get_cmdline_user_args().has("--autoplay=run")
		pilot.plunge_only = OS.get_cmdline_user_args().has("--autoplay=plunge")
		pilot.finisher_only = OS.get_cmdline_user_args().has("--autoplay=finisher")
		player.add_child(pilot)


func _on_session_ended(reason: String) -> void:
	_close_session(reason)


func _close_session(message: String) -> void:
	if session != null:
		session.leave()
		session.queue_free()
		session = null
	get_tree().paused = false
	pause_menu.close()
	hud.session = null
	hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.open(message)
	# 게임 중에 받아 둔 업데이트는 메뉴로 돌아왔을 때 설치한다.
	if updater != null and updater.state == Updater.State.READY:
		_on_update_ready()


func _start_updater() -> void:
	var args := OS.get_cmdline_user_args()
	var custom_url := ""
	for arg in args:
		if arg.begins_with("--update-url="):
			custom_url = arg.trim_prefix("--update-url=")
	if args.has("--no-update") or not GameSettings.auto_update or not Updater.can_self_update():
		return
	updater = Updater.new()
	updater.name = "Updater"
	if not custom_url.is_empty():
		updater.release_url = custom_url
	add_child(updater)
	updater.status_changed.connect(menu.set_update_status)
	updater.update_ready.connect(_on_update_ready)
	updater.check()
	asset_updater = AssetUpdater.new()
	asset_updater.name = "AssetUpdater"
	asset_updater.key = GameSettings.asset_key
	add_child(asset_updater)
	asset_updater.status_changed.connect(menu.set_asset_status)
	asset_updater.check()


func _on_update_ready() -> void:
	if session != null:
		menu.set_update_status("새 버전이 준비되었습니다. 메뉴로 돌아오거나 게임을 끝내면 설치됩니다.")
		return
	menu.set_update_status("새 버전을 설치하고 다시 시작합니다...")
	await get_tree().create_timer(1.5).timeout
	# 기다리는 사이에 게임을 시작했으면 나중에 설치한다.
	if session != null:
		return
	if updater.apply(true) == OK:
		get_tree().quit()
	else:
		menu.set_update_status("업데이트를 설치하지 못했습니다. 다음에 켤 때 다시 시도합니다.")


func _install_pending_update(relaunch: bool) -> void:
	if updater != null and updater.state == Updater.State.READY:
		updater.apply(relaunch)


## 화면 확인용으로 도는 중인지 (tools/screenshot.sh의 --write-movie, tools/capture.sh의 --capture)
func is_recording() -> bool:
	if not Engine.get_write_movie_path().is_empty():
		return true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return true
	return false


## 화면 확인용으로 켰을 때: PC를 쓰고 있는 사람을 방해하지 않게 창을 화면 밖으로 옮긴다. tools/capture.sh는 창을
## 1x1 크기로, 포커스를 뺏지 않게(override.cfg) 띄우므로 여기서 화면 밖으로 옮긴 뒤 찍을 크기로 키운다.
## 창을 처음부터 화면 밖에 띄우는 설정은 Godot가 화면 안으로 되돌려서 쓸 수 없었다.
func _hide_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_position(Vector2i(-20000, -20000))
	if Engine.get_write_movie_path().is_empty():
		DisplayServer.window_set_size(Vector2i(1280, 720))


func _apply_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	autoplay = args.has("--autoplay") or args.has("--autoplay=combo") or args.has("--autoplay=run") or args.has("--autoplay=plunge") or args.has("--autoplay=finisher")
	var capture := FrameCapture.from_command_line(args)
	if capture != null:
		capture.name = "FrameCapture"
		add_child(capture)
	# 화면 확인 중에는 마우스를 가두지 않는다(창이 화면 밖에 있어 커서가 끌려간다).
	MouseLock.disabled = is_recording()
	for arg in args:
		if arg.begins_with("--character="):
			command_line_character = StringName(arg.trim_prefix("--character="))
	for arg in args:
		if arg == "--single":
			start_session(Session.Mode.SINGLE)
		elif arg == "--host":
			start_session(Session.Mode.HOST)
		elif arg.begins_with("--join="):
			start_session(Session.Mode.CLIENT, arg.trim_prefix("--join="))
