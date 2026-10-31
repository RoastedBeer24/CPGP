"""원본 캐릭터 glb의 공격 동작에서 몸(뿌리 뼈 Bip001)이 앞으로 나아간 거리와 무기가 가장 빠른 순간(타격 시각)을 잰다.
data/characters/*/kit.tres의 advance(내디딤)와 hits의 time을 정할 때 쓴다.

    python3 tools/measure_attack_clips.py "!File/Endministrator_F_Animated.glb" attack_01:1.4 normal_skill:1.6
    python3 tools/measure_attack_clips.py "!File/endministrator_m/Endministrator_M_Animated.glb" --prefix=A_actor_endminm_battle_ attack_01:1.4

동작 이름 뒤의 숫자는 몇 초까지 잴지다. 앞으로 나아간 거리는 0.05초마다, 무기 속도의 봉우리는 "시각(m/s)"로 찍는다.
"""
import json
import math
import struct
import sys

PREFIX = "A_actor_endminf_battle_"


def read_glb(path):
    with open(path, "rb") as f:
        f.read(12)
        json_len, _ = struct.unpack("<II", f.read(8))
        doc = json.loads(f.read(json_len))
        bin_len, _ = struct.unpack("<II", f.read(8))
        data = f.read(bin_len)
    return doc, data


def read_floats(doc, data, index):
    accessor = doc["accessors"][index]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    view = doc["bufferViews"][accessor["bufferView"]]
    stride = view.get("byteStride", width * 4)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [struct.unpack_from("<%df" % width, data, start + i * stride) for i in range(accessor["count"])]


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def qrot(q, v):
    x, y, z, w = q
    vx, vy, vz = v
    tx, ty, tz = 2 * (y * vz - z * vy), 2 * (z * vx - x * vz), 2 * (x * vy - y * vx)
    return (vx + w * tx + (y * tz - z * ty), vy + w * ty + (z * tx - x * tz), vz + w * tz + (x * ty - y * tx))


def slerp(a, b, t):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b = tuple(-x for x in b)
        dot = -dot
    if dot > 0.9995:
        r = tuple(x + (y - x) * t for x, y in zip(a, b))
    else:
        th = math.acos(dot)
        s = math.sin(th)
        r = tuple((math.sin((1 - t) * th) * x + math.sin(t * th) * y) / s for x, y in zip(a, b))
    n = math.sqrt(sum(x * x for x in r))
    return tuple(x / n for x in r)


def sample(times, values, t, rotation):
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    lo, hi = 0, len(times) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if times[mid] <= t:
            lo = mid
        else:
            hi = mid
    f = (t - times[lo]) / max(times[hi] - times[lo], 1e-9)
    if rotation:
        return slerp(values[lo], values[hi], f)
    return tuple(a + (b - a) * f for a, b in zip(values[lo], values[hi]))


def main(path, specs):
    doc, data = read_glb(path)
    nodes = doc["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    index = {n.get("name", ""): i for i, n in enumerate(nodes)}

    def chain(name):
        i = index[name]
        out = []
        while i is not None:
            out.append(i)
            i = parent.get(i)
        return list(reversed(out))

    chains = {"root": chain("Bip001"), "weapon": chain("IK_Weapon_R_001")}
    wanted = {PREFIX + spec.split(":")[0]: float(spec.split(":")[1]) for spec in specs}
    for anim in doc["animations"]:
        name = anim.get("name", "")
        if name not in wanted:
            continue
        end = wanted[name]
        tracks = {}
        for ch in anim["channels"]:
            sampler = anim["samplers"][ch["sampler"]]
            times = [v[0] for v in read_floats(doc, data, sampler["input"])]
            tracks[(ch["target"].get("node"), ch["target"]["path"])] = (times, read_floats(doc, data, sampler["output"]))

        def world_rotation(key, t):
            rot = (0.0, 0.0, 0.0, 1.0)
            for i in chains[key]:
                ro = tracks.get((i, "rotation"))
                ro = sample(*ro, t, True) if ro else nodes[i].get("rotation", [0, 0, 0, 1])
                rot = qmul(rot, tuple(ro))
            return rot

        def world(key, t):
            pos, rot, scale = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0)
            for i in chains[key]:
                n = nodes[i]
                tr = tracks.get((i, "translation"))
                ro = tracks.get((i, "rotation"))
                sc = tracks.get((i, "scale"))
                tr = sample(*tr, t, False) if tr else n.get("translation", [0, 0, 0])
                ro = sample(*ro, t, True) if ro else n.get("rotation", [0, 0, 0, 1])
                sc = sample(*sc, t, False) if sc else n.get("scale", [1, 1, 1])
                p = qrot(rot, (tr[0] * scale[0], tr[1] * scale[1], tr[2] * scale[2]))
                pos = (pos[0] + p[0], pos[1] + p[1], pos[2] + p[2])
                rot = qmul(rot, tuple(ro))
                scale = (scale[0] * sc[0], scale[1] * sc[1], scale[2] * sc[2])
            return pos

        step = 1.0 / 60.0
        root0 = world("root", 0.0)
        rows = []
        previous = None
        t = 0.0
        while t <= end + 1e-6:
            weapon = world("weapon", t)
            speed = math.dist(weapon, previous) / step if previous is not None else 0.0
            previous = weapon
            # 모델은 +Z를 앞으로 본다. 높이는 처음 자세에서 얼마나 떴는지다(낙하 공격처럼 뛰어오르는 동작).
            root = world("root", t)
            rows.append((t, root[2] - root0[2], speed, root[1] - root0[1]))
            t += step
        peaks = ["%.2f(%.0f)" % (rows[k][0], rows[k][2]) for k in range(2, len(rows) - 2)
                 if rows[k][2] > 9.0 and rows[k][2] >= max(rows[k - 2][2], rows[k - 1][2], rows[k + 1][2], rows[k + 2][2])]
        print("== %s (%.2f초까지)" % (name, end))
        print("  타격 후보:", " ".join(peaks))
        print("  앞으로:", " ".join("%.2f:%.2f" % (r[0], r[1]) for r in rows if int(round(r[0] * 60)) % 3 == 0))
        print("  높이:", " ".join("%.2f:%.2f" % (r[0], r[3]) for r in rows if int(round(r[0] * 60)) % 3 == 0))
        # 몸이 처음보다 좌우로 돈 각도(위에서 본 회전, 도). 세상 위쪽 축 둘레 회전(twist)만 재고, 360도를 넘어도 이어 센다.
        # 모델에서는 이 회전을 빼므로(tools/extract_character.py의 TURN_LOCKED) kit.tres의 turn에 그대로 넣는다.
        start_inv = world_rotation("root", 0.0)
        start_inv = (-start_inv[0], -start_inv[1], -start_inv[2], start_inv[3])
        turns = []
        previous = 0.0
        frame = 0
        while frame / 30.0 <= end + 1e-6:
            t = frame / 30.0
            r = qmul(world_rotation("root", t), start_inv)
            angle = math.degrees(2.0 * math.atan2(r[1], r[3]))
            angle += round((previous - angle) / 360.0) * 360.0
            previous = angle
            turns.append((t, angle))
            frame += 1
        print("  돎(도):", " ".join("%.2f:%.0f" % row for row in turns[::3]))
        print("  turn = PackedVector2Array(%s)" % ", ".join("%g, %g" % (round(t, 4), round(a, 1)) for t, a in turns))


if __name__ == "__main__":
    args = sys.argv[2:]
    if args and args[0].startswith("--prefix="):
        PREFIX = args[0].split("=", 1)[1]
        args = args[1:]
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], args)
