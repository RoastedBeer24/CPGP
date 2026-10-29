extends TestCase
## 프로젝트 기본 설정과 모든 스크립트·씬이 오류 없이 불러와지는지 확인한다.

const SOURCE_ROOT := "res://src"


func test_main_scene_exists() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_true(ResourceLoader.exists(main_scene), "메인 씬 경로: %s" % main_scene)


func test_main_scene_runs() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed := load(main_scene) as PackedScene
	assert_not_null(packed)
	add_child_autofree(packed.instantiate())
	await tree.process_frame


func test_physics_engine_is_jolt() -> void:
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")


func test_all_sources_load() -> void:
	var paths := _collect(SOURCE_ROOT, [".gd", ".tscn", ".tres"])
	assert_true(paths.size() > 0, "src 아래에 파일이 있어야 함")
	for path in paths:
		assert_not_null(load(path), path)


func _collect(dir_path: String, extensions: Array[String]) -> PackedStringArray:
	var found: PackedStringArray = []
	for file_name in DirAccess.get_files_at(dir_path):
		if extensions.has("." + file_name.get_extension()):
			found.append(dir_path.path_join(file_name))
	for sub_dir in DirAccess.get_directories_at(dir_path):
		found.append_array(_collect(dir_path.path_join(sub_dir), extensions))
	return found
