#!/usr/bin/env python3
"""生成 AppIcon（1024x1024 PNG），只在本机重新生成图标时用到。

依赖：Pillow（`python -m pip install pillow`）。
用法：`python scripts/make-app-icon.py`

产物：Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
运行时不需要它；App 打包只引用 PNG，不引用本脚本。
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

SIZE = 1024
ACCENT_TOP = (77, 107, 254)
ACCENT_BOTTOM = (37, 58, 156)
INK = (255, 255, 255, 255)


def lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def build_gradient() -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE), ACCENT_BOTTOM)
    draw = ImageDraw.Draw(image)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        draw.line(
            [(0, y), (SIZE, y)],
            fill=(
                lerp(ACCENT_TOP[0], ACCENT_BOTTOM[0], t),
                lerp(ACCENT_TOP[1], ACCENT_BOTTOM[1], t),
                lerp(ACCENT_TOP[2], ACCENT_BOTTOM[2], t),
            ),
        )
    return image


def main() -> None:
    image = build_gradient().convert("RGBA")
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # 终端窗口：圆角描边 + 内部 ">_" 提示符
    margin = 196
    box = (margin, margin + 26, SIZE - margin, SIZE - margin - 26)
    draw.rounded_rectangle(box, radius=116, outline=INK, width=34)

    # 顶部三个小圆点（窗口按钮）
    dot_y = box[1] + 74
    for index in range(3):
        dot_x = box[0] + 82 + index * 62
        draw.ellipse((dot_x - 13, dot_y - 13, dot_x + 13, dot_y + 13), fill=INK)

    # ">" 提示符
    draw.line([(372, 470), (474, 560)], fill=INK, width=36, joint="curve")
    draw.line([(474, 560), (372, 650)], fill=INK, width=36, joint="curve")

    # "_" 光标
    draw.rectangle((508, 618, 664, 650), fill=INK)

    image = Image.alpha_composite(image, overlay)

    target_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "Sources",
        "Resources",
        "Assets.xcassets",
        "AppIcon.appiconset",
    )
    os.makedirs(target_dir, exist_ok=True)
    target = os.path.join(target_dir, "AppIcon-1024.png")
    image.convert("RGB").save(target, format="PNG", optimize=True)
    print("wrote", target, image.size)


if __name__ == "__main__":
    main()
