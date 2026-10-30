class_name Interactor
extends Node
## 플레이어의 상호작용(F): 뒤에서 적 제압, 쓰러진 몸 들기, 내려놓기, 컨테이너에 숨기기.
##
## 조종하는 피어가 지금 할 수 있는 일을 찾아 prompt로 알려 주고, 키를 누르면 호스트에 요청한다.
## 호스트가 다시 판정해서 적의 상태를 바꾸고, 몸을 들었으면 조종하는 피어에 알려 준다.
## 적은 플레이어 목록(Players)을 기준으로 한 상대 경로로 주고받는다. 테스트처럼 한 프로세스에
## 여러 피어가 있으면 절대 경로가 피어마다 다르기 때문이다.

enum Action { NONE, TAKEDOWN, PICK_UP, DROP, STASH }

## 몸을 들고 있으면 이 배율로 느려진다.
const CARRY_SPEED_MULTIPLIER := 0.6

## 지금 들고 있는 몸 (조종하는 피어에서만 의미가 있다)
var carrying: Enemy
## 화면에 보여 줄 안내 ("F: 제압" 등). 할 일이 없으면 빈 문자열.
var prompt := ""
var focus_action := Action.NONE
var focus: Enemy

## 몸을 든 직후에는 동기화가 늦게 올 수 있으므로 잠시 기다렸다가 들고 있는지 다시 확인한다.
var _carry_grace := 0.0

@onready var player: Player = get_parent() as Player


func _process(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return
	_carry_grace = maxf(_carry_grace - delta, 0.0)
	if carrying != null and _carry_grace <= 0.0:
		var lost := not is_instance_valid(carrying) or carrying.carrier_peer != player.get_multiplayer_authority()
		if lost or not player.health.is_alive():
			carrying = null
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_multiplayer_authority() or not player.use_device_input:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.is_action_pressed(InputActions.INTERACT):
		interact()


## 지금 가능한 상호작용을 한다. 테스트에서도 직접 부른다.
func interact() -> void:
	if focus_action == Action.NONE:
		return
	var path := NodePath("")
	if focus != null:
		path = player.get_parent().get_path_to(focus)
	_host_interact.rpc_id(1, focus_action, path)


func _update_focus() -> void:
	focus = null
	focus_action = Action.NONE
	if not player.health.is_alive():
		prompt = ""
		return
	if carrying != null:
		focus = carrying
		var spot := HideSpot.near(player, player.global_position)
		focus_action = Action.STASH if spot != null else Action.DROP
		prompt = "F: 숨기기" if spot != null else "F: 내려놓기"
		return
	var best_distance := INF
	var look := -player.global_basis.z
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.get_world_3d() != player.get_world_3d():
			continue
		var to_enemy := enemy.global_position - player.global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		# 내 앞쪽에 있는 것만 고른다.
		if distance >= best_distance or (distance > 0.3 and look.dot(to_enemy.normalized()) < 0.3):
			continue
		if enemy.can_be_taken_down_by(player):
			focus = enemy
			focus_action = Action.TAKEDOWN
			best_distance = distance
		elif enemy.can_be_picked_up_by(player):
			focus = enemy
			focus_action = Action.PICK_UP
			best_distance = distance
	match focus_action:
		Action.TAKEDOWN:
			prompt = "F: 제압"
		Action.PICK_UP:
			prompt = "F: 몸 들기"
		_:
			prompt = ""


# ---- 호스트 판정 ----

@rpc("any_peer", "call_local", "reliable")
func _host_interact(action: int, enemy_path: NodePath) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != player.get_multiplayer_authority():
		return
	var enemy := player.get_parent().get_node_or_null(enemy_path) as Enemy if not enemy_path.is_empty() else null
	if enemy == null:
		return
	match action:
		Action.TAKEDOWN:
			enemy.try_takedown(player)
		Action.PICK_UP:
			if enemy.pick_up(player):
				_set_carrying.rpc_id(player.get_multiplayer_authority(), enemy_path)
		Action.DROP:
			if enemy.carrier_peer == player.get_multiplayer_authority():
				enemy.drop()
				_set_carrying.rpc_id(player.get_multiplayer_authority(), NodePath(""))
		Action.STASH:
			if enemy.carrier_peer == player.get_multiplayer_authority() and HideSpot.near(player, player.global_position) != null:
				enemy.stash()
				_set_carrying.rpc_id(player.get_multiplayer_authority(), NodePath(""))


@rpc("any_peer", "call_local", "reliable")
func _set_carrying(enemy_path: NodePath) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	carrying = player.get_parent().get_node_or_null(enemy_path) as Enemy if not enemy_path.is_empty() else null
	_carry_grace = 0.5
