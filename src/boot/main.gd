extends Node
## 앱의 뿌리. 메인 메뉴와 게임 세션 사이를 오가고, 일시정지 메뉴와 마우스 고정을 맡는다.
##
## 명령줄로 메뉴를 건너뛸 수 있다 (개발·테스트용):
##   godot --path . -- --single
##   godot --path . -- --host
##   godot --path . -- --join=192.168.0.12

const SESSION_SCENE := preload("res://src/net/session.tscn")

var session: Session

@onready var menu: MainMenu = $MainMenu
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var hud: Hud = $Hud


func _ready() -> void:
	# 일시정지 중에도 Esc를 받아야 하므로 앱 뿌리는 항상 동작한다. 세션만 멈춘다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu.single_requested.connect(start_session.bind(Session.Mode.SINGLE))
	menu.host_requested.connect(start_session.bind(Session.Mode.HOST))
	menu.join_requested.connect(func(address: String) -> void: start_session(Session.Mode.CLIENT, address))
	menu.quit_requested.connect(get_tree().quit)
	pause_menu.resume_requested.connect(resume)
	pause_menu.leave_requested.connect(leave_session)
	hud.hide()
	menu.open()
	_apply_command_line()


func _unhandled_input(event: InputEvent) -> void:
	if session == null or not event.is_action_pressed(InputActions.PAUSE):
		return
	if pause_menu.visible:
		resume()
	elif session.mode != Session.Mode.NONE:
		open_pause_menu()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# 창이 포커스를 잃으면 마우스를 풀어 준다.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and session != null and not pause_menu.visible:
		open_pause_menu()


func start_session(mode: Session.Mode, address: String = "") -> void:
	if session != null:
		return
	session = SESSION_SCENE.instantiate() as Session
	session.name = "Session"
	session.process_mode = Node.PROCESS_MODE_PAUSABLE
	session.started.connect(_on_session_started)
	session.ended.connect(_on_session_ended)
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


func resume() -> void:
	pause_menu.close()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func leave_session() -> void:
	_close_session("")


func _on_session_started() -> void:
	menu.hide()
	hud.session = session
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


func _apply_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--single":
			start_session(Session.Mode.SINGLE)
		elif arg == "--host":
			start_session(Session.Mode.HOST)
		elif arg.begins_with("--join="):
			start_session(Session.Mode.CLIENT, arg.trim_prefix("--join="))
