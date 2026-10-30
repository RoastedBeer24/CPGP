class_name FxEffect
extends Node3D
## 원작 이펙트 하나를 한 번 재생한다(이펙트 모델의 노드 계층 + 파티클 시스템들 + 이펙트 자체 애니메이션).
## 원작 동작 이벤트(animation_events.json의 battle_effect_events)대로 놓는다:
##   - 붙일 뼈(mount)가 없으면 캐릭터 모델의 원점(발밑)에 둔다. 원작의 path는 원작 동작의 뿌리 이동인데, 이 게임은
##     동작을 제자리로 묶고 플레이어가 직접 나아가므로 모델 원점이 곧 그 자리다.
##   - move "follow"면 캐릭터를 따라 움직이고, "stationary"면 나타난 자리에 남는다.
##   - rot "stationary"면 나타날 때의 방향을 그대로 둔다(캐릭터가 돌아도 돌지 않는다).
##   - 끝 시각(end)이 되면 남은 파티클까지 한 번에 사라진다(원작과 같다).
## 모든 피어가 동기화된 동작 시작을 보고 저마다 튼다(소리처럼 화면 효과일 뿐이다).

## 이펙트가 시작된 뒤 지난 시간(초)과, 보이는 시간(초)
var time := 0.0
var length := 1.0
## 시간이 흐르는 빠르기를 정하는 함수(맞힌 순간 동작이 멈추면 이펙트도 멈춘다). 비어 있으면 1.
var time_scale: Callable

var _systems: Array[FxSystem] = []
var _animation: AnimationPlayer
var _animation_name := &""
## rot "stationary": 나타날 때의 세상 방향. move "follow"면 위치는 parent_anchor를 따른다.
var _frozen_basis := Basis.IDENTITY
var _freeze_rotation := false
var _rotation_from_model := false
var _pose_basis := Basis.IDENTITY
var _anchor: Node3D
var _model: Node3D


## 이벤트 하나를 재생한다. anchor는 붙일 노드(뼈 자리나 캐릭터 모델), model은 캐릭터 모델(방향 기준)이다.
## 그릴 수 있는 파티클 시스템이 하나도 없으면 null.
static func spawn(effect: EffectLibrary.Effect, event: Dictionary, anchor: Node3D, model: Node3D) -> FxEffect:
	if effect == null or anchor == null or effect.scene == null:
		return null
	var node := FxEffect.new()
	node.name = "Effect_" + str(event.get("effect", ""))
	node.length = maxf(float(event.get("end", 0.0)) - float(event.get("start", 0.0)), 0.05)
	anchor.add_child(node)
	node._place(event, anchor, model)
	node._build(effect)
	if node._systems.is_empty():
		node.queue_free()
		return null
	node.advance(0.0)
	return node


func _place(event: Dictionary, anchor: Node3D, model: Node3D) -> void:
	_anchor = anchor
	_model = model
	var pose: Dictionary = event.get("pose", {}) if typeof(event.get("pose")) == TYPE_DICTIONARY else {}
	_pose_basis = Basis(_quaternion(pose.get("rot", null)))
	var scale_values: Variant = event.get("scale", null)
	if typeof(scale_values) == TYPE_ARRAY and (scale_values as Array).size() >= 3:
		_pose_basis = _pose_basis * Basis.from_scale(Vector3(float(scale_values[0]), float(scale_values[1]), float(scale_values[2])))
	var mounted := event.get("mount") != null
	var following := str(event.get("move", "follow")) == "follow"
	var rotation_follows := str(event.get("rot", "follow")) == "follow"
	# 뼈에 붙으면 뼈의 방향을, 아니면 모델 기준 자세를 따른다.
	transform = Transform3D(Basis.IDENTITY if mounted else _pose_basis, Vector3.ZERO)
	if not following:
		# 나타난 자리에 남는다: 모델 방향 기준 자세를 세상 변환으로 바꿔 고정한다.
		top_level = true
		global_transform = Transform3D(model.global_basis * _pose_basis, anchor.global_position)
	elif not rotation_follows:
		# 따라가되 방향은 원작대로: 뼈에 붙었으면 모델 방향(뼈의 회전은 빼고), 아니면 나타날 때의 방향 그대로
		top_level = true
		_rotation_from_model = mounted
		_frozen_basis = model.global_basis * _pose_basis
		_freeze_rotation = true
		global_transform = Transform3D(_frozen_basis, anchor.global_position)


func _build(effect: EffectLibrary.Effect) -> void:
	var scene := effect.scene.instantiate() as Node3D
	scene.name = "Scene"
	add_child(scene)
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation = players[0] as AnimationPlayer
		var names := _animation.get_animation_list()
		if not names.is_empty():
			_animation_name = names[0]
			_animation.play(_animation_name)
			_animation.pause()
	for i in effect.systems.size():
		var data := effect.systems[i]
		if not FxSystem.drawable(data, effect):
			continue
		var node := scene.get_node_or_null(data.get("node_path", NodePath())) as Node3D
		if node == null:
			continue
		var system := FxSystem.new()
		system.name = "System%d" % i
		system.setup(data, effect, node, _material(effect, i, data))
		add_child(system)
		_systems.append(system)


## 시스템마다 재질은 이펙트에 한 번만 만들어 둔다(같은 이펙트를 여러 번 틀어도 함께 쓴다).
static func _material(effect: EffectLibrary.Effect, index: int, data: Dictionary) -> ShaderMaterial:
	if effect.system_materials.has(index):
		return effect.system_materials[index]
	var renderer: Dictionary = data.get("renderer", {})
	var extras: Dictionary = effect.materials[int((renderer.get("materials", [0]) as Array)[0])]["extras"]
	var streams: Variant = renderer.get("streams", null)
	var second_uv := typeof(streams) == TYPE_ARRAY and (streams as Array).has(5)
	var draw := FxSystem.draw_mode(int(renderer.get("mode", 0)), int(renderer.get("align", 0)))
	var material := FxMaterial.build(extras, effect, renderer, draw, int(renderer.get("mode", 0)) == 4, second_uv)
	effect.system_materials[index] = material
	return material


func _process(delta: float) -> void:
	var speed := 1.0
	if time_scale.is_valid():
		speed = float(time_scale.call())
	time += delta * speed
	if time >= length:
		queue_free()
		return
	advance(time)


## time초 시점으로 이펙트를 맞춘다.
func advance(at: float) -> void:
	time = at
	if _freeze_rotation and _anchor != null and is_instance_valid(_anchor):
		if _rotation_from_model and _model != null and is_instance_valid(_model):
			_frozen_basis = _model.global_basis * _pose_basis
		global_transform = Transform3D(_frozen_basis, _anchor.global_position)
	if _animation != null and _animation_name != &"":
		_animation.seek(minf(time, _animation.get_animation(_animation_name).length), true)
	for system in _systems:
		system.advance(time)


## 살아 있는 파티클 수 (테스트용)
func alive() -> int:
	var total := 0
	for system in _systems:
		total += system.alive()
	return total


func system_count() -> int:
	return _systems.size()


static func _quaternion(values: Variant) -> Quaternion:
	if typeof(values) != TYPE_ARRAY or (values as Array).size() < 4:
		return Quaternion.IDENTITY
	var list: Array = values
	var q := Quaternion(float(list[0]), float(list[1]), float(list[2]), float(list[3]))
	return q.normalized() if q.length_squared() > 0.0 else Quaternion.IDENTITY
