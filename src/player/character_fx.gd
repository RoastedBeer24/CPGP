class_name CharacterFx
extends Node3D
## 캐릭터 동작에 맞춰 원작의 소리와 보이스, 이펙트를 낸다. 몸(PlayerBody)이 동작을 틀 때 play(동작 이름)를 부른다.
##
## 원본 꾸러미(zip, tools/extract_character_fx.py가 만든다)의 fx.json에 동작마다 "몇 초에 무엇을 낼지"가 있다.
##   - 소리: 여러 후보 중 하나를 고르고(random) 원본 볼륨대로 낸다. 효과음 버스(SFX).
##   - 보이스: 확률·재사용 대기·우선순위가 있다. 설정의 음성 언어로 고르고, 음성 버스(Voice)로 낸다.
##     더 높은 우선순위의 보이스가 나오면 지금 보이스를 끊는다.
##   - 이펙트: 원작 이펙트(칼빛·불꽃·연기)를 시각에 맞춰 띄운다(FxEffect). 이펙트 모델과 파티클 설정도 zip에 있다.
## 동작이 끊기고 다음 동작이 시작되면 아직 나지 않은 것은 버린다(연속 공격에서 앞 동작의 끝소리가 겹치지 않게).
## 이미 나온 이펙트는 제 끝 시각까지 보인다.
## zip은 원작 자산이라 저장소에 없다. 없으면 소리와 이펙트 없이 돈다.
## 적(EnemyBody)도 쓴다: 공격 동작의 재생 위치를 따라가며 fire_between으로 소리를 내고, 싸움을 걸 때·격노할 때의 소리는
## cue_engage, cue_enrage 역할로 play한다(tools/extract_enemy.py가 만든다).

## 원본 볼륨은 원작 믹서 기준이라 그대로 내면 작다. 전체를 이만큼 키운다(dB).
const GAIN_DB := 6.0
const VOICE_GAIN_DB := 3.0
## 한 캐릭터가 동시에 낼 수 있는 효과음 수
const MAX_SOUNDS := 10
## 소리가 들리는 거리: 이 거리(m)까지는 거의 그대로 들린다.
const UNIT_SIZE := 8.0

## zip 경로 → {"roles": 동작별 정보, "streams": 파일 이름 → AudioStream}. 플레이어마다 다시 읽지 않는다.
static var _loaded: Dictionary[String, Dictionary] = {}

var _source := ""
var _roles: Dictionary = {}
var _streams: Dictionary = {}
## 원작 연출 카메라 컷: 이름(궁극기 "ultimate") → 컷 목록
var _cameras: Dictionary = {}
## 원작 캐릭터 화면의 카메라 자리: 이름("overview", "weapon" 등) → [x, y, z, qx, qy, qz, qw, 시야각]
var _camera_poses: Dictionary = {}
## 아직 나지 않은 소리: [시각, 종류("sound"/"voice"), 정보]
var _pending: Array[Array] = []
var _clock := 0.0
var _sounds: Array[AudioStreamPlayer3D] = []
var _voice: AudioStreamPlayer3D
var _voice_priority := -1
var _voice_ready_at := 0.0
## 미리 읽어 둘 이펙트 [glb 파일, 파티클 파일]. 처음 틀 때 멈칫하지 않게 한 프레임에 하나씩 읽는다.
var _preload: Array[Array] = []
var _sounds_started := 0
## 소품(보조 무기) 목록: [{file, idle, fight, shown, timelines}] (tools/extract_character_fx.py의 PROPS)
var _props: Array = []
## 읽은 소품 장면: "zip|파일" → PackedScene
static var _prop_scenes: Dictionary[String, PackedScene] = {}


## 꾸러미를 읽는다. 없거나 읽지 못하면 false (소리 없이 돈다).
func setup(zip_path: String) -> bool:
	if zip_path.is_empty() or not FileAccess.file_exists(zip_path):
		return false
	if not _loaded.has(zip_path):
		var package := _read_package(zip_path)
		if package.is_empty():
			return false
		_loaded[zip_path] = package
	_source = zip_path
	_roles = _loaded[zip_path]["roles"]
	_streams = _loaded[zip_path]["streams"]
	_cameras = _loaded[zip_path].get("camera", {})
	_camera_poses = _loaded[zip_path].get("camera_poses", {})
	_props = _loaded[zip_path].get("props", [])
	_voice = _make_player(&"Voice")
	for role: String in _roles:
		for effect: Dictionary in (_roles[role] as Dictionary).get("effects", []):
			_preload.append([str(effect.get("file", "")), str(effect.get("particles", ""))])
	return true


func has_sounds() -> bool:
	return not _roles.is_empty()


func has_role(role: StringName) -> bool:
	return _roles.has(String(role))


## 원작 연출 카메라 컷 목록(궁극기 등). 컷마다 at(시작 초), duration, easeOut(원래 카메라로 돌아가는 초),
## follow([위치, 방향]을 캐릭터를 따라 바꾸는지), rate(초당 장 수), frames([x, y, z, qx, qy, qz, qw, 시야각]을 이어 붙임,
## 캐릭터 모델 기준·glTF 좌표)가 있다. 없으면 빈 배열.
func camera_shots(name: StringName) -> Array:
	return _cameras.get(String(name), [])


## 원작 캐릭터 화면의 카메라 자리: [x, y, z, qx, qy, qz, qw, 시야각] (캐릭터 모델 기준·glTF 좌표, 카메라는 -Z를 본다).
## "overview"(첫 화면), "weapon"(무기 보기), "equip", "skill"이 있다. 없으면 빈 배열.
func camera_pose(name: StringName) -> Array:
	return _camera_poses.get(String(name), [])


## 캐릭터 화면 카메라 자리를 넣는다 (테스트용)
func set_camera_poses(poses: Dictionary) -> void:
	_camera_poses = poses


## 동작에 원작 이펙트가 있는지 (있으면 몸이 임시 검기를 그리지 않는다)
func has_effects(role: StringName) -> bool:
	var info: Dictionary = _roles.get(String(role), {})
	return not (info.get("effects", []) as Array).is_empty()


## 동작에 딸린 소리를 시작한다. 앞 동작의 아직 나지 않은 소리는 버린다. keep_pending이면 버리지 않는다
## (낙하 공격처럼 이어지는 동작: 시작 동작의 칼빛이 0.6초에 나오는데 그 전에 땅에 닿을 수 있다).
func play(role: StringName, keep_pending := false) -> void:
	if not keep_pending:
		_pending.clear()
	var info: Dictionary = _roles.get(String(role), {})
	if info.is_empty():
		return
	for sound: Dictionary in info.get("sounds", []):
		_pending.append([_clock + float(sound["time"]), "sound", sound])
	for voice: Dictionary in info.get("voices", []):
		_pending.append([_clock + float(voice["time"]), "voice", voice])
	for effect: Dictionary in info.get("effects", []):
		_pending.append([_clock + float(effect.get("start", 0.0)), "effect", effect])
	_pending.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))


func stop() -> void:
	_pending.clear()


## 동작의 from초 뒤부터 to초까지에 든 소리·보이스를 바로 낸다. 동작의 재생 위치를 직접 따라갈 때 쓴다(적의 공격처럼
## 예고 시간에 맞춰 빠르기가 바뀌는 동작은 시간으로 예약하면 어긋난다).
func fire_between(role: StringName, from: float, to: float) -> void:
	var info: Dictionary = _roles.get(String(role), {})
	if info.is_empty():
		return
	for sound: Dictionary in info.get("sounds", []):
		var time := float(sound["time"])
		if time > from and time <= to:
			_play_sound(sound)
	for voice: Dictionary in info.get("voices", []):
		var time := float(voice["time"])
		if time > from and time <= to:
			_play_voice(voice)


## 소품(보조 무기) 목록. 항목마다 file(zip 안 모델), idle·fight(쉬는 자리·싸우는 자리 노드 이름), shown(시간표가 없는
## 동작에서 쉬는 자리에 보이는지), timelines(동작 이름 → [시각, 자리, ...], 자리 0 숨김·1 쉬는 자리·2 싸우는 자리)가 있다.
func props() -> Array:
	return _props


## 소품 모델 장면(zip 안 glb를 실행 중에 읽는다, 플레이어끼리 한 번만). 읽지 못하면 null.
func prop_scene(file: String) -> PackedScene:
	var key := "%s|%s" % [_source, file]
	if _prop_scenes.has(key):
		return _prop_scenes[key]
	var scene: PackedScene = null
	var reader := ZIPReader.new()
	if reader.open(_source) == OK:
		var glb := reader.read_file(file)
		reader.close()
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if not glb.is_empty() and document.append_from_buffer(glb, "", state) == OK:
			var root := document.generate_scene(state)
			if root != null:
				CharacterAppearance._add_mipmaps(root)
				for node: Node in root.find_children("*", "", true, false):
					node.owner = root
				scene = PackedScene.new()
				if scene.pack(root) != OK:
					scene = null
				root.free()
	_prop_scenes[key] = scene
	return scene


## 지금까지 낸 효과음 수 (테스트용)
func sounds_started() -> int:
	return _sounds_started


func _process(delta: float) -> void:
	_clock += delta
	while not _pending.is_empty() and float(_pending[0][0]) <= _clock:
		var event: Array = _pending.pop_front()
		match event[1]:
			"sound":
				_play_sound(event[2])
			"voice":
				_play_voice(event[2])
			"effect":
				_play_effect(event[2])
	if not _preload.is_empty():
		var next: Array = _preload.pop_back()
		EffectLibrary.load_effect(_source, str(next[0]), str(next[1]))


## 원작 이펙트 하나를 띄운다. 붙일 자리(뼈나 모델)는 몸이 알려 준다.
func _play_effect(info: Dictionary) -> void:
	var body := get_parent() as PlayerBody
	if body == null or not body.has_model:
		return
	var effect := EffectLibrary.load_effect(_source, str(info.get("file", "")), str(info.get("particles", "")))
	var mount: Variant = info.get("mount")
	var anchor := body.effect_anchor(StringName(str(mount)) if mount != null else &"")
	var spawned := FxEffect.spawn(effect, info, anchor, body.model_root())
	if spawned != null:
		spawned.time_scale = body.action_time_scale


func _play_sound(sound: Dictionary) -> void:
	var files: Array = sound.get("files", [])
	if files.is_empty():
		return
	var index := randi() % files.size() if str(sound.get("mode", "random")) == "random" else 0
	var stream := _stream(str(files[index]))
	if stream == null:
		return
	var volume := float(sound.get("volume", 1.0))
	var volumes: Array = sound.get("volumes", [])
	if index < volumes.size():
		volume *= float(volumes[index])
	var player := _free_sound_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = linear_to_db(maxf(volume, 0.0001)) + GAIN_DB
	player.play()
	_sounds_started += 1


func _play_voice(voice: Dictionary) -> void:
	if randf() > float(voice.get("chance", 1.0)) or _clock < _voice_ready_at:
		return
	var priority := int(voice.get("priority", 0))
	if _voice.playing and priority < _voice_priority:
		return
	var languages: Dictionary = voice.get("languages", {})
	var choices: Array = languages.get(GameSettings.voice_language, languages.get("KR", []))
	if choices.is_empty():
		return
	var total := 0.0
	for choice: Dictionary in choices:
		total += float(choice.get("weight", 1.0))
	var pick := randf() * total
	var files: Array = []
	for choice: Dictionary in choices:
		pick -= float(choice.get("weight", 1.0))
		files = choice.get("files", [])
		if pick <= 0.0:
			break
	if files.is_empty():
		return
	var stream := _stream(str(files[randi() % files.size()]))
	if stream == null:
		return
	_voice.stream = stream
	_voice.volume_db = VOICE_GAIN_DB
	_voice.play()
	_voice_priority = priority
	_voice_ready_at = _clock + float(voice.get("cooldown", 0.0))


func _stream(file: String) -> AudioStream:
	return _streams.get(file) as AudioStream


func _free_sound_player() -> AudioStreamPlayer3D:
	for player in _sounds:
		if not player.playing:
			return player
	if _sounds.size() >= MAX_SOUNDS:
		return null
	var player := _make_player(&"SFX")
	_sounds.append(player)
	return player


func _make_player(bus: StringName) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = bus
	player.unit_size = UNIT_SIZE
	player.max_distance = 60.0
	player.position = Vector3.UP * 1.2
	add_child(player)
	return player


## zip에서 fx.json과 소리 파일을 읽는다. 소리는 처음 한 번만 읽어 모든 플레이어가 함께 쓴다.
static func _read_package(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {}
	var json := JSON.new()
	if json.parse(reader.read_file("fx.json").get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		reader.close()
		return {}
	var manifest: Dictionary = json.data
	var streams := {}
	var cameras: Dictionary = manifest.get("camera", {})
	for entry in reader.get_files():
		if entry.begins_with("audio/") and entry.ends_with(".wav"):
			var stream := AudioStreamWAV.load_from_buffer(reader.read_file(entry))
			if stream != null:
				streams[entry.get_file()] = stream
	reader.close()
	return {"roles": manifest.get("roles", {}), "streams": streams, "camera": cameras, "camera_poses": manifest.get("camera_poses", {}),
			"props": manifest.get("props", [])}
