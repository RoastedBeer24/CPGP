"""원본 캐릭터의 소리·보이스·이펙트 연결 정보에서 게임이 쓰는 동작의 것만 골라 캐릭터마다 zip 하나로 묶는다.

    python3 tools/extract_character_fx.py "!File/Endministrator_Extras" F assets/characters/endministrator_f/endministrator_f_fx.zip
    python3 tools/extract_character_fx.py "!File/Endministrator_Extras" M assets/characters/endministrator_m/endministrator_m_fx.zip
    python3 tools/extract_character_fx.py "!File/Akekuri_Assets" Akekuri assets/characters/akekuri/akekuri_fx.zip
    python3 tools/extract_character_fx.py "!File/Chen_Arclight_Pogranichnik_Assets" chr_0005_chen assets/characters/chen_qianyu/chen_qianyu_fx.zip

원본 꾸러미(사용자가 사이트에서 추출해 준 것)에는 동작마다 언제 어떤 소리·보이스·이펙트가 나는지(animation_events.json)와
그 파일들(assets/audio_wav, characters/*/effects)이 들어 있다. 게임 이름(attack_1 등)은 tools/extract_character.py의
ROLES와 같고, 그 도구가 잘라 쓰는 구간(TRIMS) 밖의 소리는 뺀다.

zip 안에는 fx.json(동작 이름 → 시각별 소리·보이스·이펙트, 소품 목록)과 audio/*.wav, effects/*.glb, props/*.glb(보조 무기)가
들어간다.
게임은 실행 중에 이 zip을 읽는다(src/player/character_fx.gd). 원작 자산이라 재배포할 수 없으므로 저장소에 올리지 않고
비공개 에셋 저장소에만 올린다(docs/assets.md).
"""
import json
import os
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_character import (LOOPING, ROLES, TRIM_OVERRIDES, TRIMS, read_glb, role_clip, save_compact,  # noqa: E402
                               strip_extra_meshes)

LANGUAGES = ["KR", "JP", "EN", "CN"]
# 원본 꾸러미의 캐릭터 폴더 이름(characters/<이름>) → 동작 이름의 캐릭터 앞부분
WHO = {"F": "endminf", "M": "endminm", "Akekuri": "karin", "chr_0005_chen": "chen", "chr_0007_ikut": "ikut",
       "chr_0029_pograni": "pograni"}

# 원작 자료에 이펙트가 없는 동작은 비슷한 동작의 원작 이펙트를 타격 시각에 맞춰 빌려 쓴다(게임에서 정한 것).
# 캐릭터 → 동작 → [(빌려 올 동작, 그 동작의 타격 시각, 이 동작의 타격 시각), ...]. 타격 시각은 data/characters/*/kit.tres.
BORROWED = {
    "endminf": {"ultimate": [("skill", 0.26, 1.47), ("finisher", 0.92, 3.02)]},
    "endminm": {"ultimate": [("skill", 0.3, 2.12), ("finisher", 0.97, 2.33)]},
}


# 소품(보조 무기): 원작 무기 연결 정보(weapon_binding.json)의 battle.copies 가운데 칼 다음 것들. 캐릭터 →
# [(copy의 index, 꾸러미의 소품 이름(object_catalog), 시간표가 없는 동작(이동·대기)에서 쉬는 자리에 보이는지,
# 숨기는 동작(역할 이름))].
# 진천우는 싸울 때 왼손에 wpn_misc_0002를 들고(평소엔 inner 자리) 허리(outer)에 wpn_misc_0003을 단다. 원작 캐릭터 화면
# 자료(animation_events.json의 deco_events)에서 쉬는 자세(relax)와 그 반응 동작에서는 둘 다 숨긴다. 포그라니치니크는
# 처형·배틀 스킬·궁극기 동안 칼을 거두고 왼손에 wpn_misc_0035를 든다(그 밖에는 숨김).
RELAX_ROLES = ("relax_in", "relax", "relax_sp_1", "relax_sp_2", "ui_react")
PROPS = {
    "chen": [(10, "deco:1", True, RELAX_ROLES), (11, "deco:2", True, RELAX_ROLES)],
    "pograni": [(10, "deco:7", False, ())],
}


def wav_name(m4a):
    return os.path.splitext(m4a)[0] + ".wav"


def prop_bytes(path):
    """소품 glb에서 먼 거리용 메시(lod1~3)와 그림자 대용 메시를 빼고 쓰는 데이터만 남긴 glb 내용."""
    doc, data = read_glb(path)
    doc.setdefault("animations", [])
    strip_extra_meshes(doc)
    with tempfile.TemporaryDirectory() as folder:
        out = os.path.join(folder, "prop.glb")
        save_compact(doc, bytearray(data), out)
        with open(out, "rb") as f:
            return f.read()


def collect_props(extras, who, char, catalog):
    """소품 목록(fx.json의 props)과 zip에 넣을 소품 파일(이름 → 내용). 동작별 시간표는 [시각, 자리, ...]이고
    자리는 0 숨김, 1 쉬는 자리(idle), 2 싸우는 자리(fight)다."""
    props, files = [], {}
    binding_path = os.path.join(extras, "characters", who, "weapon_binding.json")
    clips_path = os.path.join(extras, "characters", who, "metadata", "clips.json")
    if char not in PROPS or not os.path.isfile(binding_path) or not os.path.isfile(clips_path):
        return props, files
    binding = json.load(open(binding_path, encoding="utf-8"))
    file_of = {c["name"]: c["file"] for c in json.load(open(clips_path, encoding="utf-8"))}
    copies = binding["battle"]["copies"]
    for copy_index, deco, shown, hidden_roles in PROPS[char]:
        slot = next(i for i, c in enumerate(copies) if c["index"] == copy_index)
        info = catalog.get(deco) or {}
        source = os.path.join(extras, info.get("glb", ""))
        if not os.path.isfile(source):
            print("  소품 모델이 없어 건너뜀:", deco)
            continue
        timelines = {}
        for role in ROLES:
            name = role_clip(role, char, file_of)
            per_copy = binding["battle"]["clips"].get(file_of.get(name, "")) if name else None
            if per_copy and slot < len(per_copy):
                timelines[role] = [x for t, v in per_copy[slot] for x in (round(t, 4), int(v))]
            if role in hidden_roles and name:
                timelines[role] = [0.0, 0]
        name = "props/%d.glb" % copy_index
        files[name] = prop_bytes(source)
        props.append({"file": name, "idle": copies[slot].get("idle"), "fight": copies[slot].get("fight"),
                      "shown": shown, "timelines": timelines})
    return props, files


def main(extras, who, target):
    char = WHO[who]
    events = json.load(open(os.path.join(extras, "characters", who, "animation_events.json"), encoding="utf-8"))
    # 꾸러미마다 이름이 조금 다르다: 이펙트 목록(effect_catalog.json 또는 object_catalog.json), 소리 폴더
    # (assets/audio_wav 또는 audio/wav), 파티클 설정 키(particle_data 또는 particles).
    catalog_path = os.path.join(extras, "characters", who, "effect_catalog.json")
    if not os.path.isfile(catalog_path):
        catalog_path = os.path.join(extras, "characters", who, "object_catalog.json")
    catalog = json.load(open(catalog_path, encoding="utf-8"))
    audio_dir = os.path.join(extras, "assets", "audio_wav")
    if not os.path.isdir(audio_dir):
        audio_dir = os.path.join(extras, "audio", "wav")
    trims = dict(TRIMS)
    trims.update(TRIM_OVERRIDES.get(char, {}))

    roles = {}
    audio_files = set()
    effect_files = {}
    missing = set()

    def keep_audio(names):
        found = []
        for m4a in names:
            wav = wav_name(m4a)
            if os.path.isfile(os.path.join(audio_dir, wav)):
                found.append(wav)
                audio_files.add(wav)
            else:
                missing.add(wav)
        return found

    for role in ROLES:
        name = role_clip(role, char, events)
        entry = events[name] if name else None
        if entry is None:
            continue
        end = trims[role][1] if role in trims else float(entry.get("duration", 0.0))
        sounds, voices, effects = [], [], []
        for event in entry.get("audio_events", []):
            if event["time"] > end:
                continue
            voice = event.get("voice")
            if voice:
                languages = {}
                for language in LANGUAGES:
                    choices = []
                    for choice in voice.get("languages", {}).get(language, []):
                        files = keep_audio(choice.get("sounds", []))
                        if files:
                            choices.append({"weight": choice.get("weight", 1), "files": files})
                    if choices:
                        languages[language] = choices
                if languages:
                    voices.append({"time": round(event["time"], 4), "chance": voice.get("chance", 1.0),
                                   "cooldown": voice.get("cooldown", 0.0), "priority": voice.get("priority", 0),
                                   "languages": languages})
                continue
            files = keep_audio(event.get("sounds", []))
            if not files:
                continue
            sound = {"time": round(event["time"] + event.get("delay", 0.0), 4), "files": files,
                     "mode": event.get("mode", "random"), "volume": event.get("volume", 1.0)}
            if "volumes" in event:
                sound["volumes"] = event["volumes"]
            if event.get("foley"):
                sound["foley"] = True
            sounds.append(sound)
        # 메뉴 화면용 꾸밈 이펙트는 사전 모양이라 뺀다(전투 동작은 목록이다).
        listed = [e for key in ("battle_effect_events", "deco_effect_events")
                  for e in (entry.get(key) if isinstance(entry.get(key), list) else [])]
        for event in listed:
            if event.get("start", 0.0) > end:
                continue
            info = catalog.get("battleEffects:" + event["effect"]) or catalog.get("decoEffects:" + event["effect"])
            if info is None or not info.get("glb"):
                continue
            source = os.path.join(extras, info["glb"])
            if not os.path.isfile(source):
                continue
            effect_files[os.path.basename(source)] = source
            # 파티클 설정(유니티 파티클 시스템을 옮겨 적은 JSON)도 함께 넣는다. 게임이 이것으로 파티클을 만든다.
            particles = info.get("particle_data") or info.get("particles")
            particle_file = None
            if particles and os.path.isfile(os.path.join(extras, particles)):
                particle_file = os.path.basename(particles)
                effect_files[particle_file] = os.path.join(extras, particles)
            effects.append({"effect": event["effect"], "file": os.path.basename(source), "particles": particle_file,
                            "start": event.get("start", 0.0), "end": event.get("end", 0.0), "mount": event.get("mount"),
                            "move": event.get("move"), "rot": event.get("rot"), "pose": event.get("pose"),
                            "path": event.get("path"), "scale": event.get("scale"),
                            "grounded": event.get("grounded", False)})
        if sounds or voices or effects:
            roles[role] = {"length": end, "loop": role in LOOPING, "sounds": sounds, "voices": voices, "effects": effects}

    for role, sources in BORROWED.get(char, {}).items():
        for source, source_hit, hit in sources:
            shift = hit - source_hit
            for effect in roles.get(source, {}).get("effects", []):
                copied = dict(effect)
                copied["start"] = round(float(effect["start"]) + shift, 4)
                copied["end"] = round(float(effect["end"]) + shift, 4)
                roles.setdefault(role, {"length": 0.0, "loop": False, "sounds": [], "voices": [], "effects": []})
                roles[role]["effects"].append(copied)

    # 원작 연출 카메라: 궁극기 컷(캐릭터 모델 기준 위치·회전·시야각, 초당 60장)과 캐릭터 화면용 자세들
    camera_path = os.path.join(extras, "characters", who, "metadata", "camera.json")
    camera = json.load(open(camera_path, encoding="utf-8")) if os.path.isfile(camera_path) else {}

    props, prop_files = collect_props(extras, who, char, catalog)
    manifest = {"character": char, "languages": LANGUAGES, "roles": roles, "props": props,
                "camera": camera.get("shots", {}), "camera_poses": camera.get("pages", {}).get("poses", {})}
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("fx.json", json.dumps(manifest, ensure_ascii=False, separators=(",", ":")))
        for wav in sorted(audio_files):
            archive.write(os.path.join(audio_dir, wav), "audio/" + wav)
        for name, source in sorted(effect_files.items()):
            archive.write(source, "effects/" + name)
        for name, content in sorted(prop_files.items()):
            archive.writestr(name, content)
    size = os.path.getsize(target)
    print("%s: 동작 %d개, 소리 %d개, 이펙트 %d개, 소품 %d개, %.1fMB" % (target, len(roles), len(audio_files), len(effect_files),
                                                              len(props), size / 1e6))
    for role, data in roles.items():
        print("  %-12s 소리 %2d  보이스 %d  이펙트 %d" % (role, len(data["sounds"]), len(data["voices"]), len(data["effects"])))
    if missing:
        print("  (원본에 없는 소리 %d개는 뺐습니다)" % len(missing))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
