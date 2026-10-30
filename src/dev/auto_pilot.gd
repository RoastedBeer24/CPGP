class_name AutoPilot
extends Node
## 개발용 자동 조종(명령줄 --autoplay). 화면을 찍어 확인할 때 내 플레이어가 저절로 싸운다.
## 로비에서는 잠시 뒤 작전을 출발하고(방장일 때), 보상은 첫 번째 것을 고른다.
## 가까운 적에게 달려가 공격하고, SP가 차면 배틀 스킬, 에너지가 차면 궁극기를 쓰고, 근처 적이 예고하면 회피한다.
## --autoplay=combo면 로비에 남아 제자리에서 기본 공격 연속과 배틀 스킬만 되풀이한다(원작 이펙트 확인용).

var player: Player
## true면 로비에서 제자리 공격만 되풀이한다. 카메라는 캐릭터 뒤에 둔다.
var combo_only := false

var _intent := PlayerIntent.new()
var _cooldown := 0.0
var _lobby_time := 0.0


func _ready() -> void:
	player.intent_override = _intent


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_intent.move = Vector2.ZERO
	if combo_only:
		_combo(delta)
		return
	var session := player.get_parent().get_parent() as Session
	if session != null:
		if session.zone() is Lobby:
			_lobby_time += delta
			if _lobby_time > 1.5 and multiplayer.is_server():
				session.run.start()
			return
		_lobby_time = 0.0
		if session.run.choosing(player):
			player.add_reward(session.run.offers_for(player)[0].id)
	var target := _nearest_enemy()
	if target == null:
		return
	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	var distance := to_target.length()
	# 카메라를 목표 쪽으로 천천히 돌려 화면에 싸움이 보이게 한다.
	var wanted := atan2(-to_target.x, -to_target.z)
	player.camera_yaw = lerp_angle(player.camera_yaw, wanted, minf(delta * 2.0, 1.0))
	if _threatened() and _cooldown <= 0.0:
		_intent.move = Vector2(1, 0)
		_intent.dodge_pressed = true
		_cooldown = 0.8
		return
	if distance > 2.6:
		var local := Basis(Vector3.UP, player.camera_yaw).inverse() * to_target.normalized()
		_intent.move = Vector2(local.x, -local.z)
		return
	if _cooldown > 0.0:
		return
	if player.ultimate_ready():
		_intent.ultimate_pressed = true
	elif player.sp >= player.kit.battle_skill.sp_cost and player.current_action() == null:
		_intent.skill_pressed = true
	else:
		_intent.attack_pressed = true
	_cooldown = 0.25


func _combo(delta: float) -> void:
	player.camera_yaw = lerp_angle(player.camera_yaw, player.rotation.y, minf(delta * 4.0, 1.0))
	if _cooldown > 0.0:
		return
	if player.sp >= player.kit.max_sp and player.current_action() == null:
		_intent.skill_pressed = true
	else:
		_intent.attack_pressed = true
	_cooldown = 0.25


func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for enemy in Roster.enemies(player):
		if not enemy.is_alive():
			continue
		var distance := enemy.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## 가까운 적이 공격을 예고하고 있고 곧 맞을 것 같은지
func _threatened() -> bool:
	for enemy in Roster.enemies(player):
		if enemy.state != Enemy.State.WIND_UP or enemy.current_attack() == null:
			continue
		var left := enemy.current_attack().wind_up - enemy.state_time()
		if left < 0.25 and enemy.global_position.distance_to(player.global_position) < enemy.current_attack().reach + 1.0:
			return true
	return false
