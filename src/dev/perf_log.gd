class_name PerfLog
extends Node
## 확인용: 1초마다 성능을 파일에 적는다(명령줄 --perf-log=파일). 프레임 시간(실제 시간), 엔진의 처리·물리 시간,
## GPU·렌더링 CPU 시간, 그리기 호출·물체·삼각형 수, 노드·적·이펙트 수, 메모리. 화면 확인 도구(tools/capture.sh)로 화면
## 밖 창에서 돌리며 무거운 장면을 찾는다. 마지막 줄은 전체 평균과 가장 나빴던 1초다.

## 이보다 오래 걸린 프레임(ms)은 그때 상황과 함께 따로 적는다.
const SLOW_FRAME := 25.0

var path := ""
## 0보다 크면 이만큼(초) 적은 뒤 게임을 끝낸다(명령줄 --perf-seconds=초).
var seconds := 0

var _file: FileAccess
var _last_usec := 0
var _window := 0.0
var _seconds := 0
var _frames := 0
var _sum := {}
var _max := {}
var _total := {}
var _total_frames := 0
var _worst_second := ""
var _worst_frame := 0.0




## 명령줄(--perf-log=파일)로 만든다. 없으면 null.
static func from_command_line(args: PackedStringArray) -> PerfLog:
	var log: PerfLog = null
	for arg in args:
		if arg.begins_with("--perf-log="):
			log = PerfLog.new()
			log.path = arg.trim_prefix("--perf-log=")
	for arg in args:
		if arg.begins_with("--perf-seconds=") and log != null:
			log.seconds = int(arg.trim_prefix("--perf-seconds="))
	return log


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_last_usec = Time.get_ticks_usec()
	_file.store_line("초\tFPS\t프레임ms(평균/최대)\t처리ms\t물리ms\tGPUms(평균/최대)\t렌더CPUms\t그리기\t물체\t삼각형k\t노드\t적\t이펙트\t비디오MB\t메모리MB")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame := (now - _last_usec) / 1000.0
	_last_usec = now
	var viewport := get_viewport().get_viewport_rid()
	_add(&"frame", frame)
	_add(&"process", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_add(&"physics", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_add(&"gpu", RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	_add(&"render_cpu", RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu())
	_add(&"draws", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add(&"objects", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_add(&"primitives", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)
	_frames += 1
	_window += frame / 1000.0
	if frame > SLOW_FRAME and _seconds > 0:
		_file.store_line("  느린 프레임 %.1fms: %s" % [frame, _situation()])
	if _window >= 1.0:
		_write_second()


## 지금 상황: 구역, 내 플레이어의 상태·동작, 시간 배율, 이펙트 수 (느린 프레임이 어디서 나는지 찾는다)
func _situation() -> String:
	var main := get_parent()
	var session: Session = main.get("session") if main != null else null
	if session == null:
		return "세션 없음"
	var zone := session.zone()
	var mine := ""
	for player in Roster.players(zone as Node3D) if zone is Node3D else []:
		if player.is_multiplayer_authority():
			var action := player.current_action()
			mine = "상태 %s, 동작 %s" % [Player.State.keys()[player.state], action.resource_path.get_file() + ":" + str(action.id) if action != null else "-"]
	return "구역 %s, %s, 시간 배율 %.2f" % [zone.name if zone != null else "-", mine, Engine.time_scale]


func _add(key: StringName, value: float) -> void:
	_sum[key] = float(_sum.get(key, 0.0)) + value
	_max[key] = maxf(float(_max.get(key, 0.0)), value)
	_total[key] = float(_total.get(key, 0.0)) + value


func _average(key: StringName) -> float:
	return float(_sum.get(key, 0.0)) / maxf(_frames, 1)


func _write_second() -> void:
	_seconds += 1
	var effects := get_tree().root.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is FxEffect).size()
	var line := "%d\t%d\t%.1f/%.1f\t%.2f\t%.2f\t%.2f/%.2f\t%.2f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d" % [
		_seconds, _frames, _average(&"frame"), float(_max.get(&"frame", 0.0)), _average(&"process"), _average(&"physics"),
		_average(&"gpu"), float(_max.get(&"gpu", 0.0)), _average(&"render_cpu"), roundi(_average(&"draws")),
		roundi(_average(&"objects")), roundi(_average(&"primitives")), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		get_tree().get_nodes_in_group(Enemy.GROUP).size(), effects,
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6), int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6)]
	_file.store_line(line)
	_file.flush()
	if float(_max.get(&"frame", 0.0)) > _worst_frame:
		_worst_frame = float(_max.get(&"frame", 0.0))
		_worst_second = line
	_total_frames += _frames
	_sum.clear()
	_max.clear()
	_frames = 0
	_window = 0.0
	if seconds > 0 and _seconds >= seconds:
		get_tree().quit()


func _exit_tree() -> void:
	if _file == null:
		return
	var frames := maxf(_total_frames, 1)
	_file.store_line("전체 평균: 프레임 %.2fms, 처리 %.2fms, 물리 %.2fms, GPU %.2fms, 렌더CPU %.2fms, 그리기 %d" % [
		float(_total.get(&"frame", 0.0)) / frames, float(_total.get(&"process", 0.0)) / frames, float(_total.get(&"physics", 0.0)) / frames,
		float(_total.get(&"gpu", 0.0)) / frames, float(_total.get(&"render_cpu", 0.0)) / frames, roundi(float(_total.get(&"draws", 0.0)) / frames)])
	_file.store_line("가장 나쁜 1초: " + _worst_second)
	_file.close()
