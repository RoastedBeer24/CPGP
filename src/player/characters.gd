class_name Characters
extends RefCounted
## 고를 수 있는 캐릭터 목록. 메뉴에서 고르고, 코옵에서는 각자 고른 캐릭터로 들어간다.

const DEFAULT_ID := &"endministrator_f"
const PATHS: Array[String] = [
	"res://data/characters/endministrator_f/character.tres",
	"res://data/characters/endministrator_m/character.tres",
	"res://data/characters/akekuri/character.tres",
]


static func all() -> Array[CharacterData]:
	var found: Array[CharacterData] = []
	for path in PATHS:
		var character := load(path) as CharacterData
		if character != null:
			found.append(character)
	return found


## 이름으로 찾는다. 없는 이름이면 기본 캐릭터다.
static func find(id: StringName) -> CharacterData:
	var fallback: CharacterData = null
	for character in all():
		if character.id == id:
			return character
		if character.id == DEFAULT_ID:
			fallback = character
	return fallback
