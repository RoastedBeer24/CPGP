"""캐릭터 모델 같은 에셋을 비공개 에셋 저장소의 릴리스에 올린다. 게임(AssetUpdater)이 켤 때 받아 간다.

    python3 tools/publish_assets.py             # 올리기
    python3 tools/publish_assets.py --dry-run   # 목록(assets.json)만 만들어 보기
    python3 tools/publish_assets.py --create    # 에셋 저장소가 없으면 비공개로 만들고 올리기

- 올리는 파일은 아래 FILES에 적는다. 경로는 실행 파일 폴더 기준이다(게임이 그 자리에 넣는다).
- 재배포할 수 없는 에셋이라 저장소가 비공개인지 먼저 확인하고, 공개면 올리지 않는다.
- 게임은 목록(assets.json)의 SHA-256과 자기 파일을 비교해 다른 파일만 받는다. 파일을 먼저 올리고 목록을 마지막에 올린다.
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

# 실행 파일 폴더 기준 경로 -> 저장소(작업 폴더) 안의 원본
FILES = {
    "characters/endministrator_f.glb": "assets/characters/endministrator_f/endministrator_f.glb",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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
           "--description", "CyberUniverse private assets (not redistributable)")
        view = gh("repo", "view", REPOSITORY, "--json", "isPrivate")
    if not json.loads(view.stdout).get("isPrivate", False):
        sys.exit("에셋 저장소 %s가 공개입니다. 재배포할 수 없는 에셋이라 올리지 않습니다." % REPOSITORY)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="목록만 만들고 올리지 않는다")
    parser.add_argument("--create", action="store_true", help="에셋 저장소가 없으면 비공개로 만든다")
    options = parser.parse_args()

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
           "--notes", "CyberUniverse assets downloaded by the game (AssetUpdater). Not redistributable.")
    # 파일을 먼저, 목록을 마지막에 올린다. 그 사이에 받아 간 게임은 SHA-256이 맞지 않아 다음에 다시 받는다.
    gh("release", "upload", RELEASE_TAG, *sources, "--clobber", "--repo", REPOSITORY)
    gh("release", "upload", RELEASE_TAG, manifest_path, "--clobber", "--repo", REPOSITORY)
    print("올렸습니다: %s (릴리스 %s)" % (REPOSITORY, RELEASE_TAG))


if __name__ == "__main__":
    main()
