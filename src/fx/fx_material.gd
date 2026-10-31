class_name FxMaterial
extends RefCounted
## 원작 이펙트 재질 설정(glb 재질의 extras: VFXBaseV2의 floats, colors, vfx)을 vfx_base 셰이더 재질로 바꾼다.
##
## 샘플 슬롯(_SampleTex0~): 슬롯마다 왜곡·가중치·마스크·섞기·녹이기 중 어떤 역할인지가 재질 값으로 정해진다.
## 섞는 방식(_BlendMode 0 알파, 1 더하기), 뒷면(_CullMode), 깊이 비교(_ZTest 8은 항상 보임)는 render_mode라서
## 조합마다 셰이더를 따로 만든다(본문은 vfx_base.gdshaderinc).

const BODY := "res://src/fx/vfx_base.gdshaderinc"
## 원작 재질 자료가 비어 있는 화면 이펙트를 비슷하게 만든 셰이더: 화면 왜곡(VFXRefract), 방사 흐림(VFXRadialBlur)
const REFRACT_BODY := "res://src/fx/vfx_refract.gdshaderinc"
const BLUR_BODY := "res://src/fx/vfx_blur.gdshaderinc"
const REFRACT_SHADER := "HGRP/Effect/VFXRefract"
const BLUR_SHADER := "HGRP/Effect/VFXRadialBlur"
## 샘플 슬롯이 맡을 수 있는 역할(순서대로 번호 0~5)
const ROLE_NAMES: Array[String] = ["_DisturbTex1", "_DisturbTex2", "_WeightTex", "_MaskTex", "_BlendTex", "_DissolveTex"]
const MAX_SLOTS := 4
## 그리기 방식 (FxSystem과 셰이더의 draw_mode)
enum Draw { AXES, VIEW, STRETCH }

## render_mode 조합 → 셰이더
static var _shaders: Dictionary[String, Shader] = {}


## 그릴 수 있는 재질인지. VFXBaseV2만 그리고, 원작 계산을 모르는 기능(정점 밀기 등)을 쓰면 건너뛴다.
## 극좌표 UV(충격파 고리)는 판 가운데에서 잰 (각도, 거리)로 만든다.
static func supported(extras: Dictionary) -> bool:
	if str(extras.get("shader", "")) != "HGRP/Effect/VFXBaseV2":
		return false
	var keywords: Array = (extras.get("vfx", {}) as Dictionary).get("keywords", [])
	for keyword: String in keywords:
		if not (keyword.begins_with("_SAMPLE_TEX") or keyword in ["_USE_SOFTBLEND", "_USE_FOG", "_USE_POLARUV", "_USE_SCREENUV"]):
			return false
	return _slot_count(keywords) >= 0


## 재질 자료 없이 비슷하게 만드는 화면 이펙트의 셰이더 이름인지 (화면 왜곡, 방사 흐림)
static func screen_effect(shader_name: String) -> bool:
	return shader_name == REFRACT_SHADER or shader_name == BLUR_SHADER


## 화면 왜곡·방사 흐림 재질. 원작 재질 자료가 없어서 세기는 직접 정했고, 파티클 알파를 따른다.
static func build_screen_effect(shader_name: String, renderer: Dictionary, draw: int, mesh: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var body := BLUR_BODY if shader_name == BLUR_SHADER else REFRACT_BODY
	material.shader = _shader_with(body, false, 0, false)
	material.render_priority = clampi(int(renderer.get("sortingOrder", 0)), Material.RENDER_PRIORITY_MIN, Material.RENDER_PRIORITY_MAX)
	var pivot := _vector3(renderer.get("pivot", null))
	if mesh:
		pivot.x = -pivot.x
	material.set_shader_parameter(&"draw_mode", draw)
	material.set_shader_parameter(&"is_mesh", mesh)
	material.set_shader_parameter(&"pivot", pivot)
	material.set_shader_parameter(&"min_size", float(renderer.get("minSize", 0.0)))
	material.set_shader_parameter(&"max_size", float(renderer.get("maxSize", 0.5)))
	material.set_shader_parameter(&"length_scale", float(renderer.get("lengthScale", 2.0)))
	material.set_shader_parameter(&"velocity_scale", float(renderer.get("velocityScale", 0.0)))
	if body == REFRACT_BODY:
		material.set_shader_parameter(&"noise_texture", _noise())
	return material


static var _noise_texture: NoiseTexture2D


## 화면 왜곡에 쓰는 이어지는 잡음 그림
static func _noise() -> NoiseTexture2D:
	if _noise_texture == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.03
		_noise_texture = NoiseTexture2D.new()
		_noise_texture.noise = noise
		_noise_texture.seamless = true
		_noise_texture.width = 128
		_noise_texture.height = 128
		_noise_texture.generate_mipmaps = true
	return _noise_texture


## 재질 하나를 만든다. renderer는 파티클 시스템의 renderer 설정이다(피벗, 크기 제한 등은 시스템마다 다르다).
static func build(extras: Dictionary, effect: EffectLibrary.Effect, renderer: Dictionary, draw: int, mesh: bool, second_uv: bool) -> ShaderMaterial:
	var floats: Dictionary = extras.get("floats", {})
	var colors: Dictionary = extras.get("colors", {})
	var vfx: Dictionary = extras.get("vfx", {})
	var keywords: Array = vfx.get("keywords", [])
	var textures: Dictionary = vfx.get("textures", {})
	var st: Dictionary = vfx.get("st", {})
	var material := ShaderMaterial.new()
	var cull := int(floats.get("_CullMode", 2.0)) if draw == Draw.AXES else 0
	var ztest := int(floats.get("_ZTest", 4.0))
	var always_visible := ztest == 8 or ztest == 0 or float(floats.get("_DisableZTest", 0.0)) > 0.5
	material.shader = _shader(int(floats.get("_BlendMode", 0.0)) == 1, cull, always_visible)
	var priority := int(renderer.get("sortingOrder", 0)) + 20 * (int(extras.get("renderQueue", 3000)) - 3000)
	material.render_priority = clampi(priority, Material.RENDER_PRIORITY_MIN, Material.RENDER_PRIORITY_MAX)

	var pivot := _vector3(renderer.get("pivot", null))
	if mesh:
		pivot.x = -pivot.x
	material.set_shader_parameter(&"draw_mode", draw)
	material.set_shader_parameter(&"is_mesh", mesh)
	material.set_shader_parameter(&"pivot", pivot)
	material.set_shader_parameter(&"min_size", float(renderer.get("minSize", 0.0)))
	material.set_shader_parameter(&"max_size", float(renderer.get("maxSize", 0.5)))
	material.set_shader_parameter(&"length_scale", float(renderer.get("lengthScale", 2.0)))
	material.set_shader_parameter(&"velocity_scale", float(renderer.get("velocityScale", 0.0)))
	material.set_shader_parameter(&"vert_camera_offset", float(floats.get("_VertCameraOffset", 0.0)))
	material.set_shader_parameter(&"use_second_uv", second_uv)

	material.set_shader_parameter(&"tint_color", _linear(colors.get("_TintColor", null)))
	material.set_shader_parameter(&"tint_intensity", float(floats.get("_TintColorIntensity", 1.0)))
	material.set_shader_parameter(&"tint_alpha", float(floats.get("_TintColorAlpha", 1.0)))
	material.set_shader_parameter(&"disable_vert_color", float(floats.get("_DisableVertColor", 0.0)))

	var main := _texture(effect, textures.get("_MainTex", null))
	material.set_shader_parameter(&"main_tex", main[0])
	material.set_shader_parameter(&"main_clamp", main[1])
	material.set_shader_parameter(&"main_weights", _vector4(colors.get("_MainTexUVWeights", null), Vector4(1, 0, 0, 0)))
	material.set_shader_parameter(&"main_speed", _vector4(colors.get("_MainTexUVSpeed", null), Vector4.ZERO))
	material.set_shader_parameter(&"main_rot", _vector4(colors.get("_MainTexUVRotateMat", null), Vector4(1, 0, 0, 1)))
	material.set_shader_parameter(&"main_st", _vector4(st.get("_MainTex", null), Vector4(1, 1, 0, 0)))
	material.set_shader_parameter(&"main_as_alpha", float(floats.get("_UseMainTexAsAlpha", 0.0)))
	material.set_shader_parameter(&"main_use_disturb", float(floats.get("_MainTexUseDisturb", 0.0)))

	var count := mini(_slot_count(keywords), MAX_SLOTS)
	var weights := PackedVector4Array()
	var speeds := PackedVector4Array()
	var rots := PackedVector4Array()
	var sts := PackedVector4Array()
	var roles := PackedVector4Array()
	var dissolves := PackedFloat32Array()
	var as_alpha := PackedFloat32Array()
	var use_disturb := PackedFloat32Array()
	var clamps := PackedFloat32Array()
	for b in MAX_SLOTS:
		var role_weights := _role_weights(b, count, floats)
		var slot_st := Vector4.ZERO
		for k: int in role_weights:
			slot_st += float(role_weights[k]) * _vector4(st.get(ROLE_NAMES[k], null), Vector4(1, 1, 0, 0))
		if role_weights.is_empty():
			slot_st = Vector4(1, 1, 0, 0)
		weights.append(_vector4(colors.get("_SampleTex%dUVWeights" % b, null), Vector4(1, 0, 0, 0)))
		speeds.append(_vector4(colors.get("_SampleTex%dUVSpeed" % b, null), Vector4.ZERO))
		rots.append(_vector4(colors.get("_SampleTex%dUVRotateMat" % b, null), Vector4(1, 0, 0, 1)))
		sts.append(slot_st)
		var disturb_role := float(role_weights.get(b, 0.0)) if b < 2 else 0.0
		roles.append(Vector4(disturb_role, role_weights.get(2, 0.0), role_weights.get(3, 0.0), role_weights.get(4, 0.0)))
		dissolves.append(float(role_weights.get(5, 0.0)))
		as_alpha.append(float(floats.get("_UseSampleTex%dAsAlpha" % b, 0.0)))
		use_disturb.append(float(floats.get("_SampleTex%dUseDisturb" % b, 0.0)))
		var slot := _texture(effect, textures.get("_SampleTex%d" % b, null)) if b < count else [null, false]
		material.set_shader_parameter(StringName("slot%d" % b), slot[0])
		clamps.append(1.0 if slot[1] else 0.0)
	material.set_shader_parameter(&"slot_count", count)
	material.set_shader_parameter(&"slot_weights", weights)
	material.set_shader_parameter(&"slot_speed", speeds)
	material.set_shader_parameter(&"slot_rot", rots)
	material.set_shader_parameter(&"slot_st", sts)
	material.set_shader_parameter(&"slot_roles", roles)
	material.set_shader_parameter(&"slot_dissolve", dissolves)
	material.set_shader_parameter(&"slot_as_alpha", as_alpha)
	material.set_shader_parameter(&"slot_use_disturb", use_disturb)
	material.set_shader_parameter(&"slot_clamp", clamps)

	material.set_shader_parameter(&"use_disturb", float(floats.get("_UseDisturb", 0.0)))
	material.set_shader_parameter(&"use_disturb2", float(floats.get("_UseDisturb2", 0.0)))
	material.set_shader_parameter(&"bi_disturb", float(floats.get("_Bi_Disturb", 0.0)))
	material.set_shader_parameter(&"disturb1_normal", float(floats.get("_DisturbTex1Normal", 0.0)))
	material.set_shader_parameter(&"disturb2_normal", float(floats.get("_DisturbTex2Normal", 0.0)))
	material.set_shader_parameter(&"disturb_intensity", Vector4(float(floats.get("_DisturbUIntensity1", 0.0)),
			float(floats.get("_DisturbVIntensity1", 0.0)), float(floats.get("_DisturbUIntensity2", 0.0)),
			float(floats.get("_DisturbVIntensity2", 0.0))))
	material.set_shader_parameter(&"use_weight_tex", float(floats.get("_UseWeightTex", 0.0)))
	material.set_shader_parameter(&"weight_tex_intensity", float(floats.get("_WeightTexIntensity", 1.0)))
	material.set_shader_parameter(&"disturb_use_weight", float(floats.get("_DisturbUseWeight", 0.0)))
	material.set_shader_parameter(&"use_mask", float(floats.get("_UseMask", 0.0)))
	material.set_shader_parameter(&"blend_tint", _linear(colors.get("_BlendTint", null)))
	material.set_shader_parameter(&"use_dissolve", float(floats.get("_UseDissolve", 0.0)))
	material.set_shader_parameter(&"dissolve_use_weight", float(floats.get("_DissolveUseWeight", 0.0)))
	material.set_shader_parameter(&"dissolve_schedule_offset", float(floats.get("_DissolveScheduleOffset", 0.0)))
	material.set_shader_parameter(&"dissolve_emissive_edge", float(floats.get("_DissolveEmissiveEdge", 0.0)))
	material.set_shader_parameter(&"dissolve_edge_sharp", float(floats.get("_DissolveEdgeSharp", 1.0)))
	material.set_shader_parameter(&"dissolve_emissive_color", _linear(colors.get("_DissolveEmissiveColor", null)))
	material.set_shader_parameter(&"exp_threshold", float(floats.get("_ExpThreshold", 1.0)))
	material.set_shader_parameter(&"exp_intensity", float(floats.get("_ExpIntensity", 0.0)))
	material.set_shader_parameter(&"soft_enabled", keywords.has("_USE_SOFTBLEND"))
	material.set_shader_parameter(&"soft_bias", float(floats.get("_SoftBias", 0.0)))
	material.set_shader_parameter(&"soft_distance", float(floats.get("_SoftDistance", 1.0)))
	return material


## 샘플 슬롯 수(_SAMPLE_TEX0부터 이어진 것). 중간이 빠졌으면 -1.
static func _slot_count(keywords: Array) -> int:
	var count := 0
	while keywords.has("_SAMPLE_TEX%d" % count):
		count += 1
	for i in range(count, 6):
		if keywords.has("_SAMPLE_TEX%d" % i):
			return -1
	return count


## 슬롯 b가 맡는 역할마다 가중치: 역할 번호 → 0/1. 후보가 하나뿐이면 그 역할이다.
static func _role_weights(b: int, count: int, floats: Dictionary) -> Dictionary:
	var candidates: Array[int] = []
	if b < count:
		for k in range(b, mini(b + 6 - count, 5) + 1):
			if b == 0 and k == 1:
				continue
			candidates.append(k)
	var weights := {}
	for k in candidates:
		weights[k] = 1.0 if candidates.size() == 1 else float(floats.get("_SampleTex%dUseWeight%d" % [b, k], 0.0))
	return weights


## 재질의 텍스처 참조 {"index": glTF 텍스처 번호} → [Texture2D, 가장자리에서 멈추는지]
static func _texture(effect: EffectLibrary.Effect, reference: Variant) -> Array:
	if typeof(reference) != TYPE_DICTIONARY:
		return [null, false]
	var index := int((reference as Dictionary).get("index", -1))
	if index < 0 or index >= effect.textures.size():
		return [null, false]
	return [effect.textures[index], not effect.repeats[index]]


static func _shader(additive: bool, cull: int, always_visible: bool) -> Shader:
	return _shader_with(BODY, additive, cull, always_visible)


static func _shader_with(body: String, additive: bool, cull: int, always_visible: bool) -> Shader:
	var key := "%s|%s|%d|%s" % [body, additive, cull, always_visible]
	if _shaders.has(key):
		return _shaders[key]
	var modes: Array[String] = ["unshaded", "depth_draw_never", "fog_disabled", "shadows_disabled", "skip_vertex_transform"]
	modes.append("blend_add" if additive else "blend_mix")
	modes.append(["cull_disabled", "cull_front", "cull_back"][clampi(cull, 0, 2)])
	if always_visible:
		modes.append("depth_test_disabled")
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode %s;\n\n#include \"%s\"\n" % [", ".join(modes), body]
	_shaders[key] = shader
	return shader


## 원작 색(감마) → 선형. 1보다 큰 값(HDR)은 c^2.4로 바꾼다(사이트와 같은 규칙). 알파는 그대로.
static func _linear(values: Variant) -> Vector4:
	var c := _vector4(values, Vector4.ONE)
	return Vector4(_to_linear(c.x), _to_linear(c.y), _to_linear(c.z), c.w)


static func _to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	if c < 1.0:
		return pow((c + 0.055) / 1.055, 2.4)
	return pow(c, 2.4)


static func _vector4(values: Variant, fallback: Vector4) -> Vector4:
	if typeof(values) != TYPE_ARRAY or (values as Array).size() < 4:
		return fallback
	var list: Array = values
	return Vector4(float(list[0]), float(list[1]), float(list[2]), float(list[3]))


static func _vector3(values: Variant) -> Vector3:
	if typeof(values) != TYPE_ARRAY or (values as Array).size() < 3:
		return Vector3.ZERO
	var list: Array = values
	return Vector3(float(list[0]), float(list[1]), float(list[2]))
