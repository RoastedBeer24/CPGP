class_name Hackable
extends Node3D
## 해킹할 수 있는 대상에 붙이는 표시. 스캔 모드에서 이 위치에 표식이 뜨고, 정보와 퀵핵 목록을 보여 준다.
## 부모 노드가 is_hackable(), scan_lines(), apply_quickhack(hack, hacker)를 가지고 있어야 한다.
## 퀵핵의 효과 판정은 호스트에서 부모의 apply_quickhack이 한다.

const GROUP := &"hackables"

@export var display_name := ""
## 이 대상에 쓸 수 있는 퀵핵. 스캔 화면의 1~4번 키 순서다.
@export var quickhacks: Array[QuickhackData] = []


func _ready() -> void:
	add_to_group(GROUP)


func target() -> Node:
	return get_parent()


## 지금 해킹할 수 있는지 (쓰러진 적, 부서진 카메라는 안 됨)
func is_available() -> bool:
	return target().call("is_hackable")


## 스캔 화면에 보여 줄 정보 줄
func scan_lines() -> PackedStringArray:
	return target().call("scan_lines")
