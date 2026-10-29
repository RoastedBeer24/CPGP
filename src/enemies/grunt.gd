class_name Grunt
extends CharacterBody3D
## M2용 단순한 적(경비병). 사거리 안에 보이는 가장 가까운 플레이어를 향해 돌아서 일정 간격으로 쏜다.
## 순찰, 경계 단계, 수색 같은 본격적인 AI는 M3에서 붙인다.
## 판단과 사격 판정은 호스트에서만 하고, 회전과 체력은 동기화된다.

const TEAM := &"enemy"
const EYE_HEIGHT := 1.6
const AIM_HEIGHT := 1.1

@export var max_health := 80.0
@export var armor := 10.0
@export var sight_range := 25.0
@export var fire_interval := 1.2
@export var damage := 8.0
@export var spread_degrees := 3.5
## 초당 회전 각도(라디안)
@export var turn_speed := 3.5
## 플레이어를 처음 본 뒤 첫 발을 쏘기까지의 시간
@export var reaction_time := 0.6
## 0이면 되살아나지 않는다. 시험장에서는 반복 연습을 위해 되살린다.
@export var respawn_delay := 0.0

var target: Player

var _cooldown := 0.0
var _respawn_left := 0.0
var _home: Transform3D

@onready var health: Health = $Health
@onready var body_mesh: Node3D = $Body
@onready var label: Label3D = $HealthLabel
@onready var hitboxes: Array[Hitbox] = [$HeadHitbox, $BodyHitbox]


func _ready() -> void:
	health.max_health = max_health
	health.armor = armor
	health.current = max_health
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)
	_home = global_transform


func _process(_delta: float) -> void:
	label.text = "%d" % ceili(health.current)
	label.visible = health.is_alive() and health.current < max_health


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not health.is_alive():
		_tick_respawn(delta)
		return

	var previous := target
	target = _find_target()
	if target == null:
		return
	if target != previous:
		_cooldown = maxf(_cooldown, reaction_time)

	var to_target := target.global_position - global_position
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	rotation.y = rotate_toward(rotation.y, desired_yaw, turn_speed * delta)

	_cooldown = maxf(_cooldown - delta, 0.0)
	var facing := absf(angle_difference(rotation.y, desired_yaw)) < deg_to_rad(12.0)
	if facing and _cooldown <= 0.0:
		_cooldown = fire_interval
		_shoot(target)


func _find_target() -> Player:
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var space := get_world_3d().direct_space_state
	var best: Player
	var best_distance := sight_range
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player == null or not player.health.is_alive() or player.get_world_3d() != get_world_3d():
			continue
		var aim := player.global_position + Vector3.UP * AIM_HEIGHT
		var distance := eye.distance_to(aim)
		if distance > best_distance:
			continue
		var los := PhysicsRayQueryParameters3D.create(eye, aim, CombatQuery.WORLD_MASK)
		if not space.intersect_ray(los).is_empty():
			continue
		best = player
		best_distance = distance
	return best


func _shoot(player: Player) -> void:
	var origin := global_position + Vector3.UP * EYE_HEIGHT - global_basis.z * 0.4
	var aim := player.global_position + Vector3.UP * AIM_HEIGHT
	var direction := CombatQuery.pellet_directions(aim - origin, 1, spread_degrees, randi())[0]
	var space := get_world_3d().direct_space_state
	var hit := CombatQuery.trace(space, origin, direction, sight_range * 1.5, TEAM)
	var end := origin + direction * sight_range * 1.5
	if hit != null:
		end = hit.position
		if hit.hitbox != null and hit.hitbox.health != null:
			var amount := damage * hit.hitbox.multiplier(1.5)
			hit.hitbox.health.apply_damage(DamageInfo.create(amount, 0, hit.position, &"grunt_rifle", hit.hitbox.part == Hitbox.Part.HEAD))
	_show_shot.rpc(origin, end)


@rpc("authority", "call_local", "unreliable")
func _show_shot(from: Vector3, to: Vector3) -> void:
	Tracer.spawn(self, from, to)


func _tick_respawn(delta: float) -> void:
	if respawn_delay <= 0.0:
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		global_transform = _home
		health.revive()


func _on_died(_info: DamageInfo) -> void:
	target = null
	body_mesh.visible = false
	$CollisionShape3D.set_deferred("disabled", true)
	for hitbox in hitboxes:
		hitbox.set_deferred("collision_layer", 0)
	_respawn_left = respawn_delay


func _on_revived() -> void:
	body_mesh.visible = true
	$CollisionShape3D.set_deferred("disabled", false)
	for hitbox in hitboxes:
		hitbox.set_deferred("collision_layer", Hitbox.LAYER)
	_cooldown = reaction_time
