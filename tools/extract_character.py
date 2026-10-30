"""원본 캐릭터 glb에서 게임에 쓸 애니메이션만 남겨 가벼운 glb를 만든다.

    python3 tools/extract_character.py <원본.glb> <결과.glb>
    python3 tools/extract_character.py "!File/Endministrator_F_Animated.glb" assets/characters/endministrator_f/endministrator_f.glb

원본에는 애니메이션이 651개(약 450MB) 들어 있어서 그대로 쓰기에는 너무 크다.
모델(메시, 뼈대, 재질, 텍스처)은 그대로 두고, 아래 ROLES에 적은 애니메이션만 골라
게임에서 부르는 짧은 이름(idle, walk 등)으로 바꿔 넣는다.
결과 파일은 재배포할 수 없는 모델이 들어 있으므로 저장소에 올리지 않는다(docs/assets.md).
"""
import json
import struct
import sys

# 게임에서 부르는 이름 -> 원본 애니메이션 이름. 동작을 더 쓰려면 여기에 추가한다.
# 원래 속도(동작이 제자리에서 걸을 때 발이 뒤로 가는 속도): walk 약 1.0, run 4.3, sprint 6.2 m/s
ROLES = {
    "idle": "A_actor_girl_idle_loop",
    "walk": "A_actor_girl_walk_loop",
    "run": "A_actor_girl_run_loop",
    "sprint": "A_actor_girl_sprint_loop",
    # 점프: 도약(제자리, 달리며) -> 낙하 -> 착지(제자리, 달리며)
    "jump_idle": "A_actor_girl_idle_jump_start_l",
    "jump_run": "A_actor_girl_run_jump_start_l",
    "fall": "A_actor_girl_fall_loop_l",
    "land": "A_actor_girl_idle_jump_land_l",
    "run_land": "A_actor_girl_run_jump_land_l",
    "dodge_f": "A_actor_endminf_battle_dodge_f_l",
    "dodge_b": "A_actor_endminf_battle_dodge_b_l",
    "hit": "A_actor_endminf_battle_hit_heavy",
    "dead": "A_actor_endminf_battle_dead",
}

# 루프로 재생할 동작 (glTF에는 반복 여부가 없어서 이름 끝에 -loop를 붙이면 Godot가 반복으로 가져온다)
LOOPING = {"idle", "walk", "run", "sprint", "fall"}


def read_glb(path):
    with open(path, "rb") as f:
        magic, version, length = struct.unpack("<III", f.read(12))
        assert magic == 0x46546C67, "glb 파일이 아닙니다"
        json_len, json_type = struct.unpack("<II", f.read(8))
        doc = json.loads(f.read(json_len))
        bin_len, bin_type = struct.unpack("<II", f.read(8))
        data = f.read(bin_len)
    return doc, data


def write_glb(path, doc, data):
    text = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    data += b"\0" * (-len(data) % 4)
    total = 12 + 8 + len(text) + 8 + len(data)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A))
        f.write(text)
        f.write(struct.pack("<II", len(data), 0x004E4942))
        f.write(data)


def main(source, target):
    doc, data = read_glb(source)
    by_name = {a.get("name"): a for a in doc.get("animations", [])}
    missing = [name for name in ROLES.values() if name not in by_name]
    if missing:
        sys.exit("원본에 없는 애니메이션: " + ", ".join(missing))

    animations = []
    for role, name in ROLES.items():
        anim = json.loads(json.dumps(by_name[name]))
        anim["name"] = role + ("-loop" if role in LOOPING else "")
        animations.append(anim)
    doc["animations"] = animations

    # 쓰이는 accessor만 남기고 번호를 다시 매긴다.
    used = []
    def keep(index):
        if index is not None and index not in used:
            used.append(index)
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            for index in prim["attributes"].values():
                keep(index)
            keep(prim.get("indices"))
            for morph in prim.get("targets", []):
                for index in morph.values():
                    keep(index)
    for skin in doc.get("skins", []):
        keep(skin.get("inverseBindMatrices"))
    for anim in animations:
        for sampler in anim["samplers"]:
            keep(sampler["input"])
            keep(sampler["output"])
    accessor_map = {old: new for new, old in enumerate(used)}

    # 쓰이는 bufferView만 새 버퍼로 복사한다 (accessor와 이미지).
    views = doc["bufferViews"]
    view_map = {}
    new_views = []
    new_data = bytearray()
    def copy_view(old):
        if old in view_map:
            return view_map[old]
        view = dict(views[old])
        start = view.get("byteOffset", 0)
        chunk = data[start:start + view["byteLength"]]
        new_data.extend(b"\0" * (-len(new_data) % 4))
        view["byteOffset"] = len(new_data)
        view["buffer"] = 0
        new_data.extend(chunk)
        view_map[old] = len(new_views)
        new_views.append(view)
        return view_map[old]

    new_accessors = []
    for old in used:
        accessor = dict(doc["accessors"][old])
        if "bufferView" in accessor:
            accessor["bufferView"] = copy_view(accessor["bufferView"])
        new_accessors.append(accessor)
    for image in doc.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = copy_view(image["bufferView"])

    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            prim["attributes"] = {k: accessor_map[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = accessor_map[prim["indices"]]
            if "targets" in prim:
                prim["targets"] = [{k: accessor_map[v] for k, v in t.items()} for t in prim["targets"]]
    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = accessor_map[skin["inverseBindMatrices"]]
    for anim in animations:
        for sampler in anim["samplers"]:
            sampler["input"] = accessor_map[sampler["input"]]
            sampler["output"] = accessor_map[sampler["output"]]

    doc["accessors"] = new_accessors
    doc["bufferViews"] = new_views
    doc["buffers"] = [{"byteLength": len(new_data)}]
    write_glb(target, doc, bytes(new_data))
    print(f"{target}: 애니메이션 {len(animations)}개, {len(new_data) / 1e6:.1f}MB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
