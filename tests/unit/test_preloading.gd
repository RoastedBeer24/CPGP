extends TestCase
## 캐릭터를 바꿀 때 멈칫하지 않게 하는 것들: 여러 스레드가 함께 쓰는 읽기 저장소(SharedCache), 배경에서 미리
## 읽기(AssetPreloader), 실행 중에 읽는 glTF 그림에 밉맵 넣기(GltfMipmaps).


func test_cache_loads_once_and_remembers_failures() -> void:
	var cache := SharedCache.new()
	var count := [0]
	var loader := func() -> Variant:
		count[0] += 1
		return null
	assert_eq(cache.get_or_load("a", loader), null)
	assert_eq(cache.get_or_load("a", loader), null)
	assert_eq(count[0], 1, "못 읽은 결과도 기억해 다시 읽지 않는다")
	assert_true(cache.has("a"))
	assert_eq(cache.get_or_load("b", func() -> String: return "모델"), "모델")
	assert_eq(cache.peek("b"), "모델")
	assert_eq(cache.size(), 2)


func test_cache_waits_for_another_thread_reading_the_same_file() -> void:
	var cache := SharedCache.new()
	var count := [0]
	var mutex := Mutex.new()
	var slow := func() -> String:
		mutex.lock()
		count[0] += 1
		mutex.unlock()
		OS.delay_msec(150)
		return "모델"
	var thread := Thread.new()
	thread.start(cache.get_or_load.bind("m", slow))
	# 배경 스레드가 먼저 읽기 시작한 뒤에 같은 것을 찾는다.
	OS.delay_msec(40)
	var value: Variant = cache.get_or_load("m", slow)
	var background: Variant = thread.wait_to_finish()
	assert_eq(value, "모델", "다 읽기를 기다렸다가 그 결과를 쓴다")
	assert_eq(background, "모델")
	assert_eq(count[0], 1, "같은 것을 두 번 읽지 않는다")


func test_preloader_works_in_the_background() -> void:
	var preloader := AssetPreloader.new()
	add_child_autofree(preloader)
	var threads := []
	var mutex := Mutex.new()
	preloader.start([func() -> void:
		mutex.lock()
		threads.append(OS.get_thread_caller_id())
		mutex.unlock()])
	# 테스트는 프레임을 실제 시간보다 빨리 돌린다(--fixed-fps). 우선순위가 낮은 스레드가 차례를 받도록 실제 시간으로
	# 기다리며 주 스레드를 잠깐씩 쉬게 한다(CI에서 프레임 300개로는 모자랐다).
	var deadline := Time.get_ticks_msec() + 10000
	while not preloader.is_done() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
		await tree.process_frame
	assert_true(preloader.is_done(), "할 일을 마친다")
	assert_eq(threads.size(), 1)
	if threads.size() == 1:
		assert_ne(threads[0], OS.get_main_thread_id(), "주 스레드가 아닌 곳에서 읽는다")


func test_preloader_stops_when_the_game_ends() -> void:
	var preloader := AssetPreloader.new()
	tree.root.add_child(preloader)
	var count := [0]
	var jobs: Array[Callable] = []
	for i in 40:
		jobs.append(func() -> void:
			OS.delay_msec(20)
			count[0] += 1)
	preloader.start(jobs)
	await tree.process_frame
	# 트리에서 빠질 때(게임을 끝낼 때) 지금 하는 일까지만 하고 스레드를 기다린다.
	tree.root.remove_child(preloader)
	var finished_count: int = count[0]
	assert_true(finished_count < 40, "남은 일은 하지 않는다 (%d개 함)" % finished_count)
	OS.delay_msec(60)
	assert_eq(count[0], finished_count, "스레드가 끝나 있다")
	preloader.free()


func test_preloader_lists_the_chosen_character_first() -> void:
	var preloader := AssetPreloader.new()
	var jobs: Array[Callable] = []
	preloader._add_character(jobs, Characters.find(&"akekuri").appearance(), true)
	# 모델이 없는 PC(CI)에서는 고른 캐릭터의 실행 파일 옆 모델 자리만 넣는다.
	assert_true(jobs.size() >= 1, "고른 캐릭터는 모델이 어디 있든 읽는다")
	preloader.free()


func test_preloader_jobs_keep_their_resources() -> void:
	# 스레드는 일을 나중에 부른다. 무기를 객체 메서드(weapon.load_scene)로 넣었더니 목록이 사라지며 무기 자원이 풀려
	# 스레드가 오류로 멈췄다. 일 목록을 만든 함수가 끝난 뒤에도 모든 일이 살아 있어야 한다.
	var preloader := AssetPreloader.new()
	var jobs := preloader.jobs_for(&"akekuri")
	assert_true(jobs.size() >= Weapons.PATHS.size(), "무기까지 읽는다")
	for job in jobs:
		assert_true(job.is_valid(), "일이 살아 있다: %s" % job)
	jobs[jobs.size() - 1].call()
	preloader.free()


func test_spawned_character_effects_go_to_the_background() -> void:
	# 플레이어가 생기면 그 캐릭터의 꾸러미를 배경 스레드의 맨 앞으로 넘긴다(주 스레드가 이펙트를 한 프레임에 하나씩
	# 읽으면 프레임마다 수십 ms 멈칫했다). 스레드가 이미 일을 마치고 쉬고 있어도 다시 띄운다.
	var zip_path := ProjectSettings.globalize_path("user://test_prioritize_fx.zip")
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	packer.start_file("fx.json")
	packer.write_file(JSON.stringify({"roles": {}}).to_utf8_buffer())
	packer.close_file()
	packer.close()
	CharacterFx._packages.clear()
	var preloader := AssetPreloader.new()
	add_child_autofree(preloader)
	preloader.start([func() -> void: pass])
	await _until_done(preloader)
	assert_true(preloader.is_done(), "처음 일을 마치고 쉰다")
	assert_true(AssetPreloader.prioritize_package(zip_path), "미리 읽기 노드가 받는다")
	await _until_done(preloader)
	assert_true(CharacterFx._packages.has(zip_path), "쉬던 스레드가 다시 떠서 꾸러미를 읽었다")
	CharacterFx._packages.clear()
	DirAccess.remove_absolute(zip_path)


func _until_done(preloader: AssetPreloader) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not preloader.is_done() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
		await tree.process_frame


func test_runtime_gltf_textures_get_mipmaps() -> void:
	# 실행 중에 읽는 glTF의 그림은 텍스처로 만들기 전에 밉맵을 넣는다(다시 꺼내는 호출은 배경 스레드에서 멈출 수 있다).
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	material.albedo_texture = ImageTexture.create_from_image(image)
	box.material = material
	mesh_instance.mesh = box
	root.add_child(mesh_instance)
	var writer := GLTFDocument.new()
	var write_state := GLTFState.new()
	assert_eq(writer.append_from_scene(root, write_state), OK)
	var glb := writer.generate_buffer(write_state)
	root.free()
	GltfMipmaps.ensure_registered()
	var reader := GLTFDocument.new()
	var state := GLTFState.new()
	assert_eq(reader.append_from_buffer(glb, "", state), OK)
	var textures := state.get_images()
	assert_eq(textures.size(), 1)
	assert_true(textures[0].get_image().has_mipmaps(), "그림을 풀 때 밉맵을 넣는다")
