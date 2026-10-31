"""원작 적 glb(<ID>_Animated.glb, 본 크러셔 꾸러미)에서 게임에 쓸 동작만 골라 가벼운 glb를 만든다.

    python3 tools/extract_enemy.py "!File/Bonekrusher_Assets/enemies/eny_0029_lbmob/eny_0029_lbmob_Animated.glb" assets/enemies/lbmob.glb

동작 이름은 게임이 부르는 역할 이름(idle, move, hit, stun_start, stun, dead, attack_1 ...)으로 바꾼다(EnemyData.clips가 이
이름을 쓴다). 원본 동작은 몸(뿌리 뼈 Bip001)이 앞으로 나가므로 모두 제자리로 묶는다. 적은 게임이 직접 움직인다
(이동 속도, 공격의 travel). 원래 이동 동작의 빠르기(m/s)를 찍으므로 EnemyData.move_clip_speed에 넣는다.
공격 동작은 몸이 앞으로 나아간 거리와 좌우로 돈 각도를 재어 그 모델을 쓰는 적 데이터(data/enemies/*.tres)의 공격마다
travel·turn으로 넣고, 모델 동작에서는 돈 각도도 뺀다. 게임이 그 곡선대로 적을 움직이고 모델을 돌린다(EnemyAttackData).
예전에는 공격이 맞는 순간 한꺼번에 밀어 줘서 순간이동처럼 보였고, 몸을 돌리는 공격은 끝날 때 휙 돌아갔다.
원작 소리가 있는 적(로댄)은 소리 꾸러미(<결과>_fx.zip)도 만든다(SOUNDS).
결과 파일은 재배포할 수 없는 모델이라 저장소에 올리지 않는다(docs/assets.md).
"""
import glob
import json
import math
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_character import (read_glb, read_floats, reshape, save_compact, strip_extra_meshes, parent_rotation,  # noqa: E402
                               ROOT_BONE)
import measure_attack_clips as measure  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 원본 동작 이름의 앞부분("A_monster_<이름>_") → 역할 → 원본 동작 이름의 나머지. 처형자 정예(eny_0068_lbtough2)는
# 처형자와 같은 동작(lbtough)을 쓴다. 로댄은 1형태(rodin_01)만 쓴다.
ENEMIES = {
    # 본 크러셔 약탈자 (eny_0029_lbmob)
    "lbmob": {"idle": "fightIdle", "move": "run", "hit": "hit_light_right", "stun_start": "hit_break_start",
              "stun": "hit_break_loop", "dead": "dead", "attack_1": "attack_01", "attack_2": "attack_02"},
    # 본 크러셔 저격수 (eny_0033_lbhunt): 원거리
    "lbhunt": {"idle": "fightidle", "move": "run", "hit": "hit_light_right", "stun_start": "hit_break_start",
               "stun": "hit_break_loop", "dead": "dead", "attack_1": "attack_01", "attack_2": "attack_02"},
    # 본 크러셔 처형자 (eny_0018_lbtough, 정예 eny_0068_lbtough2)
    "lbtough": {"idle": "fightidle", "move": "fightwalk", "hit": "hit_stagger_F", "stun_start": "hit_break_start",
                "stun": "hit_break_loop", "dead": "dead", "attack_1": "skill_01", "attack_2": "skill_03",
                "attack_3": "skill_05_01", "attack_4": "skill_09"},
    # '본 크러셔의 주먹' 로댄 (eny_0051_rodin)
    "rodin_01": {"idle": "fightidle", "move": "walk_f", "hit": "hit_light_middle", "stun_start": "hit_break_start",
                 "stun": "hit_break_loop", "dead": "dead", "attack_1": "skill_04", "attack_2": "skill01_01_attack",
                 "attack_3": "skill03_end", "attack_4": "skill06_01"},
}
LOOPING = {"idle", "move", "stun"}

# 원작 소리가 있는 적(꾸러미의 metadata/sounds.json): 소리 꾸러미(<결과>_fx.zip)도 만든다. 원작 소리는 일부 동작에만
# 있어서, 소리가 없는 동작은 비슷한 동작의 소리를 빌려 타격 시각에 맞춘다: 역할 → [(원본 동작, 구간 시작, 구간 끝,
# 옮길 시간(초))]. cue는 동작과 상관없이 내는 소리다(engage: 싸움을 걸 때, enrage: 격노할 때).
LANGUAGES = ["KR", "JP", "EN", "CN"]
SOUNDS = {
    "rodin_01": {
        "borrow": {
            # 내려찍기(skill_04, 2.33초에 내리꽂음): 시작할 때 외침, 내리꽂을 때 충격파 동작의 외침·충격
            "attack_1": [("A_monster_rodin_01_skill03_start", 0.0, 0.2, 0.7),
                         ("A_monster_rodin_01_skill03_end", 1.9, 2.5, -0.04)],
            # 휘두르기(skill01_01_attack, 0.47초): 두 번째 기술의 휘두르는 소리
            "attack_2": [("A_monster_rodin_01_skill_02_end1", 0.4, 0.5, 0.0)],
            # 충격파(skill03_end): 준비 동작의 외침을 예고가 시작할 때(clip_from 1.0초)
            "attack_3": [("A_monster_rodin_01_skill03_start", 0.0, 0.2, 1.0)],
            # 돌진(skill06_01, 2.32초): 휘두르는 소리
            "attack_4": [("A_monster_rodin_01_skill_02_end1", 1.3, 1.5, 0.92)],
        },
        "cues": {"engage": ("A_monster_rodin_01_taunt", 0.0, 1.0), "enrage": ("A_monster_rodin_02_taunt", 0.0, 1.5)},
    },
}


def pick_enemy(by_name):
    for prefix in ENEMIES:
        if "A_monster_%s_%s" % (prefix, ENEMIES[prefix]["idle"]) in by_name:
            return prefix
    sys.exit("알고 있는 적(약탈자, 저격수, 처형자, 로댄)의 동작이 없는 원본입니다")


def root_travel(doc, data, anim):
    """동작이 끝날 때까지 뿌리 뼈가 수평으로 움직인 거리(m)와 길이(초)."""
    nodes = doc["nodes"]
    for channel in anim["channels"]:
        if nodes[channel["target"]["node"]].get("name") == ROOT_BONE and channel["target"]["path"] == "translation":
            sampler = anim["samplers"][channel["sampler"]]
            times = read_floats(doc, data, sampler["input"])
            values = read_floats(doc, data, sampler["output"])
            dx, dz = values[-1][0] - values[0][0], values[-1][2] - values[0][2]
            return (dx * dx + dz * dz) ** 0.5, times[-1][0]
    return 0.0, 0.0


def build_sounds(source, prefix, target):
    """원작 소리 연결 정보로 소리 꾸러미를 만든다(fx.json + audio/*.wav, src/player/character_fx.gd가 읽는 형식).
    역할마다 그 동작 시각 기준의 소리·보이스를 담는다. 게임은 공격 동작을 예고 시간에 맞춘 빠르기로 틀므로 동작의
    재생 위치를 따라가며 소리를 낸다(EnemyBody)."""
    config = SOUNDS.get(prefix)
    folder = os.path.dirname(os.path.abspath(source))
    sounds_path = os.path.join(folder, "metadata", "sounds.json")
    if config is None or not os.path.isfile(sounds_path):
        return
    audio_dir = os.path.join(folder, "..", "..", "audio", "wav")
    file_of = {c["name"]: c["file"] for c in json.load(open(os.path.join(folder, "metadata", "clips.json"), encoding="utf-8"))}
    events_of = json.load(open(sounds_path, encoding="utf-8"))["clips"]
    audio_files = set()

    def keep(names):
        found = []
        for m4a in names:
            wav = os.path.splitext(m4a)[0] + ".wav"
            if os.path.isfile(os.path.join(audio_dir, wav)):
                found.append(wav)
                audio_files.add(wav)
        return found

    def collect(clip_name, start, end, shift, into):
        for event in events_of.get(file_of.get(clip_name, ""), []):
            time = event["time"] + event.get("delay", 0.0)
            if not start - 1e-4 <= time <= end + 1e-4:
                continue
            voice = event.get("voice")
            if voice:
                languages = {}
                for language in LANGUAGES:
                    choices = [{"weight": c.get("weight", 1), "files": keep(c.get("sounds", []))}
                               for c in voice.get("languages", {}).get(language, [])]
                    choices = [c for c in choices if c["files"]]
                    if choices:
                        languages[language] = choices
                if languages:
                    into["voices"].append({"time": round(time + shift, 4), "chance": voice.get("chance", 1.0),
                                           "cooldown": voice.get("cooldown", 0.0), "priority": voice.get("priority", 0),
                                           "languages": languages})
                continue
            files = keep(event.get("sounds", []))
            if files:
                into["sounds"].append({"time": round(time + shift, 4), "files": files, "mode": event.get("mode", "random"),
                                       "volume": event.get("volume", 1.0)})

    roles = {}
    for role, rest in ENEMIES[prefix].items():
        entry = {"length": 0.0, "loop": role in LOOPING, "sounds": [], "voices": [], "effects": []}
        collect("A_monster_%s_%s" % (prefix, rest), 0.0, 1e9, 0.0, entry)
        for clip_name, start, end, shift in config["borrow"].get(role, []):
            collect(clip_name, start, end, shift, entry)
        if entry["sounds"] or entry["voices"]:
            roles[role] = entry
    for cue, (clip_name, start, end) in config["cues"].items():
        entry = {"length": 0.0, "loop": False, "sounds": [], "voices": [], "effects": []}
        collect(clip_name, start, end, -start, entry)
        if entry["sounds"] or entry["voices"]:
            roles["cue_" + cue] = entry
    manifest = {"enemy": prefix, "languages": LANGUAGES, "roles": roles}
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("fx.json", json.dumps(manifest, ensure_ascii=False, separators=(",", ":")))
        for wav in sorted(audio_files):
            archive.write(os.path.join(audio_dir, wav), "audio/" + wav)
    print("%s: 소리 %d개, 소리 있는 역할 %s" % (target, len(audio_files), ", ".join(sorted(roles))))


def root_motion(doc, data, anim):
    """원본 동작에서 뿌리 뼈가 앞(+Z, 모델이 보는 쪽)으로 나아간 거리(m)와 좌우로 돈 각도(도, 위에서 본 회전을
    360도 넘어도 이어 센다)를 초당 30번 잰다: ([(시각, 거리)], [(시각, 각도)])"""
    nodes = doc["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    chain = []
    i = next(k for k, n in enumerate(nodes) if n.get("name") == ROOT_BONE)
    while i is not None:
        chain.append(i)
        i = parent.get(i)
    chain.reverse()
    tracks = {}
    end = 0.0
    for channel in anim["channels"]:
        sampler = anim["samplers"][channel["sampler"]]
        times = [v[0] for v in read_floats(doc, data, sampler["input"])]
        tracks[(channel["target"].get("node"), channel["target"]["path"])] = (times, read_floats(doc, data, sampler["output"]))
        end = max(end, times[-1])

    def world(t):
        pos, rot, scale = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0)
        for k in chain:
            n = nodes[k]
            tr, ro, sc = tracks.get((k, "translation")), tracks.get((k, "rotation")), tracks.get((k, "scale"))
            tr = measure.sample(*tr, t, False) if tr else n.get("translation", [0, 0, 0])
            ro = measure.sample(*ro, t, True) if ro else n.get("rotation", [0, 0, 0, 1])
            sc = measure.sample(*sc, t, False) if sc else n.get("scale", [1, 1, 1])
            p = measure.qrot(rot, (tr[0] * scale[0], tr[1] * scale[1], tr[2] * scale[2]))
            pos = (pos[0] + p[0], pos[1] + p[1], pos[2] + p[2])
            rot = measure.qmul(rot, tuple(ro))
            scale = (scale[0] * sc[0], scale[1] * sc[1], scale[2] * sc[2])
        return pos, rot

    start, start_rotation = world(0.0)
    start_inv = (-start_rotation[0], -start_rotation[1], -start_rotation[2], start_rotation[3])
    travel, turn = [], []
    previous = 0.0
    frame = 0
    while frame / 30.0 <= end + 1e-6:
        t = frame / 30.0
        pos, rot = world(t)
        travel.append((t, pos[2] - start[2]))
        r = measure.qmul(rot, start_inv)
        angle = math.degrees(2.0 * math.atan2(r[1], r[3]))
        angle += round((previous - angle) / 360.0) * 360.0
        previous = angle
        turn.append((t, angle))
        frame += 1
    return travel, turn


def vec2(points, digits):
    return "PackedVector2Array(%s)" % ", ".join("%g, %g" % (round(t, 4), round(v, digits)) for t, v in points)


def update_enemy_data(target, motions):
    """이 모델을 쓰는 적 데이터(data/enemies/*.tres)의 공격마다 travel·turn을 넣는다(공격의 clip 이름으로 찾는다)."""
    model_file = "enemies/" + os.path.basename(target)
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "enemies", "*.tres"))):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if 'model_file = "%s"' % model_file not in text:
            continue
        blocks = re.split(r"(?m)^(?=\[)", text)
        changed = 0
        for k, block in enumerate(blocks):
            clip = re.search(r'(?m)^clip = &"([^"]+)"$', block)
            if not clip or clip.group(1) not in motions:
                continue
            travel, turn = motions[clip.group(1)]
            block = re.sub(r"(?m)^(travel|turn) = .*\n", "", block)
            block = block.replace(clip.group(0), "%s\ntravel = %s\nturn = %s" % (clip.group(0), vec2(travel, 3), vec2(turn, 1)), 1)
            blocks[k] = block
            changed += 1
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("".join(blocks))
        print("%s: 공격 %d개에 travel·turn" % (os.path.relpath(path, ROOT), changed))


def main(source, target):
    doc, data = read_glb(source)
    data = bytearray(data)
    by_name = {a.get("name"): a for a in doc.get("animations", [])}
    prefix = pick_enemy(by_name)
    root_parent = parent_rotation(doc, ROOT_BONE)
    animations = []
    motions = {}
    for role, rest in ENEMIES[prefix].items():
        name = "A_monster_%s_%s" % (prefix, rest)
        if name not in by_name:
            sys.exit("원본에 없는 동작: " + name)
        anim = json.loads(json.dumps(by_name[name]))
        if role == "move":
            distance, length = root_travel(doc, data, anim)
            print("이동 동작 원래 빠르기: %.2f m/s (EnemyData.move_clip_speed)" % (distance / length if length > 0 else 0.0))
        attack = role.startswith("attack_")
        if attack:
            motions[role] = root_motion(doc, data, anim)
        anim["name"] = role + ("-loop" if role in LOOPING else "")
        reshape(doc, data, anim, None, True, None, attack, root_parent)
        animations.append(anim)
    doc["animations"] = animations
    strip_extra_meshes(doc)
    save_compact(doc, data, target)
    update_enemy_data(target, motions)
    build_sounds(source, prefix, os.path.splitext(target)[0] + "_fx.zip")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    os.makedirs(os.path.dirname(os.path.abspath(sys.argv[2])), exist_ok=True)
    main(sys.argv[1], sys.argv[2])
