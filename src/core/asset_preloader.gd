class_name AssetPreloader
extends Node
## 캐릭터를 바꾸거나 전투 방에 들어갈 때 멈칫하지 않게, 게임을 켜면 배경 스레드에서 모델·소리 꾸러미·원작 이펙트·
## 소품을 미리 읽어 둔다. 예전에는 처음 고른 캐릭터마다 모델(1~2초)과 소리 꾸러미(약 1초)를 그 자리에서 읽느라 게임이
## 멈췄다.
##
## 읽은 것은 각 읽기 함수의 저장소(SharedCache)에 들어간다. 게임이 같은 것을 찾으면 다시 읽지 않고, 배경 스레드가 아직
## 읽는 중이면 다 읽기를 기다렸다가 쓴다. 고른 캐릭터와 적은 어차피 쓰므로 먼저 읽고, 다른 캐릭터의 모델은 압축해
## 구운 장면(.scn)이나 프로젝트 안 모델이 있을 때만 읽는다(glTF를 그대로 읽으면 텍스처가 그래픽 메모리를 많이 쓴다).
## 메인 장면(main.gd)이 만든다.

## 다 읽었다 (화면 확인·테스트용)
signal finished

## false면 메인 장면이 미리 읽지 않는다 (테스트 러너가 끈다)
static var enabled := true

var _thread: Thread
var _jobs: Array[Callable] = []
var _mutex := Mutex.new()
var _stopping := false
var _done := false


## 고른 캐릭터를 먼저, 그다음 적, 다른 캐릭터, 무기 순서로 배경 스레드에서 읽는다.
func start_for(character_id: StringName) -> void:
	start(jobs_for(character_id))


## start_for가 할 일들. 일마다 쓰는 자원(무기·적 데이터)을 붙잡고 있어야 한다(스레드가 나중에 부른다).
func jobs_for(character_id: StringName) -> Array[Callable]:
	var jobs: Array[Callable] = []
	var characters := Characters.all()
	var chosen := Characters.find(character_id)
	if chosen != null:
		_add_character(jobs, chosen.appearance(), true)
	for path: String in DirAccess.get_files_at("res://data/enemies"):
		var data := load("res://data/enemies/" + path.trim_suffix(".remap")) as EnemyData
		if data == null:
			continue
		jobs.append(EnemyBody.load_model_scene.bind(data))
		if not data.fx_file.is_empty():
			var fx_path := CharacterAppearance.existing_file("res://assets/" + data.fx_file, data.fx_file)
			if not fx_path.is_empty():
				jobs.append(CharacterFx.load_package.bind(fx_path))
	for character in characters:
		if character != chosen:
			_add_character(jobs, character.appearance(), false)
	for weapon in Weapons.all():
		# 객체의 메서드 Callable은 객체를 붙잡지 않는다(목록이 사라지면 무기 자원이 풀린다). 람다가 붙잡게 한다.
		jobs.append(func() -> void: weapon.load_scene())
	return jobs


## 할 일(인자 없는 함수들)을 배경 스레드에서 차례로 한다.
func start(jobs: Array[Callable]) -> void:
	if _thread != null:
		return
	_jobs = jobs
	_thread = Thread.new()
	_thread.start(_run, Thread.PRIORITY_LOW)


func is_done() -> bool:
	_mutex.lock()
	var done := _done
	_mutex.unlock()
	return done


func _add_character(jobs: Array[Callable], appearance: CharacterAppearance, chosen: bool) -> void:
	if appearance == null:
		return
	if not appearance.model_path.is_empty() and ResourceLoader.exists(appearance.model_path):
		jobs.append(CharacterAppearance.project_resource.bind(appearance.model_path))
	else:
		var file := appearance.external_model_path()
		if not file.is_empty() and (chosen or FileAccess.file_exists(CharacterAppearance.baked_path(file))):
			jobs.append(CharacterAppearance.model_entry.bind(file))
	var fx_path := appearance.fx_file()
	if not fx_path.is_empty():
		# 소품·이펙트는 꾸러미를 읽은 뒤에야 목록을 안다. 게임을 끝내면 중간에 그만둔다.
		jobs.append(CharacterFx.preload_package.bind(fx_path, _keep_going))


func _keep_going() -> bool:
	_mutex.lock()
	var stopping := _stopping
	_mutex.unlock()
	return not stopping


func _run() -> void:
	var started := Time.get_ticks_msec()
	for job in _jobs:
		if not _keep_going():
			break
		if job.is_valid():
			job.call()
	_mutex.lock()
	_done = true
	_mutex.unlock()
	print_verbose("미리 읽기 끝: %d ms" % (Time.get_ticks_msec() - started))
	finished.emit.call_deferred()


## 게임을 끝낼 때: 지금 읽는 것까지만 읽고 스레드를 기다린다(스레드가 도는 채로 엔진을 끄면 오류가 나거나 멈춘다).
func _exit_tree() -> void:
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
