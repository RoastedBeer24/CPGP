class_name HudOverlay
extends Control
## 3D 세상 위에 그리는 HUD: 적 머리 위의 체력·경직 게이지, 원석 결정 표시, 경직된 적의 처형 안내, 대상 고정 표시.

const BAR_SIZE := Vector2(90, 7)
const STAGGER_HEIGHT := 4.0
const ENEMY_HP_COLOR := Color(0.95, 0.32, 0.26)
const STAGGER_COLOR := Color(1.0, 0.85, 0.25)
const CRYSTAL_COLOR := Color(1.0, 0.6, 0.15)
const LOCK_COLOR := Color(1.0, 0.9, 0.4)
## 이보다 먼 적은 막대를 그리지 않는다(m).
const DRAW_RANGE := 35.0

var hud: Hud


func _draw() -> void:
	var player := hud.local_player() if hud != null else null
	if player == null or not player.is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var font := get_theme_default_font()
	for enemy in Roster.enemies(player):
		if not enemy.is_alive():
			continue
		var top := enemy.top()
		if camera.is_position_behind(top) or top.distance_to(camera.global_position) > DRAW_RANGE:
			continue
		var point := camera.unproject_position(top)
		var corner := point - Vector2(BAR_SIZE.x * 0.5, 0)
		draw_rect(Rect2(corner - Vector2(1, 1), BAR_SIZE + Vector2(2, STAGGER_HEIGHT + 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(corner, Vector2(BAR_SIZE.x * enemy.health.ratio(), BAR_SIZE.y)), ENEMY_HP_COLOR)
		var stagger_ratio := 1.0 if enemy.is_staggered() else enemy.stagger / maxf(enemy.data.stagger_max, 1.0)
		draw_rect(Rect2(corner + Vector2(0, BAR_SIZE.y + 2), Vector2(BAR_SIZE.x * stagger_ratio, STAGGER_HEIGHT)), STAGGER_COLOR)
		if enemy.has_crystal():
			var diamond := PackedVector2Array([
				corner + Vector2(-10, 5), corner + Vector2(-5, -1), corner + Vector2(0, 5), corner + Vector2(-5, 11)])
			draw_colored_polygon(diamond, CRYSTAL_COLOR)
		if enemy.is_staggered():
			var close := enemy.global_position.distance_to(player.global_position) - enemy.radius() <= player.config.finisher_range
			var text := "처형 가능 [왼쪽 클릭]" if close else "경직"
			draw_string(font, point + Vector2(-70, -10), text, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, STAGGER_COLOR)
	var target := player.lock_target
	if target != null and is_instance_valid(target) and target.is_alive():
		var center := target.global_position + Vector3.UP * target.data.height * 0.55
		if not camera.is_position_behind(center):
			var at := camera.unproject_position(center)
			draw_arc(at, 22.0, 0.0, TAU, 32, LOCK_COLOR, 2.0)
			draw_circle(at, 3.0, LOCK_COLOR)
