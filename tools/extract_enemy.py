"""원작 적 glb(<ID>_Animated.glb, 본 크러셔 꾸러미)에서 게임에 쓸 동작만 골라 가벼운 glb를 만든다.

    python3 tools/extract_enemy.py "!File/Bonekrusher_Assets/enemies/eny_0029_lbmob/eny_0029_lbmob_Animated.glb" assets/enemies/lbmob.glb

동작 이름은 게임이 부르는 역할 이름(idle, move, hit, stun_start, stun, dead, attack_1 ...)으로 바꾼다(EnemyData.clips가 이
이름을 쓴다). 원본 동작은 몸(뿌리 뼈 Bip001)이 앞으로 나가므로 모두 제자리로 묶는다. 적은 게임이 직접 움직인다
(이동 속도, 공격의 lunge). 원래 이동 동작의 빠르기(m/s)를 찍으므로 EnemyData.move_clip_speed에 넣는다.
결과 파일은 재배포할 수 없는 모델이라 저장소에 올리지 않는다(docs/assets.md).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_character import read_glb, read_floats, reshape, save_compact, strip_extra_meshes, ROOT_BONE  # noqa: E402

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


def main(source, target):
    doc, data = read_glb(source)
    data = bytearray(data)
    by_name = {a.get("name"): a for a in doc.get("animations", [])}
    prefix = pick_enemy(by_name)
    animations = []
    for role, rest in ENEMIES[prefix].items():
        name = "A_monster_%s_%s" % (prefix, rest)
        if name not in by_name:
            sys.exit("원본에 없는 동작: " + name)
        anim = json.loads(json.dumps(by_name[name]))
        if role == "move":
            distance, length = root_travel(doc, data, anim)
            print("이동 동작 원래 빠르기: %.2f m/s (EnemyData.move_clip_speed)" % (distance / length if length > 0 else 0.0))
        anim["name"] = role + ("-loop" if role in LOOPING else "")
        reshape(doc, data, anim, None, True)
        animations.append(anim)
    doc["animations"] = animations
    strip_extra_meshes(doc)
    save_compact(doc, data, target)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    os.makedirs(os.path.dirname(os.path.abspath(sys.argv[2])), exist_ok=True)
    main(sys.argv[1], sys.argv[2])
