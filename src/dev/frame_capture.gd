class_name FrameCapture
extends Node
## 화면 확인용: 정한 프레임마다 화면을 PNG로 저장하고, 마지막 것을 저장하면 게임을 끝낸다.
## 화면 녹화(--write-movie)는 모든 프레임을 저장해서 느리고 크다. 이펙트처럼 몇 장면을 연달아 볼 때 쓴다.
##   godot --path . --fixed-fps 60 --resolution 1280x720 -- --single --autoplay --capture=700,710,720 --capture-dir=build/screenshots/fx

## 저장할 프레임 번호(오름차순)와 저장할 폴더
var frames := PackedInt32Array()
var directory := "build/screenshots"

var _frame := 0


func _process(_delta: float) -> void:
	_frame += 1
	if not frames.has(_frame):
		return
	var number := _frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	var image := get_viewport().get_texture().get_image()
	image.save_png(directory.path_join("frame_%05d.png" % number))
	if number >= frames[frames.size() - 1]:
		get_tree().quit()


## 명령줄(--capture=프레임,프레임 --capture-dir=폴더)로 만든다. 없으면 null.
static func from_command_line(args: PackedStringArray) -> FrameCapture:
	var capture: FrameCapture = null
	for arg in args:
		if arg.begins_with("--capture="):
			capture = FrameCapture.new()
			for part in arg.trim_prefix("--capture=").split(",", false):
				capture.frames.append(int(part))
			capture.frames.sort()
	if capture == null or capture.frames.is_empty():
		return null
	for arg in args:
		if arg.begins_with("--capture-dir="):
			capture.directory = arg.trim_prefix("--capture-dir=")
	return capture
