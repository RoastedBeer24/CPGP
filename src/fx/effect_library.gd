class_name EffectLibrary
extends RefCounted
## 원작 이펙트를 캐릭터 꾸러미(zip, tools/extract_character_fx.py)에서 읽어 두고 플레이어끼리 함께 쓴다.
##
## 이펙트 하나는 glb(노드 계층, 메시, 텍스처, 재질 설정, 이펙트 자체 애니메이션)와 파티클 설정 JSON으로 되어 있다.
## glb의 노드에는 메시가 붙어 있지 않다. 원작은 노드마다 파티클 시스템이 있어서 그 파티클이 메시나 판(빌보드)을
## 그린다. 재질은 원작 전용 셰이더(VFXBaseV2 등)의 설정 값이 extras에 들어 있다.
## zip은 원작 자산이라 저장소에 없다(docs/assets.md). 없으면 이펙트 없이 돈다.


## 읽어 둔 이펙트 하나
class Effect:
	## 노드 계층과 이펙트 자체 애니메이션(AnimationPlayer). 뿌리 아래 첫 노드가 이펙트 이름이다.
	var scene: PackedScene
	## glTF 메시 번호 순
	var meshes: Array[Mesh] = []
	## glTF 텍스처 번호 순, 그리고 텍스처마다 반복(wrap)하는지
	var textures: Array[Texture2D] = []
	var repeats: Array[bool] = []
	## glTF 재질 번호 순: 재질 이름과 extras(셰이더 이름, floats, colors, vfx)
	var materials: Array[Dictionary] = []
	## 파티클 시스템 설정 (JSON의 systems). 시스템마다 붙을 노드의 경로(뿌리 기준)를 "node_path"에 넣어 둔다.
	var systems: Array[Dictionary] = []
	## 시스템 번호 → 그 시스템의 재질 (처음 틀 때 만들어 모든 재생이 함께 쓴다)
	var system_materials: Dictionary[int, ShaderMaterial] = {}


## zip 경로 + 이펙트 파일 → Effect (못 읽었으면 null도 기억해 다시 읽지 않는다). 배경 스레드(AssetPreloader)가
## 미리 읽어 두기도 한다.
static var _cache := SharedCache.new()


## 꾸러미에서 이펙트를 읽는다. 없거나 읽지 못하면 null.
static func load_effect(zip_path: String, glb_file: String, particles_file: String) -> Effect:
	return _cache.get_or_load("%s|%s" % [zip_path, glb_file], _read.bind(zip_path, glb_file, particles_file))


## 이미 읽어 둔 이펙트인지
static func is_loaded(zip_path: String, glb_file: String) -> bool:
	return _cache.has("%s|%s" % [zip_path, glb_file])


static func _read(zip_path: String, glb_file: String, particles_file: String) -> Effect:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return null
	var glb := reader.read_file("effects/" + glb_file)
	var particles := reader.read_file("effects/" + particles_file) if not particles_file.is_empty() else PackedByteArray()
	reader.close()
	return _parse(glb, particles) if not glb.is_empty() else null


static func _parse(glb: PackedByteArray, particles: PackedByteArray) -> Effect:
	GltfMipmaps.ensure_registered()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(glb, "", state) != OK:
		return null
	var effect := Effect.new()
	for gltf_mesh: GLTFMesh in state.get_meshes():
		effect.meshes.append(gltf_mesh.mesh.get_mesh() if gltf_mesh.mesh != null else null)
	var images := state.get_images()
	var samplers := state.get_texture_samplers()
	for gltf_texture: GLTFTexture in state.get_textures():
		# 밉맵은 그림을 풀 때 넣었다(GltfMipmaps). 멀리서 자글거리지 않게 한다.
		var image := images[gltf_texture.src_image] if gltf_texture.src_image >= 0 and gltf_texture.src_image < images.size() else null
		effect.textures.append(image)
		var repeat := true
		if gltf_texture.sampler >= 0 and gltf_texture.sampler < samplers.size():
			repeat = samplers[gltf_texture.sampler].wrap_s == 10497
		effect.repeats.append(repeat)
	for material: Dictionary in state.json.get("materials", []):
		effect.materials.append({"name": material.get("name", ""), "extras": material.get("extras", {})})
	var root := document.generate_scene(state)
	if root == null:
		return null
	var json := JSON.new()
	if not particles.is_empty() and json.parse(particles.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		for system: Dictionary in (json.data as Dictionary).get("systems", []):
			var node := state.get_scene_node(int(system.get("node", -1))) if int(system.get("node", -1)) >= 0 else null
			if node == null or not root.is_ancestor_of(node):
				continue
			system["node_path"] = root.get_path_to(node)
			effect.systems.append(system)
	for node: Node in root.find_children("*", "", true, false):
		node.owner = root
	effect.scene = PackedScene.new()
	var error := effect.scene.pack(root)
	root.free()
	return effect if error == OK else null
