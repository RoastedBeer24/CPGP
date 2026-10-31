extends SceneTree
## 모델(glb)을 내보낸 게임이 바로 읽는 Godot 장면(.scn)으로 굽는다(CharacterAppearance.baked_path, 같은 이름의 .scn).
##
## 내보낸 게임(Godot 내보내기 템플릿)에는 텍스처 압축기가 없다. glb를 그대로 읽으면 텍스처가 압축되지 않은 채 그래픽
## 메모리에 올라가고(캐릭터 하나에 125~300MB, 모델 전부 약 2GB), 그림을 풀고 밉맵을 만드느라 캐릭터 하나에 1~2초
## 멈췄다. 여기서 큰 색·법선·설정·발광 텍스처를 BC7로 미리 압축하고(약 4분의 1) 모든 텍스처에 밉맵을 넣어 둔다.
## 색 띠(ramp)·LUT·얼굴 그림자 지도(SDF)·마스크는 압축 자국이 그대로 보이므로(그림자 경계가 계단 모양) 두고 넣는다.
## 장면 구조는 게임이 glb를 직접 읽을 때와 같다(같은 CharacterAppearance.read_gltf를 쓴다).
##
## 쓰는 법 (tools/publish_assets.py가 에셋을 올리기 전에 부른다):
##   godot --headless --path . --script res://tools/bake_models.gd -- <원본.glb> <결과.scn> [<원본.glb> <결과.scn> ...]

## 압축하는 이미지 이름의 끝: 색(_D), 설정(_P), 법선(_N, 머리카락 _HN), 발광(_E)
const COMPRESSED_SUFFIXES: Array[String] = ["_D", "_P", "_N", "_HN", "_E"]
## 이보다 작은 그림은 압축하지 않는다(얻는 것이 적다).
const MIN_SIZE := 512


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var failed := args.is_empty() or args.size() % 2 != 0
	for i in range(0, args.size() - 1, 2):
		if not _bake(args[i], args[i + 1]):
			failed = true
	quit(1 if failed else 0)


func _bake(source: String, target: String) -> bool:
	var started := Time.get_ticks_msec()
	var root := CharacterAppearance.read_gltf(source)
	if root == null:
		printerr("모델을 읽지 못했습니다: ", source)
		return false
	# 텍스처 → 이름. 재질이 쓰는 텍스처도 모은다(이미지 목록의 이름이 겹치거나 비었을 수 있다).
	var names := {}
	var images: Dictionary = root.get_meta(&"images", {})
	for image_name: String in images:
		if images[image_name] is ImageTexture:
			names[images[image_name]] = image_name
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as BaseMaterial3D
			if material == null:
				continue
			for slot in BaseMaterial3D.TEXTURE_MAX:
				var texture := material.get_texture(slot) as ImageTexture
				if texture != null and not names.has(texture):
					names[texture] = texture.resource_name
	var compressed := 0
	for texture: ImageTexture in names:
		var image := texture.get_image()
		if image == null or image.is_empty() or image.is_compressed():
			continue
		if not image.has_mipmaps():
			image.generate_mipmaps()
		if _should_compress(str(names[texture]), image) and image.compress(Image.COMPRESS_BPTC) == OK:
			compressed += 1
		texture.set_image(image)
	var scene := PackedScene.new()
	var error := scene.pack(root)
	root.free()
	if error != OK:
		printerr("장면을 묶지 못했습니다 (%s): %s" % [error_string(error), source])
		return false
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	error = ResourceSaver.save(scene, target, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		printerr("저장하지 못했습니다 (%s): %s" % [error_string(error), target])
		return false
	print("%s → %s: 텍스처 %d개 중 %d개 압축, %.1fMB, %d ms" % [source.get_file(), target.get_file(), names.size(), compressed,
			FileAccess.get_file_as_bytes(target).size() / 1e6, Time.get_ticks_msec() - started])
	return true


static func _should_compress(image_name: String, image: Image) -> bool:
	if image.get_width() < MIN_SIZE or image.get_height() < MIN_SIZE:
		return false
	for suffix in COMPRESSED_SUFFIXES:
		if image_name.ends_with(suffix):
			return true
	return false
