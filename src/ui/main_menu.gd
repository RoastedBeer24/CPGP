class_name MainMenu
extends Control
## 메인 메뉴. 혼자 하기, 방 만들기, 참여하기, 종료.
## 마지막으로 입력한 참여 주소를 기억한다.

signal single_requested
signal host_requested
signal join_requested(address: String)
signal quit_requested

const SETTINGS_PATH := "user://settings.cfg"

@onready var single_button: Button = %SingleButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var quit_button: Button = %QuitButton
@onready var address_edit: LineEdit = %AddressEdit
@onready var status_label: Label = %StatusLabel
@onready var version_label: Label = %VersionLabel


func _ready() -> void:
	single_button.pressed.connect(single_requested.emit)
	host_button.pressed.connect(host_requested.emit)
	join_button.pressed.connect(_on_join_pressed)
	address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	quit_button.pressed.connect(quit_requested.emit)
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	address_edit.text = _load_last_address()


## 메뉴를 다시 보여 준다. 메시지가 있으면 함께 표시한다(연결 끊김 사유 등).
func open(message: String = "") -> void:
	show()
	set_busy(false)
	status_label.text = message
	single_button.grab_focus()


func set_status(message: String) -> void:
	status_label.text = message


## 연결 중에는 버튼을 잠가 중복 요청을 막는다.
func set_busy(busy: bool) -> void:
	for button: Button in [single_button, host_button, join_button]:
		button.disabled = busy
	address_edit.editable = not busy


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "참여할 호스트의 주소를 입력하세요."
		return
	_save_last_address(address)
	join_requested.emit(address)


func _load_last_address() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return ""
	return str(config.get_value("network", "last_address", ""))


func _save_last_address(address: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("network", "last_address", address)
	config.save(SETTINGS_PATH)
