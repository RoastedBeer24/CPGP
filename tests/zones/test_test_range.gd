extends TestCase
## 그레이박스 시험장에서 주요 경로를 실제로 오를 수 있는지 확인한다.

const ZONE_SCENE := preload("res://src/zones/test_range/test_range.tscn")
const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ROOF_HEIGHT := 3.0

var zone: Node3D
var player: Player
var intent: PlayerIntent


func before_each() -> void:
	zone = ZONE_SCENE.instantiate()
	add_child_autofree(zone)
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)


func test_has_three_spawn_points() -> void:
	assert_true(zone.get_node("SpawnPoints").get_child_count() >= 3)


func test_stairs_lead_to_rooftop() -> void:
	await _walk_from(Vector3(-14, 0.05, 7.5), 180)
	assert_almost_eq(player.global_position.y, ROOF_HEIGHT, 0.1)


func test_ramp_leads_to_rooftop() -> void:
	await _walk_from(Vector3(14, 0.05, 7.5), 180)
	assert_almost_eq(player.global_position.y, ROOF_HEIGHT, 0.1)


func test_tallest_ledge_is_climbable() -> void:
	player.global_position = Vector3(8, 0.05, -3.5)
	await _frames(5)
	intent.move = Vector2(0, 1)
	intent.jump_held = true
	intent.jump_pressed = true
	for i in 120:
		await tree.physics_frame
		if player.state == Player.State.MANTLE:
			intent.move = Vector2.ZERO
	await _frames(10)
	assert_almost_eq(player.global_position.y, 2.5, 0.1)


func _walk_from(start: Vector3, frames: int) -> void:
	player.global_position = start
	await _frames(5)
	intent.move = Vector2(0, 1)
	await _frames(frames)


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
