"""캐릭터 고르기 아이콘을 만든다: 공식 초상화(!File/Portraits/)에서 얼굴 부분을 정사각형으로 잘라 256px PNG로
assets/characters/<이름>/<이름>_icon.png에 둔다. 원작 그림이라 모델처럼 비공개 에셋 저장소에만 올린다
(tools/publish_assets.py의 FILES).

    python tools/make_icons.py            # 모든 캐릭터
    python tools/make_icons.py akekuri    # 고른 캐릭터만

Pillow가 있어야 한다(이 PC는 python3에 없고 python에 있다).
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 256
# 캐릭터 -> (초상화 파일, 자를 정사각형 (왼쪽, 위, 오른쪽, 아래)). 초상화는 900x352에 배경이 투명하다.
PORTRAITS = {
    "endministrator_f": ("endministrator_f.webp", (280, 10, 590, 320)),
    "endministrator_m": ("endministrator_m.png", (295, 0, 615, 320)),
    "akekuri": ("akekuri.png", (290, 0, 630, 340)),
}


def main():
    for character in sys.argv[1:] or list(PORTRAITS):
        name, box = PORTRAITS[character]
        source = os.path.join(ROOT, "!File", "Portraits", name)
        if not os.path.isfile(source):
            print("초상화가 없어 건너뜀:", source)
            continue
        folder = os.path.join(ROOT, "assets", "characters", character)
        os.makedirs(folder, exist_ok=True)
        image = Image.open(source).convert("RGBA").crop(box).resize((SIZE, SIZE), Image.LANCZOS)
        target = os.path.join(folder, character + "_icon.png")
        image.save(target)
        print("아이콘:", os.path.relpath(target, ROOT))


if __name__ == "__main__":
    main()
