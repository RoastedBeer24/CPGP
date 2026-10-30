class_name RunStage
extends Resource
## 작전 한 단계(방 하나): 불러올 구역과 웨이브.

@export var title := ""
@export_file("*.tscn") var scene_path := "res://src/zones/combat_room/combat_room.tscn"
## 웨이브마다 나오는 적 종류(data/enemies의 파일 이름)
@export var waves: Array[PackedStringArray] = []
## 보스 방이면 true (화면 위에 보스 체력이 나온다)
@export var boss := false
