"""원작 캐릭터 glb의 전투 동작을 재서 전투 구성(data/characters/<이름>/kit.tres) 초안을 만든다(새 캐릭터 넣기).

    python3 tools/draft_kit.py <원본_Animated.glb> <battle.json> <캐릭터 이름(id)> <표시 이름> <결과 kit.tres>
    python3 tools/draft_kit.py "!File/Chen_Arclight_Pogranichnik_Assets/characters/chr_0005_chen/chr_0005_chen_Animated.glb" \\
        "!File/Chen_Arclight_Pogranichnik_Assets/characters/chr_0005_chen/metadata/battle.json" chen_qianyu 진천우 \\
        data/characters/chen_qianyu/kit.tres

원작 동작에서 재는 것: 타격 시각(무기가 빨라지는 봉우리), 내디딤 거리(뿌리 뼈가 앞으로 나간 거리, AttackData.advance),
몸 회전(AttackData.turn), 낙하 공격 높이(AttackData.rise). 기술 이름은 battle.json의 한국어 이름이다.
배율·경직·판정 거리·에너지 같은 수치는 관리자(여)를 기준으로 한 기본값이라, 만든 뒤 화면으로 보며 고친다.
동작을 자를 구간도 찍으므로 tools/extract_character.py의 TRIM_OVERRIDES에 넣고 모델을 뽑는다(같은 구간이어야 한다).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_character as ec  # noqa: E402
import measure_attack_clips as m  # noqa: E402

STEP = 1.0 / 60.0
# 역할 → (타격을 찾을 구간 끝(초), 마지막 타격 뒤로 남길 길이(초))
WINDOWS = {
    "attack_1": (1.3, 0.55), "attack_2": (1.3, 0.55), "attack_3": (1.4, 0.55), "attack_4": (1.5, 0.55),
    "attack_5": (1.8, 0.7), "dash_attack": (2.2, 0.5), "finisher": (2.6, 0.6), "skill": (2.6, 0.5),
    "ultimate": (6.0, 0.8),
}
# 기본 공격 단계별 (배율 합, 경직 합). 관리자(여)와 비슷하게 마지막 단계가 크다.
CHAIN_TOTALS = [(0.8, 8.0), (0.9, 9.0), (1.4, 17.0), (1.5, 20.0), (2.2, 40.0)]


class Clip:
    """원작 동작 하나를 60fps로 잰 값: 무기 속도, 앞으로 나간 거리, 높이, 좌우 회전."""

    def __init__(self, doc, data, anim, nodes, chains):
        self.length = 0.0
        tracks = {}
        for channel in anim["channels"]:
            sampler = anim["samplers"][channel["sampler"]]
            times = [v[0] for v in m.read_floats(doc, data, sampler["input"])]
            self.length = max(self.length, times[-1])
            tracks[(channel["target"].get("node"), channel["target"]["path"])] = (times, m.read_floats(doc, data, sampler["output"]))

        def pose(chain, t):
            pos, rot, scale = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0)
            for i in chain:
                node = nodes[i]
                tr = tracks.get((i, "translation"))
                ro = tracks.get((i, "rotation"))
                sc = tracks.get((i, "scale"))
                tr = m.sample(*tr, t, False) if tr else node.get("translation", [0, 0, 0])
                ro = m.sample(*ro, t, True) if ro else node.get("rotation", [0, 0, 0, 1])
                sc = m.sample(*sc, t, False) if sc else node.get("scale", [1, 1, 1])
                p = m.qrot(rot, (tr[0] * scale[0], tr[1] * scale[1], tr[2] * scale[2]))
                pos = (pos[0] + p[0], pos[1] + p[1], pos[2] + p[2])
                rot = m.qmul(rot, tuple(ro))
                scale = (scale[0] * sc[0], scale[1] * sc[1], scale[2] * sc[2])
            return pos, rot

        frames = int(self.length / STEP) + 1
        self.speed, self.forward, self.height, self.turn = [], [], [], []
        root0, rot0 = pose(chains["root"], 0.0)
        start_inv = (-rot0[0], -rot0[1], -rot0[2], rot0[3])
        previous_weapon = None
        previous_angle = 0.0
        for k in range(frames):
            t = k * STEP
            weapon, _ = pose(chains["weapon"], t)
            root, rot = pose(chains["root"], t)
            self.speed.append(math.dist(weapon, previous_weapon) / STEP if previous_weapon else 0.0)
            previous_weapon = weapon
            self.forward.append(root[2] - root0[2])
            self.height.append(root[1] - root0[1])
            r = m.qmul(rot, start_inv)
            angle = math.degrees(2.0 * math.atan2(r[1], r[3]))
            angle += round((previous_angle - angle) / 360.0) * 360.0
            previous_angle = angle
            self.turn.append(angle)

    def hits(self, window):
        """구간 안에서 무기 속도 봉우리(타격 후보). 가장 빠른 것의 40%보다 느린 것과 0.15초 안에 겹친 작은 것은 뺀다."""
        last = min(int(window / STEP), len(self.speed) - 3)
        fastest = max(self.speed[3:last] or [0.0])
        floor = max(9.0, fastest * 0.4)
        peaks = [k for k in range(3, last) if self.speed[k] >= floor
                 and self.speed[k] >= max(self.speed[k - 2:k] + self.speed[k + 1:k + 3])]
        kept = []
        for k in sorted(peaks, key=lambda k: -self.speed[k]):
            if all(abs(k - other) * STEP >= 0.15 for other in kept):
                kept.append(k)
        return [round(k * STEP, 2) for k in sorted(kept)]

    def advance(self, end):
        """앞으로 나간 거리(0.05초마다). 몸이 잠깐 뒤로 물러나는 것은 빼고 앞으로 나간 만큼만 센다(게임은 뒤로 내딛지 않는다)."""
        points = [(0.0, 0.0)]
        for k in range(0, int(end / STEP) + 1, 3):
            value = round(max(self.forward[k], points[-1][1]), 2)
            if value - points[-1][1] >= 0.02:
                points.append((round(k * STEP, 2), value))
        return points

    def turns(self, end):
        return [(round(k * STEP, 4), round(self.turn[k], 1)) for k in range(0, int(end / STEP) + 1, 2)]

    def rise(self):
        """낙하 공격 시작: 뛰어올랐다가 처음 높이 아래로 내려올 때까지의 높이(0.05초마다)."""
        points = []
        went_up = False
        for k in range(0, len(self.height), 3):
            value = round(self.height[k], 2)
            points.append((round(k * STEP, 2), value))
            went_up = went_up or value > 0.3
            if went_up and value < 0.0:
                break
        return points


def vec2(points):
    return "PackedVector2Array(%s)" % ", ".join("%g, %g" % p for p in points)


def hit_block(hit_id, time, damage, stagger, reach, arc, knockback, hit_stop, shake):
    return ('[sub_resource type="Resource" id="%s"]\nscript = ExtResource("3_hit")\ntime = %g\ndamage = %g\nstagger = %g\n'
            "reach = %g\narc = %g\nknockback = %g\nhit_stop = %g\nshake = %g\n" % (hit_id, time, damage, stagger, reach, arc, knockback, hit_stop, shake))


def attack_block(attack_id, fields, hit_ids):
    lines = ['[sub_resource type="Resource" id="%s"]' % attack_id, 'script = ExtResource("2_attack")', 'id = &"%s"' % attack_id]
    for key, value in fields:
        lines.append("%s = %s" % (key, value))
    if hit_ids:
        lines.append('hits = Array[ExtResource("3_hit")]([%s])' % ", ".join('SubResource("%s")' % h for h in hit_ids))
    return "\n".join(lines) + "\n"


def main(source, battle_path, kit_id, display_name, target):
    doc, data = m.read_glb(source)
    nodes = doc["nodes"]
    parent = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            parent[child] = i
    # 이름이 같은 뼈가 여럿이면 첫 번째(본인 뼈대)를 쓴다(포그라니치니크는 궁극기 방패병 뼈대가 함께 들어 있다).
    index = {}
    for i, node in enumerate(nodes):
        index.setdefault(node.get("name", ""), i)

    def chain(name):
        i = index[name]
        out = []
        while i is not None:
            out.append(i)
            i = parent.get(i)
        return list(reversed(out))

    chains = {"root": chain("Bip001"), "weapon": chain("IK_Weapon_R_001")}
    by_name = {a.get("name"): a for a in doc.get("animations", [])}
    char = ec.pick_character(by_name)
    clips = {}
    for role in list(WINDOWS) + ["plunge_start", "plunge_end"]:
        found = ec.role_clip(role, char, by_name)
        if found:
            clips[role] = Clip(doc, data, by_name[found], nodes, chains)
    battle = json.load(open(battle_path, encoding="utf-8"))
    names = {e["id"]: e.get("name", {}).get("KR", "") for e in battle["entries"]}

    blocks = []
    trims = {}
    chain_ids = [r for r in ["attack_1", "attack_2", "attack_3", "attack_4", "attack_5"] if r in clips]
    for step, role in enumerate(chain_ids):
        clip = clips[role]
        window, tail = WINDOWS[role]
        hits = clip.hits(window) or [0.3]
        last = hits[-1]
        final = step == len(chain_ids) - 1
        total_damage, total_stagger = CHAIN_TOTALS[min(step, 4) if not final else 4]
        hit_ids = []
        for n, time in enumerate(hits):
            share = 1.0 / len(hits) if len(hits) == 1 else (0.4 if n < len(hits) - 1 else 0.6) / (1 if n == len(hits) - 1 else len(hits) - 1)
            hit_id = "hit_%s_%d" % (role, n + 1)
            hit_ids.append(hit_id)
            blocks.append(hit_block(hit_id, time, round(total_damage * share, 2), round(total_stagger * share, 1),
                                    3.0 if final else 2.7, 80.0, 1.2 if final else 0.3, 0.1 if final else 0.05, 0.45 if final else 0.12))
        duration = round(last + (0.6 if final else 0.45), 2)
        trims[role] = round(min(clip.length, duration + 0.15), 2)
        name = names.get("attack", "") or "기본 공격"
        fields = [("display_name", '"%s %d"' % (name, step + 1) if not final else '"마무리 일격"'),
                  ("clip", '&"%s"' % role), ("turn", vec2(clip.turns(trims[role]))), ("duration", duration),
                  ("chain_from", duration if final else round(last + 0.12, 2)),
                  ("move_cancel_from", round(duration * 0.8, 2) if final else round(last + 0.3, 2)),
                  ("advance", vec2(clip.advance(duration)))]
        if final:
            fields.insert(1, ("description", '"%s 마지막 타. 크게 베어 경직을 많이 쌓고 SP를 돌려받는다."' % name))
            fields += [("stop_short", 1.2), ("energy_per_hit", 4.0), ("sp_per_hit", 10.0)]
        blocks.append(attack_block(role, fields, hit_ids))

    def special(role, attack_id, title, description, total_damage, total_stagger, reach, extra, last_share=0.6):
        clip = clips[role]
        window, tail = WINDOWS[role]
        hits = clip.hits(window) or [0.4]
        hit_ids = []
        for n, time in enumerate(hits):
            if len(hits) == 1:
                share = 1.0
            elif n == len(hits) - 1:
                share = last_share
            else:
                share = (1.0 - last_share) / (len(hits) - 1)
            hit_id = "hit_%s_%d" % (attack_id, n + 1)
            hit_ids.append(hit_id)
            big = n == len(hits) - 1
            blocks.append(hit_block(hit_id, time, round(total_damage * share, 2), round(total_stagger * share, 1),
                                    reach, 90.0, 1.0 if big else 0.3, 0.1 if big else 0.04, 0.5 if big else 0.12))
        duration = round(hits[-1] + tail, 2)
        trims[role] = round(min(clip.length, duration + 0.15), 2)
        fields = [("display_name", '"%s"' % title), ("description", '"%s"' % description), ("clip", '&"%s"' % role),
                  ("turn", vec2(clip.turns(trims[role]))), ("duration", duration)] + extra(duration) + [
                  ("advance", vec2(clip.advance(duration)))]
        blocks.append(attack_block(attack_id, fields, hit_ids))
        return hits

    if "dash_attack" in clips:
        special("dash_attack", "dash_attack", "대시 공격: " + (names.get("combo") or "연계 스킬"),
                "회피 직후 공격하면 원작 연계 스킬로 내달리며 벤다.", 2.6, 30.0, 3.0,
                lambda d: [("chain_from", round(d - 0.25, 2)), ("move_cancel_from", round(d - 0.2, 2)), ("turn_until", 0.15),
                           ("stop_short", 1.2), ("energy_per_hit", 2.0)])
    special("finisher", "finisher", "처형", "경직된 적 가까이서 공격하면 나간다. 무적이며 아주 큰 피해.", 6.2, 0.0, 3.2,
            lambda d: [("chain_from", d), ("move_cancel_from", round(d - 0.15, 2)), ("dodge_cancel_from", round(d - 0.3, 2)),
                       ("turn_until", 0.1), ("stop_short", 1.0), ("energy_per_hit", 8.0), ("invulnerable_until", round(d - 0.1, 2)),
                       ("super_armor", "true")], last_share=0.8)
    special("skill", "battle_skill", "배틀 스킬: " + (names.get("skill") or "배틀 스킬"),
            "SP 100. 크게 베어 적의 균형을 무너뜨린다.", 2.6, 30.0, 4.0,
            lambda d: [("chain_from", round(d - 0.25, 2)), ("move_cancel_from", round(d - 0.2, 2)), ("turn_until", 0.12),
                       ("stop_short", 1.4), ("sp_cost", 100.0), ("energy_gain", 12.0), ("energy_per_hit", 2.0), ("super_armor", "true")])
    special("ultimate", "ultimate", "궁극기: " + (names.get("ultimate") or "궁극기"),
            "궁극기 에너지 80. 앞쪽을 휩쓰는 큰 일격.", 9.0, 120.0, 6.5,
            lambda d: [("chain_from", d), ("move_cancel_from", round(d - 0.3, 2)), ("dodge_cancel_from", round(d - 0.3, 2)),
                       ("turn_until", 0.3), ("energy_cost", 80.0), ("energy_per_hit", 0.0), ("invulnerable_until", d),
                       ("super_armor", "true")], last_share=0.6)

    plunge = clips["plunge_start"]
    rise = plunge.rise()
    trims["plunge_end"] = 1.6
    blocks.append(attack_block("plunge_start", [
        ("display_name", '"낙하 공격"'),
        ("description", '"공중에서 공격하면 뛰어올랐다가 내리꽂는다. 땅에 닿으며 둘레의 적을 모두 내려친다."'),
        ("clip", '&"plunge_start"'), ("duration", round(plunge.length, 2)), ("rise", vec2(rise)),
        ("energy_per_hit", 0.0), ("super_armor", "true")], []))
    blocks.append(attack_block("plunge_fall", [("display_name", '"낙하 공격"'), ("clip", '&"plunge_loop"'), ("duration", 30.0),
                                               ("energy_per_hit", 0.0), ("super_armor", "true")], []))
    blocks.append(hit_block("hit_plunge", 0.03, 2.2, 25.0, 3.2, 180.0, 1.2, 0.08, 0.5))
    blocks.append(attack_block("plunge_land", [("display_name", '"낙하 공격 착지"'), ("clip", '&"plunge_end"'), ("duration", 1.0),
                                               ("chain_from", 0.55), ("move_cancel_from", 0.75), ("dodge_cancel_from", 0.25),
                                               ("turn_until", 0.0), ("energy_per_hit", 3.0)], ["hit_plunge"]))

    resource = ['[resource]', 'script = ExtResource("1_kit")', 'id = &"%s"' % kit_id, 'display_name = "%s"' % display_name,
                'max_health = 1200.0', 'attack_power = 100.0',
                'basic_chain = Array[ExtResource("2_attack")]([%s])' % ", ".join('SubResource("%s")' % r for r in chain_ids)]
    if "dash_attack" in clips:
        resource.append('dash_attack = SubResource("dash_attack")')
    resource += ['finisher = SubResource("finisher")', 'battle_skill = SubResource("battle_skill")', 'ultimate = SubResource("ultimate")',
                 'plunge_start = SubResource("plunge_start")', 'plunge_fall = SubResource("plunge_fall")', 'plunge_land = SubResource("plunge_land")']
    header = ('[gd_resource type="Resource" script_class="KitData" format=3]\n\n'
              '[ext_resource type="Script" path="res://src/combat/kit_data.gd" id="1_kit"]\n'
              '[ext_resource type="Script" path="res://src/combat/attack_data.gd" id="2_attack"]\n'
              '[ext_resource type="Script" path="res://src/combat/hit_data.gd" id="3_hit"]\n\n')
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "\n".join(blocks) + "\n" + "\n".join(resource) + "\n")
    sys.stdout.reconfigure(encoding="utf-8")
    print("%s: 기본 공격 %d단계, 동작 구간(TRIM_OVERRIDES[%r]):" % (target, len(chain_ids), char))
    print("    " + repr({role: (0.0, end) for role, end in trims.items()}))
    for role, clip in clips.items():
        if role in WINDOWS:
            print("    %-12s 길이 %.2f초, 타격 %s" % (role, clip.length, clip.hits(WINDOWS[role][0])))


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    main(*sys.argv[1:])
