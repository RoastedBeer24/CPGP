class_name PauseMenu
extends CanvasLayer
## 게임 중 Esc로 여는 메뉴. 혼자 할 때는 게임을 멈추고, 코옵 중에는 멈추지 않는다.
## 방을 만든 경우 다른 사람이 입력할 주소를 보여 준다.

signal resume_requested
signal leave_requested
signal settings_requested

@onready var title_label: Label = %TitleLabel
@onready var info_label: Label = %InfoLabel
@onready var resume_button: Button = %ResumeButton
@onready var leave_button: Button = %LeaveButton
@onready var settings_button: Button = %SettingsButton


func _ready() -> void:
	hide()
	resume_button.pressed.connect(resume_requested.emit)
	leave_button.pressed.connect(leave_requested.emit)
	settings_button.pressed.connect(settings_requested.emit)


func open(session: Session) -> void:
	title_label.text = "일시정지" if session.can_pause() else "메뉴 (코옵 중에는 게임이 멈추지 않습니다)"
	info_label.text = _describe(session)
	show()
	resume_button.grab_focus()


func close() -> void:
	hide()


func _describe(session: Session) -> String:
	match session.mode:
		Session.Mode.HOST:
			var addresses := Session.lan_addresses()
			var shown := ", ".join(addresses) if not addresses.is_empty() else "(주소를 찾지 못함)"
			return "방 주소: %s\n참가 인원: %d / %d" % [shown, session.players.get_child_count(), Session.MAX_PLAYERS]
		Session.Mode.CLIENT:
			return "참가 인원: %d / %d" % [session.players.get_child_count(), Session.MAX_PLAYERS]
		_:
			return ""
