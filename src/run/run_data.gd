class_name RunData
extends Resource
## 작전 하나: 차례로 깨는 방들. 마지막 방(최종 보스)을 깨면 작전 완료.

@export var display_name := ""
@export var stages: Array[RunStage] = []
