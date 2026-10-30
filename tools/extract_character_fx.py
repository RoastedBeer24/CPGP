"""원본 캐릭터의 소리·보이스·이펙트 연결 정보에서 게임이 쓰는 동작의 것만 골라 캐릭터마다 zip 하나로 묶는다.

    python3 tools/extract_character_fx.py "!File/Endministrator_Extras" F assets/characters/endministrator_f/endministrator_f_fx.zip
    python3 tools/extract_character_fx.py "!File/Endministrator_Extras" M assets/characters/endministrator_m/endministrator_m_fx.zip

원본 꾸러미(사용자가 사이트에서 추출해 준 것)에는 동작마다 언제 어떤 소리·보이스·이펙트가 나는지(animation_events.json)와
그 파일들(assets/audio_wav, characters/*/effects)이 들어 있다. 게임 이름(attack_1 등)은 tools/extract_character.py의
ROLES와 같고, 그 도구가 잘라 쓰는 구간(TRIMS) 밖의 소리는 뺀다.

zip 안에는 fx.json(동작 이름 → 시각별 소리·보이스·이펙트)과 audio/*.wav, effects/*.glb가 들어간다.
게임은 실행 중에 이 zip을 읽는다(src/player/character_fx.gd). 원작 자산이라 재배포할 수 없으므로 저장소에 올리지 않고
비공개 에셋 저장소에만 올린다(docs/assets.md).
"""
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_character import CHARACTERS, LOOPING, ROLES, TRIM_OVERRIDES, TRIMS  # noqa: E402

LANGUAGES = ["KR", "JP", "EN", "CN"]


def wav_name(m4a):
    return os.path.splitext(m4a)[0] + ".wav"


def main(extras, who, target):
    char = "endminf" if who == "F" else "endminm"
    body = CHARACTERS[char]
    events = json.load(open(os.path.join(extras, "characters", who, "animation_events.json"), encoding="utf-8"))
    catalog = json.load(open(os.path.join(extras, "characters", who, "effect_catalog.json"), encoding="utf-8"))
    audio_dir = os.path.join(extras, "assets", "audio_wav")
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

    for role, candidates in ROLES.items():
        names = [c.format(char=char, body=body) for c in candidates]
        entry = next((events[n] for n in names if n in events), None)
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
            particles = info.get("particle_data")
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

    manifest = {"character": char, "languages": LANGUAGES, "roles": roles}
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("fx.json", json.dumps(manifest, ensure_ascii=False, separators=(",", ":")))
        for wav in sorted(audio_files):
            archive.write(os.path.join(audio_dir, wav), "audio/" + wav)
        for name, source in sorted(effect_files.items()):
            archive.write(source, "effects/" + name)
    size = os.path.getsize(target)
    print("%s: 동작 %d개, 소리 %d개, 이펙트 %d개, %.1fMB" % (target, len(roles), len(audio_files), len(effect_files), size / 1e6))
    for role, data in roles.items():
        print("  %-12s 소리 %2d  보이스 %d  이펙트 %d" % (role, len(data["sounds"]), len(data["voices"]), len(data["effects"])))
    if missing:
        print("  (원본에 없는 소리 %d개는 뺐습니다)" % len(missing))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
