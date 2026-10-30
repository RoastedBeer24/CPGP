class_name NetTestCase
extends TestCase
## 한 프로세스 안에서 여러 피어(호스트, 클라이언트)를 띄우는 테스트의 기반 클래스.
## 피어마다 별도의 SubViewport(독립된 3D 월드와 물리 공간)와 MultiplayerAPI를 주고,
## 실제 ENet으로 127.0.0.1에 접속시킨다.

const SESSION_SCENE := preload("res://src/net/session.tscn")
const CONNECT_TIMEOUT_FRAMES := 180

var port := 0
var _branches: Array[SubViewport] = []


func before_each() -> void:
	port = 47900 + randi() % 2000


func after_each() -> void:
	for branch in _branches:
		var path := branch.get_path()
		(branch.get_node("Session") as Session).leave()
		branch.get_parent().remove_child(branch)
		branch.free()
		tree.set_multiplayer(null, path)
	_branches.clear()


func new_peer(peer_name: String) -> Session:
	var branch := SubViewport.new()
	branch.name = peer_name
	branch.own_world_3d = true
	branch.size = Vector2i(64, 64)
	branch.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(branch)
	tree.set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := SESSION_SCENE.instantiate() as Session
	session.use_device_input = false
	# 적 웨이브는 그것을 보는 테스트만 켠다.
	session.waves_enabled = false
	branch.add_child(session)
	_branches.append(branch)
	return session


## 호스트 하나와 클라이언트 count개를 만들고 모두가 서로를 볼 때까지 기다린다.
func connect_peers(client_count: int) -> Array[Session]:
	var host := new_peer("Host")
	host.host(port)
	var sessions: Array[Session] = [host]
	for i in client_count:
		var client := new_peer("Client%d" % (i + 1))
		client.join("127.0.0.1", port)
		sessions.append(client)
	var expected: Array[int] = []
	for i in sessions.size():
		expected.append(sessions.size())
	await wait_until(func() -> bool: return player_counts(sessions) == expected)
	return sessions


func player_counts(sessions: Array[Session]) -> Array[int]:
	var counts: Array[int] = []
	for session in sessions:
		counts.append(session.players.get_child_count())
	return counts


func wait_until(condition: Callable) -> bool:
	for i in CONNECT_TIMEOUT_FRAMES:
		if condition.call():
			return true
		await tree.physics_frame
	return condition.call()


func physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
