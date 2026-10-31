"""원본 캐릭터 glb에서 게임에 쓸 애니메이션만 남겨 가벼운 glb를 만든다.

    python3 tools/extract_character.py <원본.glb> <결과.glb>
    python3 tools/extract_character.py "!File/Endministrator_F_Animated.glb" assets/characters/endministrator_f/endministrator_f.glb
    python3 tools/extract_character.py "!File/endministrator_m/Endministrator_M_Animated.glb" assets/characters/endministrator_m/endministrator_m.glb

원본에는 애니메이션이 500~650개(약 450MB) 들어 있어서 그대로 쓰기에는 너무 크다.
모델(메시, 뼈대, 재질, 텍스처)은 그대로 두고, 아래 ROLES에 적은 애니메이션만 골라
게임에서 부르는 짧은 이름(idle, attack_1 등)으로 바꿔 넣는다.
관리자(여)와 관리자(남)는 동작 이름의 앞부분만 다르다(endminf/girl, endminm/boy). 원본에 든 이름을 보고 고른다.
결과 파일은 재배포할 수 없는 모델이 들어 있으므로 저장소에 올리지 않는다(docs/assets.md).
"""
import json
import struct
import sys

# 캐릭터 전용 동작의 앞부분 → 그 캐릭터의 공통 동작(이동 등) 앞부분. karin은 아케쿠리(chr_0019_karin)다.
CHARACTERS = {"endminf": "girl", "endminm": "boy", "karin": "girl"}

# 게임에서 부르는 이름 -> 원본 애니메이션 이름 후보({char}: endminf/endminm/karin, {Char}: 첫 글자를 대문자로,
# {body}: girl/boy). 앞의 것부터 찾는다. 아케쿠리는 캐릭터 화면 동작이 "A_actor_Karin_ui_..._01"이다.
# 동작을 더 쓰려면 여기에 추가한다. 원래 속도(제자리에서 걸을 때 발이 뒤로 가는 속도): walk 약 1.0, run 4.3, sprint 6.2 m/s
ROLES = {
    "idle": ["A_actor_{body}_idle_loop"],
    "walk": ["A_actor_{body}_walk_loop"],
    "run": ["A_actor_{body}_run_loop"],
    "sprint": ["A_actor_{body}_sprint_loop"],
    # 전투 대기: 싸우는 중에 서 있을 때
    "battle_idle": ["A_actor_{char}_battle_loop"],
    # 점프: 도약(제자리, 달리며) -> 낙하 -> 착지(제자리, 달리며)
    "jump_idle": ["A_actor_{body}_idle_jump_start_l", "A_actor_{char}_idle_jump_start_l"],
    "jump_run": ["A_actor_{body}_run_jump_start_l", "A_actor_{body}_run_jump_start_l_02"],
    "fall": ["A_actor_{body}_fall_loop_l"],
    "land": ["A_actor_{body}_idle_jump_land_l"],
    "run_land": ["A_actor_{body}_run_jump_land_l"],
    "jump_sprint": ["A_actor_{body}_sprint_jump_start_l", "A_actor_{body}_sprint_jump_start_l_02"],
    "sprint_land": ["A_actor_{body}_sprint_jump_land_l"],
    # 높은 곳에서 떨어져 무릎을 굽히며 착지
    "land_heavy": ["A_actor_{body}_idle_jump_land_heavy_l"],
    # 달리다·질주하다 멈추기 (어느 발이 앞일 때 멈추는지에 따라 둘)
    "run_stop_l": ["A_actor_{body}_run_stop_l"],
    "run_stop_r": ["A_actor_{body}_run_stop_r"],
    "sprint_stop_l": ["A_actor_{char}_sprint_stop_l", "A_actor_{body}_sprint_stop_l"],
    "sprint_stop_r": ["A_actor_{char}_sprint_stop_r", "A_actor_{body}_sprint_stop_r"],
    # 대기: 오래 서 있으면 쉬는 자세로 바뀌고(relax_in → relax), 가끔 특수 대기 동작을 한다.
    "relax_in": ["A_actor_{char}_idle_to_relax"],
    "relax": ["A_actor_{char}_relax_loop"],
    "relax_sp_1": ["A_actor_{char}_relax_sp_01"],
    "relax_sp_2": ["A_actor_{char}_relax_sp_02"],
    # 무기 꺼내기(전투 시작)와 거두기(전투 끝)
    "draw": ["A_actor_{char}_idle_to_battle"],
    "sheathe": ["A_actor_{char}_battle_to_idle"],
    # 캐릭터 화면: 들어오기 → 대기, 쓰다듬기 반응, 무기 보기(왼손에 무기를 든다) ↔ 대기
    "ui_enter": ["A_actor_{char}_ui_overview_start", "A_actor_{Char}_ui_overview_start_01"],
    "ui_idle": ["A_actor_{char}_ui_overview_loop", "A_actor_{Char}_ui_overview_loop_01"],
    "ui_react": ["A_actor_{char}_ui_relax_react", "A_actor_{char}_relax_react"],
    "ui_to_weapon": ["A_actor_{char}_ui_overview_to_weapon", "A_actor_{Char}_ui_overview_to_weapon_01"],
    "ui_weapon": ["A_actor_{char}_ui_overview_weapon_loop", "A_actor_{Char}_ui_overview_weapon_loop_01"],
    "ui_weapon_out": ["A_actor_{char}_ui_weapon_to_overview", "A_actor_{Char}_ui_weapon_to_overview_01"],
    # 회피: 캐릭터 전용 동작이 없으면(아케쿠리) 공통 동작
    "dodge_f": ["A_actor_{char}_battle_dodge_f_l", "A_actor_{body}_battle_dodge_f_l"],
    "dodge_b": ["A_actor_{char}_battle_dodge_b_l", "A_actor_{body}_battle_dodge_b_l"],
    # 기본 공격 5단계, 대시 공격, 처형(강공격), 배틀 스킬, 궁극기. 타격 시각과 내디딤 거리는 data/kits/*.tres에 있다.
    "attack_1": ["A_actor_{char}_battle_attack_01"],
    "attack_2": ["A_actor_{char}_battle_attack_02"],
    "attack_3": ["A_actor_{char}_battle_attack_03"],
    "attack_4": ["A_actor_{char}_battle_attack_04"],
    "attack_5": ["A_actor_{char}_battle_attack_05"],
    # 대시 공격(회피 직후 공격)은 원작 연계 스킬(크게 내달리며 베기, 소리·보이스·이펙트가 있다)을 쓴다.
    "dash_attack": ["A_actor_{char}_battle_combo_skill"],
    "finisher": ["A_actor_{char}_battle_power_attack"],
    "skill": ["A_actor_{char}_battle_normal_skill"],
    "ultimate": ["A_actor_{char}_battle_skill_ult"],
    # 낙하 공격: 공중에서 뛰어올랐다가 내리꽂고(시작) → 떨어지는 동안(반복) → 땅에 닿으며 내려친다(착지)
    "plunge_start": ["A_actor_{char}_battle_air_atk_start"],
    "plunge_loop": ["A_actor_{char}_battle_air_atk_loop"],
    "plunge_end": ["A_actor_{char}_battle_air_atk_end"],
    # 맞음: 가볍게 움찔(맞은 쪽: 앞·뒤·왼쪽·오른쪽), 크게 휘청, 쓰러짐
    "hit_f": ["A_actor_{body}_battle_hit_f"],
    "hit_b": ["A_actor_{body}_battle_hit_b"],
    "hit_l": ["A_actor_{body}_battle_hit_l"],
    "hit_r": ["A_actor_{body}_battle_hit_r"],
    "hit_heavy": ["A_actor_{char}_battle_hit_heavy"],
    "dead": ["A_actor_{char}_battle_dead"],
}

# 캐릭터에 따라 없는 동작. 없으면 넣지 않는다(아케쿠리는 기본 공격이 4단계이고 대시 공격이 없다).
OPTIONAL_ROLES = {"attack_5", "dash_attack"}

# 루프로 재생할 동작 (glTF에는 반복 여부가 없어서 이름 끝에 -loop를 붙이면 Godot가 반복으로 가져온다)
LOOPING = {"idle", "walk", "run", "sprint", "battle_idle", "fall", "relax", "ui_idle", "ui_weapon", "plunge_loop"}

# 모든 동작에서 움직임을 빼는 뼈(눈동자). 원본의 대화·전투 동작은 오른쪽 눈 뼈만 2~6도씩 움직여서
# (왼쪽은 그대로) 한쪽 눈만 돌아간다. 원래 게임은 시선을 따로 정하는 것으로 보여, 눈은 처음 자세(정면)로 둔다.
FROZEN_BONES = {
    "eyeLfJoint", "eyeRtJoint", "faceLfIrisJoint", "faceRtIrisJoint",
    "faceLfPupilJoint", "faceRtPupilJoint", "faceLfHighlightJoint", "faceRtHighlightJoint",
}

# 앞부분만 잘라 쓸 동작: 게임 이름 -> (시작 초, 끝 초). 원본 공격은 휘두른 뒤 긴 마무리가 붙어 있다.
# 끝은 data/kits의 동작 길이(duration)보다 조금 길게 둔다(동작이 끝난 뒤 섞여 넘어가는 동안 쓴다).
TRIMS = {
    # 1타는 몸을 160도쯤 돌렸다가 1.2~1.4초에 앞으로 돌아온다. 이어 치지 않으면 돌아오는 데까지 보여 준다.
    "attack_1": (0.0, 1.5),
    "attack_2": (0.0, 1.1),
    "attack_3": (0.0, 1.2),
    "attack_4": (0.0, 1.3),
    "attack_5": (0.0, 1.45),
    "dash_attack": (0.0, 1.3),  # 연계 스킬
    "finisher": (0.0, 1.6),
    "skill": (0.0, 1.3),
    "ultimate": (0.0, 3.9),
    "dodge_f": (0.0, 0.6),
    "dodge_b": (0.0, 0.7),
    "hit_heavy": (0.0, 1.0),
    # 원본 착지는 5초 넘게 이어지지만 1초쯤이면 일어선다.
    "plunge_end": (0.0, 1.6),
}
# 캐릭터마다 다른 구간
TRIM_OVERRIDES = {
    "endminm": {"ultimate": (0.0, 3.3)},
    # 아케쿠리: 4타가 마무리 일격(0.6초에 3.9m 내닫기), 궁극기는 세 번째 폭발(3.97초) 뒤까지
    "karin": {"attack_1": (0.0, 1.0), "attack_2": (0.0, 1.1), "attack_3": (0.0, 1.2), "attack_4": (0.0, 1.4),
              "finisher": (0.0, 1.7), "skill": (0.0, 1.3), "ultimate": (0.0, 4.4), "dash_attack": (0.0, 1.5)},
}

# 제자리 동작으로 바꿀 것. 원본 공격·회피는 내디디며 몸(뿌리 뼈)이 앞으로 1~4m 나가지만,
# 게임에서는 플레이어가 직접 움직이므로 뿌리 뼈의 수평 이동을 없앤다(높이는 둔다).
# 멈추기 동작도 원본은 1m쯤 미끄러지며 서지만, 게임에서는 몸(캡슐)이 스스로 멈춘다.
# 캐릭터 화면에 들어오는 동작(ui_enter)은 1.6m 앞에서 걸어 들어와 제자리에서 끝나므로 그대로 둔다.
ROOT_LOCKED = {
    "attack_1", "attack_2", "attack_3", "attack_4", "attack_5", "dash_attack", "finisher", "skill", "ultimate",
    "dodge_f", "dodge_b", "hit_heavy", "dead", "run_stop_l", "run_stop_r", "sprint_stop_l", "sprint_stop_r",
    "plunge_start", "plunge_end",
}
# 뿌리 뼈의 좌우 회전(위에서 본 방향)도 없앨 것. 원본 공격은 몸을 크게 돌리며 휘두르고, 5타처럼 180도 돌아간 채
# 끝나기도 한다(원작은 이 회전으로 캐릭터를 돌린다). 동작 안에 두면 동작이 끝날 때 몸이 원래 방향으로 튀므로,
# 회전을 빼고 같은 각도를 AttackData.turn에 넣어 플레이어가 직접 돈다(tools/measure_attack_clips.py --turn).
TURN_LOCKED = {
    "attack_1", "attack_2", "attack_3", "attack_4", "attack_5", "dash_attack", "finisher", "skill", "ultimate",
    "plunge_end",
}
# 뿌리 뼈의 높이도 없애고 다른 동작의 처음 높이로 고정할 것. 원본 낙하 공격 시작은 몸(뿌리 뼈)이 공중 1.8m에서
# 1.6m 더 뛰어올랐다가 7m 아래로 내리꽂는다(원작은 이 움직임으로 캐릭터를 옮긴다). 게임에서는 플레이어(캡슐)가
# 직접 뛰어오르고 내리꽂으므로(AttackData.rise) 몸은 떨어지는 동작(plunge_loop)의 높이에 둔다.
ROOT_HEIGHT_FROM = {"plunge_start": "plunge_loop"}
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


def root_height(doc, data, anim):
    """동작의 처음 뿌리 뼈 높이(이동 값의 y). 뿌리 뼈 이동이 없으면 None."""
    nodes = doc["nodes"]
    for c in anim["channels"]:
        if nodes[c["target"]["node"]].get("name") == ROOT_BONE and c["target"]["path"] == "translation":
            return read_floats(doc, data, anim["samplers"][c["sampler"]]["output"])[0][1]
    return None


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz]


def qinv(q):
    return [-q[0], -q[1], -q[2], q[3]]


def yaw_part(q):
    """회전에서 세상의 위쪽(Y) 축 둘레 회전(twist)만 뗀다."""
    length = (q[1] * q[1] + q[3] * q[3]) ** 0.5
    if length < 1e-8:
        return [0.0, 0.0, 0.0, 1.0]
    return [0.0, q[1] / length, 0.0, q[3] / length]


def parent_rotation(doc, bone_name):
    """뼈의 부모들이 가진 (움직이지 않는) 회전을 곱한 것. 뼈의 회전 값을 세상 기준으로 바꿀 때 쓴다."""
    nodes = doc["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    index = next(i for i, n in enumerate(nodes) if n.get("name") == bone_name)
    chain = []
    i = parent.get(index)
    while i is not None:
        chain.append(i)
        i = parent.get(i)
    rotation = [0.0, 0.0, 0.0, 1.0]
    for i in reversed(chain):
        rotation = qmul(rotation, nodes[i].get("rotation", [0.0, 0.0, 0.0, 1.0]))
    return rotation


def reshape(doc, data, anim, trim, lock_root, fixed_height=None, lock_turn=False, root_parent=None):
    """동작을 [시작, 끝] 구간으로 자르고(시간은 0부터), lock_root면 뿌리 뼈의 수평 이동을 없앤다.
    fixed_height가 있으면 뿌리 뼈의 높이도 그 값으로 고정한다. lock_turn이면 뿌리 뼈가 처음보다 좌우로 돈 만큼
    (세상 위쪽 축 둘레 회전)을 뺀다. 기울기·뒤집기는 그대로 둔다."""
    nodes = doc["nodes"]
    root_samplers = {c["sampler"] for c in anim["channels"]
                     if nodes[c["target"]["node"]].get("name") == ROOT_BONE and c["target"]["path"] == "translation"}
    turn_samplers = {c["sampler"] for c in anim["channels"]
                     if nodes[c["target"]["node"]].get("name") == ROOT_BONE and c["target"]["path"] == "rotation"}
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
            values = [[0.0, v[1] if fixed_height is None else fixed_height, 0.0] for v in values]
        if lock_turn and index in turn_samplers and values:
            # 세상 기준 회전 = 부모 회전 × 뼈 회전. 처음 열쇠에서 돈 만큼(twist)을 세상 기준으로 빼고 다시 뼈 기준으로.
            parent = root_parent or [0.0, 0.0, 0.0, 1.0]
            start_inv = qinv(qmul(parent, values[0]))
            reshaped = []
            for v in values:
                world = qmul(parent, v)
                turn = yaw_part(qmul(world, start_inv))
                reshaped.append(qmul(qinv(parent), qmul(qinv(turn), world)))
            values = reshaped
        sampler["input"] = add_floats(doc, data, [[t] for t in times], "SCALAR")
        sampler["output"] = add_floats(doc, data, values, doc["accessors"][sampler["output"]]["type"])


def freeze(doc, anim):
    """FROZEN_BONES를 움직이는 채널을 뺀다. 남은 채널이 쓰는 샘플러만 남기고 번호를 다시 매긴다."""
    nodes = doc["nodes"]
    channels = [c for c in anim["channels"] if nodes[c["target"]["node"]].get("name") not in FROZEN_BONES]
    used = sorted({c["sampler"] for c in channels})
    remap = {old: new for new, old in enumerate(used)}
    anim["samplers"] = [anim["samplers"][old] for old in used]
    for channel in channels:
        channel["sampler"] = remap[channel["sampler"]]
    anim["channels"] = channels


def strip_extra_meshes(doc):
    """먼 거리용 저해상도 메시 묶음(lod1~3)과 그림자 대용 메시(shadowProxy)를 뺀다. 게임은 가장 고운 메시(lod0)만
    그리는데, 아케쿠리 원본에는 이것들이 같은 자리에 함께 들어 있어 겹쳐 보인다. 쓰이지 않게 된 메시도 지운다."""
    nodes = doc["nodes"]
    dropped = set()

    def drop(index):
        dropped.add(index)
        for child in nodes[index].get("children", []):
            drop(child)

    for i, node in enumerate(nodes):
        name = node.get("name", "")
        if name in ("lod1", "lod2", "lod3") or "shadowProxy" in name:
            drop(i)
    if not dropped:
        return
    for node in nodes:
        if "children" in node:
            node["children"] = [c for c in node["children"] if c not in dropped]
    for scene in doc.get("scenes", []):
        scene["nodes"] = [n for n in scene.get("nodes", []) if n not in dropped]
    for i in dropped:
        nodes[i].pop("mesh", None)
        nodes[i].pop("skin", None)
    used = sorted({n["mesh"] for n in nodes if "mesh" in n})
    remap = {old: new for new, old in enumerate(used)}
    doc["meshes"] = [doc["meshes"][i] for i in used]
    for node in nodes:
        if "mesh" in node:
            node["mesh"] = remap[node["mesh"]]
    print("저해상도·그림자 대용 노드 %d개를 뺐습니다" % len(dropped))


def pick_character(by_name):
    """원본에 든 동작 이름을 보고 어느 캐릭터인지 정한다."""
    for char in CHARACTERS:
        if "A_actor_%s_battle_attack_01" % char in by_name:
            return char
    sys.exit("알고 있는 캐릭터(관리자 여·남, 아케쿠리)의 전투 동작이 없는 원본입니다")


def main(source, target):
    doc, data = read_glb(source)
    data = bytearray(data)
    by_name = {a.get("name"): a for a in doc.get("animations", [])}
    char = pick_character(by_name)
    names = {}
    missing = []
    for role, candidates in ROLES.items():
        found = [c.format(char=char, Char=char.capitalize(), body=CHARACTERS[char]) for c in candidates]
        found = [c for c in found if c in by_name]
        if found:
            names[role] = found[0]
        elif role not in OPTIONAL_ROLES:
            missing.append(role)
    if missing:
        sys.exit("원본에 없는 애니메이션: " + ", ".join(missing))
    trims = dict(TRIMS)
    trims.update(TRIM_OVERRIDES.get(char, {}))
    root_parent = parent_rotation(doc, ROOT_BONE)

    animations = []
    for role, name in names.items():
        anim = json.loads(json.dumps(by_name[name]))
        anim["name"] = role + ("-loop" if role in LOOPING else "")
        if role in trims or role in ROOT_LOCKED:
            height = None
            if role in ROOT_HEIGHT_FROM:
                height = root_height(doc, data, by_name[names[ROOT_HEIGHT_FROM[role]]])
            reshape(doc, data, anim, trims.get(role), role in ROOT_LOCKED, height, role in TURN_LOCKED, root_parent)
        freeze(doc, anim)
        animations.append(anim)
    doc["animations"] = animations
    strip_extra_meshes(doc)

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
