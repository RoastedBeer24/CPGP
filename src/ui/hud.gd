class_name Hud
extends CanvasLayer
## 게임 화면 위의 정보. 지금은 조준점과 F3 디버그 표시(이동 상태·속도)만 있다.

var session: Session

@onready var debug_label: Label = %DebugLabel


func _ready() -> void:
	debug_label.hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(InputActions.DEBUG_OVERLAY):
		debug_label.visible = not debug_label.visible


func _process(_delta: float) -> void:
	if not debug_label.visible or session == null:
		return
	var player := session.get_local_player()
	if player == null:
		return
	debug_label.text = "상태 %s | 속도 %.1f m/s | 웅크림 %s | FPS %d | 인원 %d" % [
		Player.State.keys()[player.state],
		player.horizontal_speed(),
		"예" if player.crouched else "아니오",
		Engine.get_frames_per_second(),
		session.players.get_child_count(),
	]
