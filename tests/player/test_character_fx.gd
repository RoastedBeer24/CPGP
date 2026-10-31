extends TestCase
## 캐릭터 소리: 동작을 틀면 정해진 시각에 소리와 보이스가 나고, 다음 동작이 시작되면 앞 동작의 남은 소리는 버린다.
## 원작 소리 꾸러미는 저장소에 없으므로, 작은 꾸러미를 직접 만들어 확인한다.

const WORK_DIR := "user://test_character_fx"

var fx: CharacterFx
var zip_path := ""


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	zip_path = ProjectSettings.globalize_path(WORK_DIR.path_join("fx.zip"))
	var manifest := {"roles": {
		"attack_1": {"length": 1.0, "loop": false, "sounds": [
			{"time": 0.0, "files": ["swing.wav"], "mode": "random", "volume": 0.5},
			{"time": 0.5, "files": ["swing.wav"], "mode": "random", "volume": 0.5},
		], "voices": [
			{"time": 0.1, "chance": 1.0, "cooldown": 0.0, "priority": 50, "languages": {"KR": [{"weight": 1, "files": ["voice_kr.wav"]}]}},
		]},
	}}
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	packer.start_file("fx.json")
	packer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	packer.close_file()
	for name: String in ["swing.wav", "voice_kr.wav"]:
		packer.start_file("audio/" + name)
		packer.write_file(_wav_bytes())
		packer.close_file()
	packer.close()
	CharacterFx._packages.clear()
	fx = CharacterFx.new()
	add_child_autofree(fx)


func after_each() -> void:
	CharacterFx._packages.clear()
	DirAccess.remove_absolute(zip_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WORK_DIR))


func test_sounds_and_voice_play_on_time() -> void:
	assert_true(fx.setup(zip_path), "꾸러미를 읽는다")
	assert_true(fx.has_role(&"attack_1"))
	fx.play(&"attack_1")
	await _frames(2)
	assert_eq(_playing_sounds(), 1, "0초 소리")
	assert_false(fx._voice.playing, "보이스는 아직")
	await _frames(8)
	assert_true(fx._voice.playing, "0.1초에 보이스")
	assert_eq(fx._voice.bus, &"Voice")


func test_package_is_read_once_and_can_be_preloaded() -> void:
	# 게임을 켜면 배경 스레드(AssetPreloader)가 꾸러미를 미리 읽고, 플레이어는 그것을 그대로 쓴다.
	var thread := Thread.new()
	thread.start(CharacterFx.preload_package.bind(zip_path, func() -> bool: return true))
	thread.wait_to_finish()
	var package := CharacterFx.load_package(zip_path)
	assert_true(package.has("streams"), "미리 읽어 둔다")
	assert_eq((package["streams"] as Dictionary).size(), 2, "소리 두 개")
	assert_true(is_same(CharacterFx.load_package(zip_path), package), "다시 읽지 않는다")
	assert_true(fx.setup(zip_path))
	assert_true(is_same(fx._streams, package["streams"]), "플레이어는 미리 읽은 소리를 쓴다")


func test_next_action_drops_pending_sounds() -> void:
	fx.setup(zip_path)
	fx.play(&"attack_1")
	await _frames(2)
	fx.play(&"no_such_action")
	assert_true(fx._pending.is_empty(), "다음 동작이 시작되면 앞 동작의 남은 소리는 버린다")


func test_missing_package_is_silent() -> void:
	assert_false(fx.setup(ProjectSettings.globalize_path(WORK_DIR.path_join("none.zip"))))
	fx.play(&"attack_1")
	await _frames(2)
	assert_false(fx.has_sounds())


func _playing_sounds() -> int:
	var count := 0
	for player in fx._sounds:
		if player.playing:
			count += 1
	return count


## 0.2초짜리 조용한 16비트 모노 WAV
func _wav_bytes() -> PackedByteArray:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(22050 * 2 / 5)
	stream.data = data
	var path := ProjectSettings.globalize_path(WORK_DIR.path_join("tone.wav"))
	stream.save_to_wav(path)
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
