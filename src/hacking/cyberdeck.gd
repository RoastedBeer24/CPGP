class_name Cyberdeck
extends Node
## 플레이어의 사이버덱: RAM, 스캔, 퀵핵 업로드, 적 넷러너의 역해킹.
##
## 스캔(Tab)과 대상 고르기는 조종하는 피어가 하고, 퀵핵을 올리면 호스트에 요청한다.
## 호스트가 RAM과 거리를 확인해 업로드를 진행하고, 끝나면 대상의 apply_quickhack을 부른다.
## RAM과 업로드 진행도는 호스트 권한이라 HealthSync로 모두에게 퍼진다(Session이 권한을 호스트로 돌린다).
## 대상은 플레이어 목록(Players) 기준 상대 경로로 주고받는다(Interactor와 같은 이유).

signal hack_finished(target: Node, hack: QuickhackData)

## 퀵핵을 올릴 수 있는 거리(m)
const HACK_RANGE := 45.0
## 조준점에서 이 각도(라디안) 안에 있는 대상을 고른다. 멀리 있는 대상은 조금 더 넉넉하게 잡는다.
const FOCUS_ANGLE := 0.14
const HACK_PATHS: Array[String] = [
	"res://data/hacking/camera_shutdown.tres",
	"res://data/hacking/distract.tres",
	"res://data/hacking/overheat.tres",
	"res://data/hacking/weapon_glitch.tres",
	"res://data/hacking/open_door.tres",
	"res://data/hacking/turret_takeover.tres",
]

@export var max_ram := 6.0
## 초당 회복하는 RAM
@export var ram_regen := 0.5

# ---- 호스트가 정하고 동기화되는 값 ----
var ram := 6.0
## 내가 올리고 있는 퀵핵의 진행도(0~1). 0이면 올리는 중이 아니다.
var upload_progress := 0.0
## 올리고 있는 퀵핵과 대상 이름 (화면 표시용)
var upload_label := ""
## 적 넷러너가 나에게 역해킹을 올리고 있는 진행도(0~1)
var incoming_progress := 0.0

# ---- 조종하는 피어 ----
## 스캔 모드인지
var scanning := false
## 스캔 중 조준점에 있는 대상
var focus: Hackable

var _hacks: Dictionary[StringName, QuickhackData] = {}
var _upload_target: Hackable
var _upload_hack: QuickhackData
var _upload_left := 0.0
var _burn_left := 0.0
var _burn_dps := 0.0

@onready var player: Player = get_parent() as Player


func _ready() -> void:
	# Player와 서로 참조하는 중에 리소스를 미리 불러오면 깨지므로 실행 시점에 불러온다.
	for path in HACK_PATHS:
		var hack := load(path) as QuickhackData
		_hacks[hack.id] = hack
	ram = max_ram


func hack_by_id(id: StringName) -> QuickhackData:
	return _hacks.get(id)


## 조종하는 피어에서 매 물리 프레임 부른다. 스캔 중이면 조준점의 대상을 고른다.
func update_scan(scan_held: bool) -> void:
	scanning = scan_held and player.health.is_alive()
	focus = find_focus() if scanning else null


## 화면 가운데(조준점)에 가장 가까운, 보이는 해킹 대상
func find_focus() -> Hackable:
	var camera := player.camera
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var space := player.get_world_3d().direct_space_state
	var best: Hackable
	var best_angle := INF
	for node in get_tree().get_nodes_in_group(Hackable.GROUP):
		var hackable := node as Hackable
		if hackable == null or hackable.get_viewport().find_world_3d() != player.get_world_3d() or not hackable.is_available():
			continue
		var to_target := hackable.global_position - origin
		var distance := to_target.length()
		if distance > HACK_RANGE or distance < 0.1:
			continue
		var angle := forward.angle_to(to_target)
		if angle > maxf(FOCUS_ANGLE, atan(0.7 / distance)) or angle >= best_angle:
			continue
		# 대상 자신(문, 포탑)에 가리지 않도록 조금 앞쪽 점까지만 확인한다.
		if not Senses.has_line_of_sight(space, origin, hackable.global_position - to_target.normalized() * 0.6):
			continue
		best = hackable
		best_angle = angle
	return best


## 스캔 중 1~3번 키로 고른 퀵핵을 올리도록 호스트에 요청한다.
func request_hack(slot: int) -> void:
	if focus == null or slot < 1 or slot > focus.quickhacks.size():
		return
	var hack := focus.quickhacks[slot - 1]
	_host_upload.rpc_id(1, player.get_parent().get_path_to(focus), String(hack.id))


func is_uploading() -> bool:
	return _upload_target != null


# ---- 호스트 판정 ----

@rpc("any_peer", "call_local", "reliable")
func _host_upload(target_path: NodePath, hack_id: String) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != player.get_multiplayer_authority():
		return
	if _upload_target != null or not player.health.is_alive():
		return
	var hackable := player.get_parent().get_node_or_null(target_path) as Hackable
	var hack := hack_by_id(StringName(hack_id))
	if hackable == null or hack == null or not hackable.is_available() or not hackable.quickhacks.has(hack):
		return
	if ram < hack.ram_cost or hackable.global_position.distance_to(player.aim_origin()) > HACK_RANGE + 2.0:
		return
	ram -= hack.ram_cost
	_upload_target = hackable
	_upload_hack = hack
	_upload_left = hack.upload_time
	upload_progress = 0.01
	upload_label = "%s → %s" % [hack.display_name, hackable.display_name]


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	ram = minf(ram + ram_regen * delta, max_ram)
	if _upload_target != null:
		if not is_instance_valid(_upload_target) or not _upload_target.is_available() or not player.health.is_alive():
			_clear_upload()
		else:
			_upload_left -= delta
			upload_progress = clampf(1.0 - _upload_left / maxf(_upload_hack.upload_time, 0.01), 0.01, 1.0)
			if _upload_left <= 0.0:
				var target := _upload_target.target()
				var hack := _upload_hack
				_clear_upload()
				target.call("apply_quickhack", hack, player)
				hack_finished.emit(target, hack)
	if _burn_left > 0.0:
		_burn_left -= delta
		player.health.apply_damage(DamageInfo.hack(_burn_dps * delta, 0, player.global_position, &"enemy_overheat"))


func _clear_upload() -> void:
	_upload_target = null
	_upload_hack = null
	upload_progress = 0.0
	upload_label = ""


## 적 넷러너의 역해킹이 끝나면 호스트가 부른다. 장갑을 무시하는 화상 피해를 준다.
func apply_overheat(damage_per_second: float, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_burn_dps = damage_per_second
	_burn_left = duration


func is_burning() -> bool:
	return _burn_left > 0.0
