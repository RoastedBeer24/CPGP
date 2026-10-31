class_name GltfMipmaps
extends GLTFDocumentExtension
## 실행 중에 읽는 glTF의 그림(PNG·JPEG·WebP)을 풀어 텍스처로 만들기 전에 밉맵을 넣는다. 실행 중에 읽은 텍스처에는
## 밉맵이 없어 멀리서 보면 자글거린다.
## 예전에는 텍스처를 다 만든 뒤 get_image()로 다시 꺼내 밉맵을 넣었다. 그 꺼내기는 렌더링 서버의 답을 기다리는
## 호출이라 배경 스레드(AssetPreloader)에서 쓰면 주 스레드와 서로 기다리다 멈출 수 있어서, 그림을 풀 때 넣는다.
## 게임에서 glTF를 읽기 전에 ensure_registered()를 부른다(모든 GLTFDocument에 적용된다).

static var _registered := false


static func ensure_registered() -> void:
	if _registered:
		return
	_registered = true
	GLTFDocument.register_gltf_document_extension(GltfMipmaps.new(), true)


func _parse_image_data(_state: GLTFState, image_data: PackedByteArray, mime_type: String, ret_image: Image) -> Error:
	var error := OK
	match mime_type:
		"image/png":
			error = ret_image.load_png_from_buffer(image_data)
		"image/jpeg":
			error = ret_image.load_jpg_from_buffer(image_data)
		"image/webp":
			error = ret_image.load_webp_from_buffer(image_data)
		_:
			# 다른 형식은 엔진에 맡긴다 (그림을 비워 두면 엔진이 직접 푼다).
			return OK
	if error != OK or ret_image.is_empty():
		return OK
	if not ret_image.is_compressed() and not ret_image.has_mipmaps():
		ret_image.generate_mipmaps()
	return OK
