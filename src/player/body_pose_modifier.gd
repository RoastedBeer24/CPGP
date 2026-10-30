class_name BodyPoseModifier
extends SkeletonModifier3D
## 애니메이션이 뼈에 적용된 직후에 PlayerBody가 자세를 덧입히게 하는 연결 노드.
## 애니메이션과 같은 프레임 안에서 순서를 보장하려면 뼈대의 수정자(modifier)로 끼워야 한다.

var body: PlayerBody


func _process_modification() -> void:
	if body != null and is_instance_valid(body) and body.is_inside_tree() and body.visible:
		body.apply_overlays()
