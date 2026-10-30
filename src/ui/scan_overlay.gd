class_name ScanOverlay
extends Control
## 스캔 모드(Tab) 화면: 해킹 대상마다 표식을 띄우고, 조준점에 있는 대상의 정보와 퀵핵 목록을 보여 준다.
## 퀵핵은 1~3 키로 올린다. RAM이 모자란 퀵핵은 흐리게 보인다.

const MARKER_COLOR := Color(0.3, 0.95, 1, 0.8)
const FOCUS_COLOR := Color(1, 0.85, 0.2)
const TINT := Color(0.1, 0.6, 0.8, 0.08)

var player: Player

var _info: Label


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info = Label.new()
	_info.position = Vector2(0, 0)
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	add_child(_info)


func _process(_delta: float) -> void:
	var active := player != null and is_instance_valid(player) and player.cyberdeck.scanning
	visible = active
	if not active:
		return
	_update_info()
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	draw_rect(Rect2(Vector2.ZERO, size), TINT)
	var camera := player.camera
	for node in get_tree().get_nodes_in_group(Hackable.GROUP):
		var hackable := node as Hackable
		if hackable == null or hackable.get_viewport().find_world_3d() != player.get_world_3d() or not hackable.is_available():
			continue
		var position := hackable.global_position
		if camera.is_position_behind(position) or position.distance_to(camera.global_position) > Cyberdeck.HACK_RANGE:
			continue
		var point := camera.unproject_position(position)
		var focused := hackable == player.cyberdeck.focus
		var radius := 14.0 if focused else 9.0
		var color := FOCUS_COLOR if focused else MARKER_COLOR
		# 마름모 표식
		var diamond := PackedVector2Array([
			point + Vector2(0, -radius), point + Vector2(radius, 0), point + Vector2(0, radius), point + Vector2(-radius, 0), point + Vector2(0, -radius),
		])
		draw_polyline(diamond, color, 3.0 if focused else 2.0)


func _update_info() -> void:
	var focus := player.cyberdeck.focus
	if focus == null:
		_info.text = "스캔 중 — 대상을 조준점에 맞추세요\nRAM %d / %d" % [floori(player.cyberdeck.ram), int(player.cyberdeck.max_ram)]
		_info.position = size * 0.5 + Vector2(40, -20)
		return
	var lines := focus.scan_lines()
	lines.append("")
	for i in focus.quickhacks.size():
		var hack := focus.quickhacks[i]
		var short := "" if player.cyberdeck.ram >= hack.ram_cost else "  (RAM 부족)"
		lines.append("%d  %s  RAM %d%s" % [i + 1, hack.display_name, hack.ram_cost, short])
	lines.append("")
	lines.append("RAM %d / %d" % [floori(player.cyberdeck.ram), int(player.cyberdeck.max_ram)])
	_info.text = "\n".join(lines)
	var point := player.camera.unproject_position(focus.global_position)
	_info.position = point + Vector2(28, -24)
