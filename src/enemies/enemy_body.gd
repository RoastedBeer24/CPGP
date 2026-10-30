class_name EnemyBody
extends Node3D
## 적의 보이는 몸. 동기화된 상태(Enemy.state, attack_count, hurt_count, crystal_left)를 보고 모든 피어가 같은 모습을 그린다.
##   - 모델 파일이 있으면 모델의 동작을 튼다(EnemyData.clips). 없으면 단순한 도형 몸을 코드로 움직인다.
##   - 공격 예고: 맞을 자리(부채꼴·원·직선)가 땅에 깔리고, 맞는 순간까지 안쪽이 차오른다. 눈이 밝아진다.
##   - 맞으면 하얗게 번쩍이고, 경직되면 옆으로 기울어 머리 위에 노란 고리가 돈다.
##   - 원석 결정이 붙으면 몸 둘레에 주황빛 결정이 돋는다.

const TELEGRAPH_COLOR := Color(1.0, 0.35, 0.15)
const TELEGRAPH_HEIGHT := 0.06
const RANGED_TELEGRAPH_LENGTH := 14.0
const CRYSTAL_COLOR := Color(1.0, 0.6, 0.15)
const FLASH_TIME := 0.12

var enemy: Enemy
var has_model := false

var _rig: Node3D
var _materials: Array[StandardMaterial3D] = []
var _eye_material: StandardMaterial3D
var _telegraph: Node3D
var _telegraph_fill: MeshInstance3D
var _telegraph_attack: EnemyAttackData
var _telegraph_time := 0.0
var _stagger_ring: MeshInstance3D
var _crystals: Node3D
var _animation: AnimationPlayer
var _last_attack_count := 0
var _last_hurt_count := 0
var _flash := 0.0
var _lean := 0.0
var _bob := 0.0
var _dead_time := 0.0
var _last_position := Vector3.ZERO
var _speed := 0.0


func setup(owner_enemy: Enemy) -> void:
	enemy = owner_enemy
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	if not _load_model():
		_build_placeholder()
	_build_crystals()
	_build_stagger_ring()
	_last_attack_count = enemy.attack_count
	_last_hurt_count = enemy.hurt_count
	_last_position = global_position


## 지금 공격 예고가 보이는지와 그 진행 정도(0~1). 테스트와 HUD용.
func telegraph_progress() -> float:
	if _telegraph == null or not _telegraph.visible or _telegraph_attack == null:
		return -1.0
	return clampf(_telegraph_time / maxf(enemy.wind_up_time(_telegraph_attack), 0.01), 0.0, 1.0)


func _process(delta: float) -> void:
	if enemy == null:
		return
	var moved := global_position - _last_position
	moved.y = 0.0
	_last_position = global_position
	if delta > 0.0:
		_speed = lerpf(_speed, moved.length() / delta, minf(delta * 10.0, 1.0))
	if enemy.attack_count != _last_attack_count:
		_last_attack_count = enemy.attack_count
		_show_telegraph(enemy.current_attack())
	if enemy.hurt_count != _last_hurt_count:
		_last_hurt_count = enemy.hurt_count
		_flash = FLASH_TIME
	_update_telegraph(delta)
	_flash = maxf(_flash - delta, 0.0)
	_crystals.visible = enemy.has_crystal()
	if _crystals.visible:
		_crystals.rotate_y(delta * 0.6)
	_stagger_ring.visible = enemy.is_staggered()
	if _stagger_ring.visible:
		_stagger_ring.rotate_y(delta * 4.0)
	if has_model:
		_animate_model()
	else:
		_animate_placeholder(delta)


# ---- 공격 예고 ----

func _show_telegraph(attack: EnemyAttackData) -> void:
	if _telegraph != null:
		_telegraph.queue_free()
		_telegraph = null
	_telegraph_attack = attack
	_telegraph_time = 0.0
	if attack == null:
		return
	_telegraph = Node3D.new()
	_telegraph.name = "Telegraph"
	add_child(_telegraph)
	_telegraph.position.y = TELEGRAPH_HEIGHT - position.y
	var outline := MeshInstance3D.new()
	outline.mesh = _telegraph_mesh(attack, 1.0)
	outline.material_override = _telegraph_material(0.22)
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.add_child(outline)
	_telegraph_fill = MeshInstance3D.new()
	_telegraph_fill.mesh = outline.mesh
	_telegraph_fill.material_override = _telegraph_material(0.45)
	_telegraph_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_fill.position.y = 0.01
	_telegraph.add_child(_telegraph_fill)


func _update_telegraph(delta: float) -> void:
	if _telegraph == null:
		return
	_telegraph_time += delta
	var progress := telegraph_progress()
	if enemy.state != Enemy.State.WIND_UP or progress >= 1.0:
		_telegraph.queue_free()
		_telegraph = null
		return
	# 원거리는 길이가, 근접은 반지름이 차오른다.
	if _telegraph_attack.projectile_speed > 0.0 or _telegraph_attack.sweep_time > 0.0:
		_telegraph_fill.scale = Vector3(1.0, 1.0, maxf(progress, 0.01))
	else:
		_telegraph_fill.scale = Vector3.ONE * maxf(progress, 0.01)


static func _telegraph_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(TELEGRAPH_COLOR, alpha)
	return material


## 땅에 깔 예고 모양 (적 기준, 앞이 -Z). 근접은 부채꼴(반각 arc), 원거리는 앞으로 뻗은 띠.
static func _telegraph_mesh(attack: EnemyAttackData, scale_value: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	if attack.projectile_speed > 0.0 or attack.sweep_time > 0.0:
		var half := 0.35 if attack.projectile_speed > 0.0 else attack.reach * 0.6
		var length := (RANGED_TELEGRAPH_LENGTH if attack.projectile_speed > 0.0 else attack.lunge + attack.reach) * scale_value
		var corners: Array[Vector3] = [Vector3(-half, 0, 0), Vector3(half, 0, 0), Vector3(half, 0, -length), Vector3(-half, 0, -length)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			tool.add_vertex(corners[i])
		return tool.commit()
	var reach := (attack.reach + 0.35) * scale_value
	var half_angle := deg_to_rad(minf(attack.arc, 180.0))
	var segments := maxi(int(half_angle * 2.0 / deg_to_rad(8.0)), 6)
	for i in segments:
		var a0 := -half_angle + half_angle * 2.0 * i / segments
		var a1 := -half_angle + half_angle * 2.0 * (i + 1) / segments
		tool.add_vertex(Vector3.ZERO)
		tool.add_vertex(Vector3(-sin(a1), 0, -cos(a1)) * reach)
		tool.add_vertex(Vector3(-sin(a0), 0, -cos(a0)) * reach)
	return tool.commit()


# ---- 모델 ----

func _load_model() -> bool:
	var data := enemy.data
	if data.model_file.is_empty():
		return false
	var scene: PackedScene = null
	var project_path := "res://assets/" + data.model_file
	if ResourceLoader.exists(project_path):
		scene = load(project_path) as PackedScene
	else:
		var external := OS.get_executable_path().get_base_dir().path_join(data.model_file)
		if FileAccess.file_exists(external):
			scene = CharacterAppearance.load_gltf_file(external)
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * data.model_scale
	# glTF 모델은 보통 +Z를 앞으로 본다. 적의 앞은 -Z라서 돌려 세운다.
	model.rotation.y = PI
	_rig.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation = players[0] as AnimationPlayer
		PlayerBody._normalize_animation_names(_animation)
	has_model = true
	return true


func _animate_model() -> void:
	if _animation == null:
		return
	var role := &"idle"
	match enemy.state:
		Enemy.State.CHASE:
			role = &"move" if _speed > 0.5 else &"idle"
		Enemy.State.WIND_UP, Enemy.State.RECOVER:
			var attack := enemy.current_attack()
			role = attack.clip if attack != null else &"idle"
		Enemy.State.HURT:
			role = &"hit"
		Enemy.State.STAGGERED:
			role = &"stun"
		Enemy.State.DEAD:
			role = &"dead"
	var clip := StringName(enemy.data.clips.get(role, ""))
	if clip == &"" or not _animation.has_animation(clip):
		return
	if _animation.current_animation != clip:
		_animation.play(clip, 0.15)


# ---- 모델이 없을 때의 도형 몸 ----

func _build_placeholder() -> void:
	var data := enemy.data
	var bulk := data.bulk
	var height := data.height
	var torso := CapsuleMesh.new()
	torso.radius = 0.32 * bulk
	torso.height = height * 0.72
	_add_part(torso, Vector3(0, height * 0.42, 0), data.color)
	var head := SphereMesh.new()
	head.radius = 0.2 * bulk
	head.height = 0.4 * bulk
	_add_part(head, Vector3(0, height * 0.86, 0), data.color.lightened(0.15))
	# 눈(앞쪽 띠). 공격 예고 중에 밝아진다.
	var eye := BoxMesh.new()
	eye.size = Vector3(0.3 * bulk, 0.07, 0.06)
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = Color(1.0, 0.3, 0.1)
	_eye_material.emission_enabled = true
	_eye_material.emission = Color(1.0, 0.3, 0.1)
	_eye_material.emission_energy_multiplier = 1.0
	var eye_mesh := MeshInstance3D.new()
	eye_mesh.mesh = eye
	eye_mesh.material_override = _eye_material
	eye_mesh.position = Vector3(0, height * 0.88, -0.18 * bulk)
	_rig.add_child(eye_mesh)
	# 무기: 근접은 팔에 붙은 날, 원거리는 앞으로 뻗은 통
	var ranged := false
	for attack in data.attacks:
		ranged = ranged or attack.projectile_speed > 0.0
	var weapon := BoxMesh.new()
	if ranged:
		weapon.size = Vector3(0.12, 0.12, 0.7)
		_add_part(weapon, Vector3(0.3 * bulk, height * 0.6, -0.35), data.color.darkened(0.4))
	else:
		weapon.size = Vector3(0.08, 0.7 * bulk, 0.16)
		_add_part(weapon, Vector3(0.42 * bulk, height * 0.5, -0.15), data.color.darkened(0.4))


func _add_part(mesh: PrimitiveMesh, offset: Vector3, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.0
	_materials.append(material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	_rig.add_child(instance)


func _animate_placeholder(delta: float) -> void:
	var state := enemy.state
	var target_lean := 0.0
	var drop := 0.0
	var tilt := 0.0
	var glow := 1.0
	match state:
		Enemy.State.CHASE:
			target_lean = clampf(_speed / 4.0, 0.0, 1.0) * 0.15
		Enemy.State.WIND_UP:
			# 예고: 뒤로 젖혔다가
			var progress := clampf(telegraph_progress(), 0.0, 1.0)
			target_lean = -0.25 * progress
			glow = 1.0 + progress * 5.0
		Enemy.State.RECOVER:
			# 맞힌 순간 앞으로 숙인다
			target_lean = 0.35 * clampf(1.0 - enemy.state_time() / 0.4, 0.0, 1.0)
		Enemy.State.HURT:
			target_lean = -0.2
		Enemy.State.STAGGERED:
			tilt = 0.35
			drop = 0.15
			glow = 0.2
		Enemy.State.DEAD:
			_dead_time += delta
			target_lean = -1.4 * clampf(_dead_time / 0.5, 0.0, 1.0)
			drop = clampf((_dead_time - 1.2) / 1.0, 0.0, 1.0) * enemy.data.height
			glow = 0.0
	_lean = lerpf(_lean, target_lean, minf(delta * 12.0, 1.0))
	_bob += delta * (6.0 if state == Enemy.State.CHASE else 2.0)
	var bob := sin(_bob) * 0.03 if state != Enemy.State.DEAD else 0.0
	_rig.position = Vector3(0, bob - drop, 0)
	_rig.rotation = Vector3(-_lean, 0, tilt)
	var flash := _flash / FLASH_TIME
	for material in _materials:
		material.emission_energy_multiplier = flash * 2.5
		# 격노한 보스는 붉게 빛난다.
		material.emission = Color(1.0, 0.25, 0.15) if enemy.enraged and flash <= 0.0 else Color.WHITE
		if enemy.enraged and flash <= 0.0:
			material.emission_energy_multiplier = 0.6
	if _eye_material != null:
		_eye_material.emission_energy_multiplier = glow


func _build_crystals() -> void:
	_crystals = Node3D.new()
	_crystals.name = "Crystals"
	_crystals.visible = false
	add_child(_crystals)
	var material := StandardMaterial3D.new()
	material.albedo_color = CRYSTAL_COLOR
	material.emission_enabled = true
	material.emission = CRYSTAL_COLOR
	material.emission_energy_multiplier = 2.0
	var count := 5
	for i in count:
		var shard := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.18, 0.45, 0.18)
		shard.mesh = prism
		shard.material_override = material
		var angle := TAU * i / count
		var distance := enemy.data.radius + 0.15
		shard.position = Vector3(cos(angle) * distance, enemy.data.height * (0.35 + 0.1 * (i % 2)), sin(angle) * distance)
		shard.rotation = Vector3(0.3 * cos(angle), 0, -0.3 * sin(angle))
		_crystals.add_child(shard)


func _build_stagger_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.36
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.2)
	torus.material = material
	_stagger_ring = MeshInstance3D.new()
	_stagger_ring.name = "StaggerRing"
	_stagger_ring.mesh = torus
	_stagger_ring.position.y = enemy.data.height + 0.25
	_stagger_ring.visible = false
	add_child(_stagger_ring)
