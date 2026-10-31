"""캐릭터 모델 같은 에셋을 비공개 에셋 저장소의 릴리스에 올린다. 게임(AssetUpdater)이 켤 때 받아 간다.

    python3 tools/publish_assets.py             # 올리기
    python3 tools/publish_assets.py --dry-run   # 목록(assets.json)만 만들어 보기
    python3 tools/publish_assets.py --create    # 에셋 저장소가 없으면 비공개로 만들고 올리기

- 올리는 파일은 아래 FILES에 적는다. 경로는 실행 파일 폴더 기준이다(게임이 그 자리에 넣는다).
- 모델은 glb 대신 구운 장면(.scn)을 올린다(BAKED). 올리기 전에 tools/bake_models.gd로 build/baked/에 굽는다
  (원본이나 굽는 도구가 더 새로울 때만). Godot 위치를 GODOT 환경 변수로 알려 줘야 한다.
- 재배포할 수 없는 에셋이라 저장소가 비공개인지 먼저 확인하고, 공개면 올리지 않는다.
- 게임은 목록(assets.json)의 SHA-256과 자기 파일을 비교해 다른 파일만 받는다. 릴리스에 있는 목록과 비교해 바뀐 파일만
  올리고, 목록을 마지막에 올린다.
- gh(GitHub CLI)에 로그인되어 있어야 한다.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

# src/core/asset_updater.gd의 REPOSITORY, RELEASE_TAG, MANIFEST_NAME과 같아야 한다.
REPOSITORY = "RoastedBeer24/CPGP-assets"
RELEASE_TAG = "assets"
MANIFEST_NAME = "assets.json"

# 구운 모델: 실행 파일 폴더 기준 경로(.scn) -> 원본 glb. 게임은 같은 이름의 .glb 자리에서 .scn을 먼저 찾는다
# (CharacterAppearance.baked_path). glb는 올리지 않는다(예전에 받은 glb는 .scn이 없을 때 대신 쓴다).
BAKED = {
    "characters/endministrator_f.scn": "assets/characters/endministrator_f/endministrator_f.glb",
    "characters/endministrator_m.scn": "assets/characters/endministrator_m/endministrator_m.glb",
    "characters/akekuri.scn": "assets/characters/akekuri/akekuri.glb",
    "characters/chen_qianyu.scn": "assets/characters/chen_qianyu/chen_qianyu.glb",
    "characters/arclight.scn": "assets/characters/arclight/arclight.glb",
    "characters/pogranichnik.scn": "assets/characters/pogranichnik/pogranichnik.glb",
    "weapons/tarr_11.scn": "assets/weapons/tarr_11.glb",
    "weapons/edge_of_lightness.scn": "assets/weapons/edge_of_lightness.glb",
    "weapons/aspirant.scn": "assets/weapons/aspirant.glb",
    "weapons/twelve_questions.scn": "assets/weapons/twelve_questions.glb",
    "weapons/never_rest.scn": "assets/weapons/never_rest.glb",
    # 적 모델(tools/extract_enemy.py로 본 크러셔 꾸러미에서 뽑은 것)
    "enemies/lbmob.scn": "assets/enemies/lbmob.glb",
    "enemies/lbhunt.scn": "assets/enemies/lbhunt.glb",
    "enemies/lbtough.scn": "assets/enemies/lbtough.glb",
    "enemies/lbtough_elite.scn": "assets/enemies/lbtough_elite.glb",
    "enemies/rodin.scn": "assets/enemies/rodin.glb",
}
BAKE_DIR = "build/baked"
# 굽는 결과를 바꾸는 코드. 이것이 구운 파일보다 새로우면 다시 굽는다.
BAKE_CODE = ["tools/bake_models.gd", "src/player/character_appearance.gd", "src/core/gltf_mipmaps.gd"]

# 실행 파일 폴더 기준 경로 -> 저장소(작업 폴더) 안의 원본
FILES = {
    "characters/endministrator_f_fx.zip": "assets/characters/endministrator_f/endministrator_f_fx.zip",
    "characters/endministrator_m_fx.zip": "assets/characters/endministrator_m/endministrator_m_fx.zip",
    "characters/akekuri_fx.zip": "assets/characters/akekuri/akekuri_fx.zip",
    "characters/chen_qianyu_fx.zip": "assets/characters/chen_qianyu/chen_qianyu_fx.zip",
    "characters/arclight_fx.zip": "assets/characters/arclight/arclight_fx.zip",
    "characters/pogranichnik_fx.zip": "assets/characters/pogranichnik/pogranichnik_fx.zip",
    "enemies/rodin_fx.zip": "assets/enemies/rodin_fx.zip",
    # 캐릭터 고르기 아이콘(tools/make_icons.py로 공식 초상화에서 잘라 낸 그림)
    "characters/endministrator_f_icon.png": "assets/characters/endministrator_f/endministrator_f_icon.png",
    "characters/endministrator_m_icon.png": "assets/characters/endministrator_m/endministrator_m_icon.png",
    "characters/akekuri_icon.png": "assets/characters/akekuri/akekuri_icon.png",
    "characters/chen_qianyu_icon.png": "assets/characters/chen_qianyu/chen_qianyu_icon.png",
    "characters/arclight_icon.png": "assets/characters/arclight/arclight_icon.png",
    "characters/pogranichnik_icon.png": "assets/characters/pogranichnik/pogranichnik_icon.png",
}
FILES.update({target: BAKE_DIR + "/" + target for target in BAKED})

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bake():
    """원본이나 굽는 코드가 구운 파일보다 새로우면 다시 굽는다."""
    code_time = max(os.path.getmtime(os.path.join(ROOT, path)) for path in BAKE_CODE)
    jobs = []
    for target, source in BAKED.items():
        src = os.path.join(ROOT, source)
        out = os.path.join(ROOT, BAKE_DIR, target)
        if not os.path.isfile(src):
            sys.exit("에셋 파일이 없습니다: " + source)
        if not os.path.isfile(out) or os.path.getmtime(out) < max(os.path.getmtime(src), code_time):
            jobs += [src, out]
    if not jobs:
        return
    godot = os.environ.get("GODOT", "")
    if not godot or not os.path.isfile(godot):
        sys.exit("모델을 구우려면 Godot 위치를 GODOT 환경 변수로 알려 주세요.")
    print("모델 굽기: %d개" % (len(jobs) // 2))
    result = subprocess.run([godot, "--headless", "--path", ROOT, "--script", "res://tools/bake_models.gd", "--", *jobs])
    if result.returncode != 0:
        sys.exit("모델을 굽지 못했습니다.")


def remote_manifest():
    """릴리스에 지금 올라가 있는 목록: 경로 -> SHA-256 (없으면 빈 사전)"""
    result = gh("release", "download", RELEASE_TAG, "--repo", REPOSITORY, "--pattern", MANIFEST_NAME, "--output", "-",
                check=False)
    if result.returncode != 0:
        return {}
    try:
        return {entry["path"]: entry["sha256"] for entry in json.loads(result.stdout).get("files", [])}
    except (ValueError, KeyError, AttributeError):
        return {}


def gh(*args, check=True):
    result = subprocess.run(["gh", *args], capture_output=True, text=True, encoding="utf-8")
    if check and result.returncode != 0:
        sys.exit("gh %s 실패: %s" % (" ".join(args), result.stderr.strip()))
    return result


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_manifest():
    entries = []
    sources = []
    for target, source in FILES.items():
        path = os.path.join(ROOT, source)
        if not os.path.isfile(path):
            sys.exit("에셋 파일이 없습니다: " + source)
        entries.append({"path": target, "sha256": sha256(path), "asset": os.path.basename(target),
                        "size": os.path.getsize(path)})
        sources.append(path)
    names = [entry["asset"] for entry in entries]
    if len(set(names)) != len(names) or MANIFEST_NAME in names:
        sys.exit("릴리스 파일 이름(경로의 마지막 부분)이 겹칩니다: " + ", ".join(names))
    return {"files": entries}, sources


def ensure_private_repository(create):
    view = gh("repo", "view", REPOSITORY, "--json", "isPrivate", check=False)
    if view.returncode != 0:
        if not create:
            sys.exit("에셋 저장소 %s가 없습니다. --create를 붙이면 비공개로 만듭니다." % REPOSITORY)
        # 빈 저장소에는 릴리스를 만들 수 없어서 README로 첫 커밋을 만든다.
        gh("repo", "create", REPOSITORY, "--private", "--add-readme",
           "--description", "Crossfield private assets (not redistributable)")
        view = gh("repo", "view", REPOSITORY, "--json", "isPrivate")
    if not json.loads(view.stdout).get("isPrivate", False):
        sys.exit("에셋 저장소 %s가 공개입니다. 재배포할 수 없는 에셋이라 올리지 않습니다." % REPOSITORY)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="목록만 만들고 올리지 않는다")
    parser.add_argument("--create", action="store_true", help="에셋 저장소가 없으면 비공개로 만든다")
    options = parser.parse_args()

    bake()
    manifest, sources = build_manifest()
    out_dir = os.path.join(ROOT, "build", "asset_release")
    os.makedirs(out_dir, exist_ok=True)
    manifest_path = os.path.join(out_dir, MANIFEST_NAME)
    with open(manifest_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    for entry in manifest["files"]:
        print("%s  %s  %.1fMB" % (entry["sha256"][:12], entry["path"], entry["size"] / 1e6))
    if options.dry_run:
        print("목록만 만들었습니다: " + manifest_path)
        return

    ensure_private_repository(options.create)
    if gh("release", "view", RELEASE_TAG, "--repo", REPOSITORY, check=False).returncode != 0:
        gh("release", "create", RELEASE_TAG, "--repo", REPOSITORY, "--title", "Assets",
           "--notes", "Crossfield assets downloaded by the game (AssetUpdater). Not redistributable.")
    # 바뀐 파일을 먼저, 목록을 마지막에 올린다. 그 사이에 받아 간 게임은 SHA-256이 맞지 않아 다음에 다시 받는다.
    remote = remote_manifest()
    changed = [source for entry, source in zip(manifest["files"], sources) if remote.get(entry["path"]) != entry["sha256"]]
    if changed:
        print("바뀐 파일 %d개를 올립니다." % len(changed))
        gh("release", "upload", RELEASE_TAG, *changed, "--clobber", "--repo", REPOSITORY)
    gh("release", "upload", RELEASE_TAG, manifest_path, "--clobber", "--repo", REPOSITORY)
    print("올렸습니다: %s (릴리스 %s, 바뀐 파일 %d개)" % (REPOSITORY, RELEASE_TAG, len(changed)))


if __name__ == "__main__":
    main()
