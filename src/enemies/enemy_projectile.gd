class_name EnemyProjectile
extends Node3D
## 원거리 적이 쏜 탄. 모든 피어가 같은 출발점과 속도로 띄우고, 맞았는지는 호스트(authoritative)만 판정한다.
## 다른 피어의 탄은 보여 주기만 하고, 벽이나 플레이어에 닿으면 사라진다.

const LIFETIME := 3.0
## 플레이어 몸(가슴 높이)에 닿았다고 보는 거리(m)
const HIT_RADIUS := 0.55

var velocity := Vector3.ZERO
var attack: EnemyAttackData
var source: Enemy
var authoritative := false

var _age := 0.0
var _dodged: Array[Player] = []


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.45, 0.2)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.2)
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.25)
	light.light_energy = 1.2
	light.omni_range = 2.5
	add_child(light)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var next := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, CombatQuery.WORLD_MASK)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		queue_free()
		return
	global_position = next
	for player in Roster.players(self):
		if not player.is_alive() or _dodged.has(player):
			continue
		if global_position.distance_to(player.global_position + Vector3.UP * 1.0) > HIT_RADIUS:
			continue
		if player.invulnerable:
			# 회피로 피했다. 지나가게 둔다(완벽한 회피는 호스트가 한 번만 알린다).
			_dodged.append(player)
			if authoritative and player.state == Player.State.DODGE:
				player.notify_perfect_dodge()
			continue
		if authoritative and attack != null:
			var info := DamageInfo.create(attack.damage, 0, global_position, attack.id)
			if player.health.apply_damage(info) > 0.0:
				var from := source.global_position if source != null and is_instance_valid(source) else global_position - velocity
				player.notify_hit(attack.heavy, from, Enemy.ENERGY_ON_HURT)
		queue_free()
		return
