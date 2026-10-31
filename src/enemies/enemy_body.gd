class_name EnemyBody
extends Node3D
## 적의 보이는 몸. 동기화된 상태(Enemy.state, attack_count, hurt_count, crystal_left)를 보고 모든 피어가 같은 모습을 그린다.
##   - 모델 파일이 있으면 모델의 동작을 튼다(EnemyData.clips). 공격 동작은 예고가 끝나는 순간에 동작의 타격 시각이 오게
##     맞추고(EnemyAttackData.clip_hit), 쓰러지면 쓰러지는 동작 뒤 땅으로 가라앉는다. 없으면 단순한 도형 몸을 코드로 움직인다.
##   - 공격 예고: 맞을 자리(부채꼴·원·직선)가 땅에 깔리고, 맞는 순간까지 안쪽이 차오른다. 눈이 밝아진다.
##   - 맞으면 하얗게 번쩍이고, 경직되면 옆으로 기울어 머리 위에 노란 고리가 돈다.
##   - 원석 결정이 붙으면 몸 둘레에 주황빛 결정이 돋는다.

const TELEGRAPH_COLOR := Color(1.0, 0.35, 0.15)
const TELEGRAPH_HEIGHT := 0.06
const RANGED_TELEGRAPH_LENGTH := 14.0
const CRYSTAL_COLOR := Color(1.0, 0.6, 0.15)
const FLASH_TIME := 0.12
## 모델: 쓰러진 뒤 이 시각(초)부터 이만큼(초) 동안 땅으로 가라앉는다 (Enemy.CORPSE_TIME 안에 끝난다)
const SINK_FROM := 2.6
const SINK_TIME := 1.2
## 격노한 모델에 덧씌우는 붉은빛
const ENRAGED_TINT := Color(1.0, 0.25, 0.15, 0.22)
## 모델: 카메라에서 이 거리(m) 안은 점점이 지운다(FROM에서 다 지우고 TO부터 다 보인다)
const CAMERA_FADE_FROM := 0.3
const CAMERA_FADE_TO := 0.9
## 모델: 공격 동작의 몸 돌림(EnemyAttackData.turn)을 따라가는 가장 빠른 빠르기와, 공격이 끝난 뒤 원래 방향으로
## 돌아오는 빠르기(라디안/초)
const TURN_FOLLOW_SPEED := 25.0
const TURN_BACK_SPEED := 6.0
## 원격 피어: 동기화로 띄엄띄엄 바뀌는 적의 자리를 보이는 몸이 부드럽게 따라가는 시간(초). 이보다 많이(m) 바뀌면
## 따라가지 않고 바로 옮긴다(되살아나기 등).
const SMOOTH_TIME := 0.06
const SMOOTH_MAX_JUMP := 3.0

var enemy: Enemy
var has_model := false

var _rig: Node3D
## 모델과, 공격 동작을 따라 지금 더 돌려 그리는 각도(라디안)
var _model: Node3D
var _turn := 0.0
## 원격 피어: 지난 프레임의 적 자리와, 보이는 몸을 그 자리에서 비켜 그리는 만큼(세상 기준)
var _smooth_from := Vector3.INF
var _smooth_offset := Vector3.ZERO
var _materials: Array[StandardMaterial3D] = []
var _eye_material: StandardMaterial3D
var _telegraph: Node3D
var _telegraph_fill: MeshInstance3D
var _telegraph_attack: EnemyAttackData
var _telegraph_time := 0.0
var _stagger_ring: MeshInstance3D
var _crystals: Node3D
var _animation: AnimationPlayer
## 모델의 메시와, 맞으면 번쩍이게(격노하면 붉게) 덧씌우는 재질, 지금 덧씌웠는지
var _model_meshes: Array[MeshInstance3D] = []
var _overlay: StandardMaterial3D
var _overlay_on := false
## 원작 소리(EnemyData.fx_file). 없으면 소리 없이 돈다.
var fx: CharacterFx
## 소리를 낸 동작과 그 동작에서 소리를 낸 위치(초), 싸움을 걸었는지, 격노했는지
var _sound_clip := &""
var _sound_position := 0.0
var _engaged := false
var _was_enraged := false
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
	var fx_path := CharacterAppearance.existing_file("res://assets/" + enemy.data.fx_file, enemy.data.fx_file) \
			if not enemy.data.fx_file.is_empty() else ""
	if has_model and not fx_path.is_empty():
		fx = CharacterFx.new()
		fx.name = "Fx"
		add_child(fx)
		if not fx.setup(fx_path):
			fx.queue_free()
			fx = null
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
	_smooth(delta)
	var moved := global_position - _last_position
	moved.y = 0.0
	_last_position = global_position
	if delta > 0.0:
		_speed = lerpf(_speed, moved.length() / delta, minf(delta * 10.0, 1.0))
	if enemy.attack_count != _last_attack_count:
		_last_attack_count = enemy.attack_count
		_show_telegraph(enemy.current_attack())
		if has_model:
			_start_attack_clip(enemy.current_attack())
	if enemy.hurt_count != _last_hurt_count:
		_last_hurt_count = enemy.hurt_count
		_flash = FLASH_TIME
		if has_model:
			_play_role(&"hit", 0.08, true)
	_update_telegraph(delta)
	_flash = maxf(_flash - delta, 0.0)
	_crystals.visible = enemy.has_crystal()
	if _crystals.visible:
		_crystals.rotate_y(delta * 0.6)
	_stagger_ring.visible = enemy.is_staggered()
	if _stagger_ring.visible:
		_stagger_ring.rotate_y(delta * 4.0)
	if has_model:
		_animate_model(delta)
		_update_sounds()
	else:
		_animate_placeholder(delta)


## 원격 피어: 적의 자리는 동기화 패킷이 올 때마다 띄엄띄엄 바뀐다(어떤 프레임은 두 번, 어떤 프레임은 0번). 보이는 몸은
## 바뀐 만큼 거꾸로 비켜 두었다가 짧게 줄여 부드럽게 따라가게 한다. 판단하는 호스트는 그대로 그린다.
func _smooth(delta: float) -> void:
	if multiplayer.is_server():
		return
	var at := enemy.global_position
	if _smooth_from != Vector3.INF:
		var jump := at - _smooth_from
		_smooth_offset = _smooth_offset - jump if jump.length() < SMOOTH_MAX_JUMP else Vector3.ZERO
	_smooth_from = at
	_smooth_offset *= exp(-delta / SMOOTH_TIME)
	position = enemy.global_basis.inverse() * _smooth_offset


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

## 적 모델 장면: 프로젝트 안(res://assets/) 파일, 없으면 실행 파일 옆 파일(구운 장면 또는 glTF). 없으면 null.
## 배경 스레드(AssetPreloader)에서도 부른다.
static func load_model_scene(data: EnemyData) -> PackedScene:
	if data.model_file.is_empty():
		return null
	var project_path := "res://assets/" + data.model_file
	if ResourceLoader.exists(project_path):
		return CharacterAppearance.project_resource(project_path) as PackedScene
	return CharacterAppearance.load_model_file(OS.get_executable_path().get_base_dir().path_join(data.model_file))


func _load_model() -> bool:
	var data := enemy.data
	if data.model_file.is_empty():
		return false
	var scene := EnemyBody.load_model_scene(data)
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * data.model_scale
	# glTF 모델은 보통 +Z를 앞으로 본다. 적의 앞은 -Z라서 돌려 세운다.
	model.rotation.y = PI
	_rig.add_child(model)
	_model = model
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_model_meshes.append(mesh)
		# 덩치 큰 적(보스)이 플레이어에 붙으면 카메라가 몸속에 들어가 팔이 화면을 가렸다. 카메라에 아주 가까운 곳은
		# 점점이 지운다. 재질은 같은 모델의 적끼리 함께 쓰므로 한 번만 바꾸면 된다.
		for i in mesh.get_surface_override_material_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			if material != null and material.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED:
				material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				material.distance_fade_min_distance = CAMERA_FADE_FROM
				material.distance_fade_max_distance = CAMERA_FADE_TO
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation = players[0] as AnimationPlayer
		PlayerBody._normalize_animation_names(_animation)
		_play_role(&"idle", 0.0)
	has_model = true
	return true


## 모델에서 그 역할(idle, move, hit, 공격의 clip 등)로 틀 동작 이름. 없으면 빈 이름.
func _role_clip(role: StringName) -> StringName:
	var clip := StringName(enemy.data.clips.get(role, String(role)))
	return clip if _animation != null and _animation.has_animation(clip) else &""


## 역할의 동작을 튼다(이미 틀고 있으면 그대로, restart면 처음부터).
func _play_role(role: StringName, blend: float, restart := false) -> void:
	var clip := _role_clip(role)
	if clip == &"":
		return
	if restart or _animation.current_animation != clip:
		_animation.play(clip, blend)
		if restart:
			_animation.seek(0.0, true)
	_animation.speed_scale = 1.0


## 공격 동작을 예고 동안 clip_from에서 clip_hit까지 예고 시간에 맞춘 빠르기로 틀어, 예고가 끝나는 순간에 맞히게 한다
## (격노해서 예고가 짧으면 더 빠르게). 늦게 알았으면(원격 피어) 지난 만큼 앞으로 옮긴다. 맞힌 뒤(RECOVER)에는 원래
## 빠르기로 마저 튼다.
func _start_attack_clip(attack: EnemyAttackData) -> void:
	if attack == null or _animation == null:
		return
	var clip := _role_clip(attack.clip)
	if clip == &"":
		return
	var total := maxf(enemy.wind_up_time(attack), 0.05)
	var progress := clampf(enemy.state_time() / total, 0.0, 1.0) if enemy.state == Enemy.State.WIND_UP else 1.0
	_animation.play(clip, 0.12)
	if attack.clip_hit > attack.clip_from:
		_animation.seek(lerpf(attack.clip_from, attack.clip_hit, progress), true)
		_animation.speed_scale = (attack.clip_hit - attack.clip_from) / total
	else:
		_animation.seek(attack.clip_from, true)
		_animation.speed_scale = 1.0


func _animate_model(delta: float) -> void:
	if _animation == null:
		return
	match enemy.state:
		Enemy.State.IDLE, Enemy.State.CHASE:
			if _speed > 0.5 and _role_clip(&"move") != &"":
				_play_role(&"move", 0.2)
				_animation.speed_scale = clampf(_speed / maxf(enemy.data.move_clip_speed, 0.1), 0.6, 1.8)
			else:
				_play_role(&"idle", 0.25)
		Enemy.State.WIND_UP, Enemy.State.RECOVER:
			var attack := enemy.current_attack()
			if attack != null and _animation.current_animation != _role_clip(attack.clip):
				_start_attack_clip(attack)
			if enemy.state == Enemy.State.RECOVER:
				_animation.speed_scale = 1.0
		Enemy.State.HURT:
			_play_role(&"hit", 0.08)
		Enemy.State.STAGGERED:
			# 경직: 무너지는 동작 뒤 무너진 채 반복한다.
			var current := _animation.current_animation
			if current != _role_clip(&"stun") and current != _role_clip(&"stun_start"):
				if _role_clip(&"stun_start") != &"":
					_play_role(&"stun_start", 0.12)
					if _role_clip(&"stun") != &"":
						_animation.queue(_role_clip(&"stun"))
				else:
					_play_role(&"stun", 0.12)
		Enemy.State.DEAD:
			_play_role(&"dead", 0.12)
			_dead_time += delta
			_rig.position.y = -clampf((_dead_time - SINK_FROM) / SINK_TIME, 0.0, 1.0) * enemy.data.height
	_update_turn(delta)
	_update_overlay()


## 원작 공격 동작의 몸 돌림(EnemyAttackData.turn, 동작에서는 뺐다)을 모델에 준다. 예고를 시작한 자리(clip_from)를
## 기준으로 돌리고, 공격이 끝나면 자연스러운 빠르기로 원래 방향으로 돌아온다. 예전에는 돌림이 동작 안에 있어서
## 공격이 끝나는 순간 0.2초 만에 휙 돌아갔다(170도 넘게 도는 공격도 있다).
func _update_turn(delta: float) -> void:
	var attack := enemy.current_attack() if enemy.state in [Enemy.State.WIND_UP, Enemy.State.RECOVER] else null
	if attack != null and not attack.turn.is_empty() and _animation.current_animation == _role_clip(attack.clip):
		var wanted := deg_to_rad(attack.turn_at(_animation.current_animation_position) - attack.turn_at(attack.clip_from))
		_turn = move_toward(_turn, wanted, TURN_FOLLOW_SPEED * delta)
	else:
		_turn = move_toward(wrapf(_turn, -PI, PI), 0.0, TURN_BACK_SPEED * delta)
	_model.rotation.y = PI + _turn


## 공격 동작을 따라 모델을 더 돌려 그리는 각도(도, 테스트용)
func model_turn_degrees() -> float:
	return rad_to_deg(_turn)


## 지금 동작의 재생 위치를 따라가며 원작 소리를 낸다. 공격 동작은 예고 시간에 맞춘 빠르기로 틀어서 시간으로 예약하면
## 어긋난다. 동작이 바뀌면 그 자리부터(앞부분을 건너뛰고 튼 공격은 건너뛴 곳의 소리를 내지 않는다), 반복해서 처음으로
## 돌아가면 처음부터 센다. 싸움을 걸 때와 격노할 때는 따로 정한 소리(보이스)를 낸다.
func _update_sounds() -> void:
	if fx == null or _animation == null:
		return
	if not _engaged and enemy.state != Enemy.State.IDLE and enemy.is_alive():
		_engaged = true
		fx.play(&"cue_engage", true)
	if enemy.enraged and not _was_enraged:
		fx.play(&"cue_enrage", true)
	_was_enraged = enemy.enraged
	var clip := StringName(_animation.current_animation)
	var at := _animation.current_animation_position
	if clip != _sound_clip:
		_sound_clip = clip
		_sound_position = at - 0.001
	elif at < _sound_position:
		_sound_position = -0.001
	fx.fire_between(clip, _sound_position, at)
	_sound_position = at


## 맞으면 하얗게 번쩍이고, 격노한 보스는 붉은빛이 돈다(모델 위에 더하는 재질).
func _update_overlay() -> void:
	var flash := _flash / FLASH_TIME
	var tint := Color(1.0, 1.0, 1.0, flash * 0.8)
	if enemy.enraged and flash <= 0.0:
		tint = ENRAGED_TINT
	var on := tint.a > 0.0
	if on != _overlay_on:
		_overlay_on = on
		for mesh in _model_meshes:
			mesh.material_overlay = _overlay if on else null
	if on:
		_overlay.albedo_color = Color(tint.r * tint.a, tint.g * tint.a, tint.b * tint.a, 1.0)


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
