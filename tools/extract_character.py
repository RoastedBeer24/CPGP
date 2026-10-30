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
    # 웅크리기: 한쪽 무릎을 꿇은 자세. 슬라이딩도 이 자세 위에 다리를 코드로 얹는다.
    "crouch": "A_actor_endminf_dialog_state_squat1_loop",
    # 점프: 도약(제자리, 달리며) -> 낙하 -> 착지(제자리, 달리며)
    "jump_idle": "A_actor_girl_idle_jump_start_l",
    "jump_run": "A_actor_girl_run_jump_start_l",
    "fall": "A_actor_girl_fall_loop_l",
    "land": "A_actor_girl_idle_jump_land_l",
    "run_land": "A_actor_girl_run_jump_land_l",
    "dodge_f": "A_actor_endminf_battle_dodge_f_l",
    "dodge_b": "A_actor_endminf_battle_dodge_b_l",
    # 근접 공격 연속 동작(1 -> 2 -> 3). 원본은 휘두른 뒤 긴 마무리가 붙어 있어서 TRIMS로 앞부분만 쓴다.
    "melee_1": "A_actor_endminf_battle_attack_01",
    "melee_2": "A_actor_endminf_battle_attack_02",
    "melee_3": "A_actor_endminf_battle_attack_03",
    "hit": "A_actor_endminf_battle_hit_heavy",
    "dead": "A_actor_endminf_battle_dead",
}

# 루프로 재생할 동작 (glTF에는 반복 여부가 없어서 이름 끝에 -loop를 붙이면 Godot가 반복으로 가져온다)
LOOPING = {"idle", "walk", "run", "sprint", "crouch", "fall"}

# 앞부분만 잘라 쓸 동작: 게임 이름 -> (시작 초, 끝 초)
TRIMS = {
    "melee_1": (0.0, 0.8),  # 가로 베기
    "melee_2": (0.0, 0.9),  # 깊이 내디디며 찌르기
    "melee_3": (0.0, 0.8),  # 뛰어올랐다 내려 베기
}

# 제자리 동작으로 바꿀 것. 원본 공격은 내디디며 몸(뿌리 뼈)이 앞으로 1~4m 나가지만,
# 게임에서는 플레이어가 직접 움직이므로 뿌리 뼈의 수평 이동을 없앤다(높이는 둔다).
ROOT_LOCKED = {"melee_1", "melee_2", "melee_3"}
# 뿌리 뼈. 부모(Root)가 돌아가 있지 않아서 이동 값의 y가 위, x와 z가 수평이다.
ROOT_BONE = "Bip001"


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


def read_floats(doc, data, index):
    """accessor 하나를 [[값, ...], ...] 목록으로 읽는다. 원본 애니메이션은 전부 float이다."""
    accessor = doc["accessors"][index]
    if accessor.get("componentType") != 5126 or "sparse" in accessor:
        sys.exit("float이 아닌 애니메이션 값은 자를 수 없습니다")
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    view = doc["bufferViews"][accessor["bufferView"]]
    stride = view.get("byteStride", width * 4)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [list(struct.unpack_from("<%df" % width, data, start + i * stride)) for i in range(accessor["count"])]


def add_floats(doc, data, values, type_name):
    """값 목록을 버퍼 끝에 붙이고 새 accessor 번호를 돌려준다. 시간(SCALAR)에는 glTF가 요구하는 min/max를 단다."""
    flat = [x for value in values for x in value]
    data.extend(b"\0" * (-len(data) % 4))
    doc["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(flat) * 4})
    data.extend(struct.pack("<%df" % len(flat), *flat))
    accessor = {"bufferView": len(doc["bufferViews"]) - 1, "componentType": 5126, "count": len(values), "type": type_name}
    if type_name == "SCALAR":
        accessor["min"] = [min(v[0] for v in values)]
        accessor["max"] = [max(v[0] for v in values)]
    doc["accessors"].append(accessor)
    return len(doc["accessors"]) - 1


def reshape(doc, data, anim, trim, lock_root):
    """동작을 [시작, 끝] 구간으로 자르고(시간은 0부터), lock_root면 뿌리 뼈의 수평 이동을 없앤다."""
    nodes = doc["nodes"]
    root_samplers = {c["sampler"] for c in anim["channels"]
                     if nodes[c["target"]["node"]].get("name") == ROOT_BONE and c["target"]["path"] == "translation"}
    for index, sampler in enumerate(anim["samplers"]):
        if sampler.get("interpolation", "LINEAR") == "CUBICSPLINE":
            sys.exit("CUBICSPLINE 동작은 자를 수 없습니다: " + anim["name"])
        times = [t[0] for t in read_floats(doc, data, sampler["input"])]
        values = read_floats(doc, data, sampler["output"])
        if trim is not None and len(times) > 1:
            start, end = trim
            keep = [k for k, t in enumerate(times) if start - 1e-4 <= t <= end + 1e-4]
            if not keep:
                # 구간 안에 열쇠가 없으면 시작 직전 값 하나로 고정한다.
                keep = [max([k for k, t in enumerate(times) if t <= start] or [0])]
            times = [max(times[k] - start, 0.0) for k in keep]
            values = [values[k] for k in keep]
        if lock_root and index in root_samplers:
            values = [[0.0, v[1], 0.0] for v in values]
        sampler["input"] = add_floats(doc, data, [[t] for t in times], "SCALAR")
        sampler["output"] = add_floats(doc, data, values, doc["accessors"][sampler["output"]]["type"])


def main(source, target):
    doc, data = read_glb(source)
    data = bytearray(data)
    by_name = {a.get("name"): a for a in doc.get("animations", [])}
    missing = [name for name in ROLES.values() if name not in by_name]
    if missing:
        sys.exit("원본에 없는 애니메이션: " + ", ".join(missing))

    animations = []
    for role, name in ROLES.items():
        anim = json.loads(json.dumps(by_name[name]))
        anim["name"] = role + ("-loop" if role in LOOPING else "")
        if role in TRIMS or role in ROOT_LOCKED:
            reshape(doc, data, anim, TRIMS.get(role), role in ROOT_LOCKED)
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
