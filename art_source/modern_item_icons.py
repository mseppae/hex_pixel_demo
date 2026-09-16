#!/usr/bin/env python3
"""Build the complete 47-item runtime atlas at the modern 20 px icon size."""

from pathlib import Path

from PIL import Image, ImageDraw

import items_new
import objects as old


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
CELL = 20


def modern_icon(kind: str) -> Image.Image:
    """Native 20px replacement art for the nine common inventory items."""
    image = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outline, steel, steel_hi = (24, 22, 29, 255), (132, 145, 160, 255), (232, 238, 242, 255)
    leather, leather_hi, gold = (100, 58, 34, 255), (177, 111, 61, 255), (238, 190, 61, 255)
    red, blue, paper = (198, 54, 54, 255), (70, 124, 183, 255), (224, 207, 158, 255)
    def polygon(points, fill, width=1):
        draw.polygon(points, fill=fill); draw.line(points + [points[0]], fill=outline, width=width)
    if kind == "gold":
        for x, y in ((6, 12), (11, 10), (4, 14)):
            draw.ellipse((x, y, x + 8, y + 5), fill=gold, outline=outline)
            draw.line((x + 2, y + 1, x + 6, y + 1), fill=(255, 232, 116, 255))
    elif kind == "potion":
        draw.rectangle((8, 2, 11, 6), fill=paper, outline=outline); draw.rectangle((7, 5, 12, 8), fill=steel, outline=outline)
        draw.rounded_rectangle((5, 7, 14, 17), radius=3, fill=red, outline=outline); draw.rectangle((7, 9, 8, 14), fill=(255, 176, 154, 255))
    elif kind in ("short_sword", "dagger", "longsword"):
        # A vertical blade plus obvious crossguard survives 20px much better
        # than the earlier diagonal line, which read like a wand in-game.
        top = 2 if kind == "longsword" else (5 if kind == "short_sword" else 7)
        width = 4 if kind == "longsword" else 3
        polygon([(10, top), (10 - width, top + 4), (10 - 1, 14), (10 + 1, 14), (10 + width, top + 4)], steel)
        draw.line((10, top + 2, 10, 13), fill=steel_hi, width=1)
        guard = gold if kind != "dagger" else leather
        draw.line((4 if kind != "dagger" else 6, 14, 16 if kind != "dagger" else 14, 14), fill=outline, width=3)
        draw.line((4 if kind != "dagger" else 6, 14, 16 if kind != "dagger" else 14, 14), fill=guard, width=1)
        draw.line((10, 15, 10, 18), fill=outline, width=3); draw.line((10, 15, 10, 18), fill=leather, width=1)
    elif kind == "club":
        draw.line((5, 16, 13, 7), fill=outline, width=5); draw.line((5, 16, 13, 7), fill=leather, width=3)
        draw.ellipse((10, 3, 18, 10), fill=(91, 70, 58, 255), outline=outline); draw.line((12, 4, 16, 5), fill=leather_hi)
    elif kind == "leather":
        polygon([(5, 4), (14, 4), (17, 8), (14, 17), (5, 17), (2, 8)], leather)
        draw.line((7, 5, 7, 15), fill=leather_hi); draw.line((12, 5, 12, 15), fill=(72, 42, 28, 255))
    elif kind == "chain":
        polygon([(5, 4), (14, 4), (17, 8), (14, 17), (5, 17), (2, 8)], steel)
        for y in range(7, 16, 3):
            draw.line((5, y, 14, y), fill=steel_hi); draw.point((7, y + 1), fill=outline)
    elif kind == "scroll":
        # Rolled ends and a central portal spiral keep this from reading as a
        # plain document when shown at native scale in an inventory slot.
        draw.rectangle((5, 5, 15, 15), fill=paper, outline=outline)
        draw.ellipse((4, 3, 16, 7), fill=paper, outline=outline)
        draw.ellipse((4, 13, 16, 17), fill=paper, outline=outline)
        draw.arc((7, 7, 13, 13), 35, 330, fill=blue, width=2)
        draw.point((10, 10), fill=(238, 244, 255, 255))
    return image


def fit(image: Image.Image) -> Image.Image:
    box = image.getbbox()
    assert box is not None
    image = image.crop(box)
    factor = min((CELL - 2) / image.width, (CELL - 2) / image.height)
    image = image.resize((round(image.width * factor), round(image.height * factor)), Image.Resampling.NEAREST)
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.alpha_composite(image, ((CELL - image.width) // 2, (CELL - image.height) // 2))
    return result


def tint(image: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    result = image.copy()
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = result.getpixel((x, y))
            if a and r + g + b > 180:
                result.putpixel((x, y), ((r + color[0]) // 2, (g + color[1]) // 2, (b + color[2]) // 2, a))
    return result


def trophy(form: int, color: tuple[int, int, int]) -> Image.Image:
    """Five legible trophy forms, each recoloured for its monster family."""
    image = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outline = (24, 22, 29, 255)
    hi = tuple(min(255, channel + 55) for channel in color) + (255,)
    base = color + (255,)
    dark = tuple(max(0, channel - 55) for channel in color) + (255,)
    def poly(points): draw.polygon(points, fill=base); draw.line(points + [points[0]], fill=outline, width=1)
    if form == 0:  # ear
        poly([(6, 15), (5, 8), (9, 3), (14, 5), (13, 12), (10, 17)])
        draw.line((8, 13, 10, 7), fill=hi, width=2)
    elif form == 1:  # fang
        poly([(8, 3), (14, 5), (12, 15), (9, 18), (7, 12)])
        draw.line((10, 6, 10, 14), fill=hi)
    elif form == 2:  # tusk
        poly([(5, 3), (12, 4), (15, 9), (12, 16), (7, 18), (10, 11), (6, 8)])
        draw.line((7, 5, 12, 9), fill=hi, width=2)
    elif form == 3:  # claw
        poly([(5, 16), (6, 8), (9, 4), (10, 11), (13, 3), (14, 10), (16, 7), (15, 16)])
        draw.line((8, 14, 8, 8), fill=hi); draw.line((12, 14, 13, 8), fill=dark)
    else:  # skull
        draw.ellipse((4, 3, 16, 14), fill=base, outline=outline)
        draw.rectangle((7, 11, 14, 17), fill=base, outline=outline)
        draw.rectangle((7, 8, 9, 10), fill=outline); draw.rectangle((12, 8, 14, 10), fill=outline)
        draw.line((8, 14, 13, 14), fill=hi)
    return image


def trophy_set() -> list[Image.Image]:
    palettes = [(86, 163, 75), (186, 97, 57), (133, 82, 166), (69, 127, 153), (176, 137, 57)]
    return [trophy(form, color) for color in palettes for form in range(5)]


def advanced_icon(kind: int) -> Image.Image:
    """Eight distinct equipment silhouettes designed directly on the 20px grid."""
    image = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    o, s, sh, wood, gold = (24, 22, 29, 255), (132, 145, 160, 255), (228, 236, 241, 255), (117, 71, 40, 255), (225, 183, 63, 255)
    if kind == 0: d.line((5, 16, 12, 7), fill=o, width=5); d.line((5, 16, 12, 7), fill=wood, width=3); d.polygon([(10, 3), (18, 6), (13, 11)], fill=s, outline=o)
    elif kind == 1: d.line((6, 16, 13, 9), fill=o, width=5); d.line((6, 16, 13, 9), fill=wood, width=3); d.ellipse((9, 3, 17, 11), fill=s, outline=o); d.ellipse((11, 4, 13, 6), fill=sh)
    elif kind == 2: d.line((5, 16, 13, 8), fill=o, width=6); d.line((5, 16, 13, 8), fill=wood, width=3); d.rectangle((9, 3, 17, 10), fill=s, outline=o); d.line((11, 4, 15, 4), fill=sh, width=2)
    elif kind == 3: d.line((5, 17, 16, 3), fill=o, width=4); d.line((5, 17, 16, 3), fill=sh, width=2); d.line((4, 14, 9, 18), fill=wood, width=3)
    elif kind == 4: d.line((5, 16, 15, 4), fill=o, width=4); d.line((5, 16, 15, 4), fill=sh, width=2); d.line((4, 13, 10, 18), fill=gold, width=2)
    elif kind == 5: d.polygon([(10, 2), (17, 6), (15, 16), (10, 18), (4, 14), (4, 6)], fill=wood, outline=o); d.ellipse((8, 8, 12, 12), fill=s, outline=o)
    elif kind == 6: d.pieslice((4, 2, 16, 16), 180, 360, fill=s, outline=o); d.rectangle((5, 9, 15, 14), fill=s, outline=o); d.line((7, 7, 13, 7), fill=sh, width=2)
    else: d.rounded_rectangle((5, 5, 15, 17), radius=3, fill=(78, 167, 104, 255), outline=o); d.rectangle((8, 2, 12, 6), fill=gold, outline=o); d.line((8, 10, 12, 10), fill=(184, 245, 157, 255))
    return image


def charm(index: int) -> Image.Image:
    colors = [(104, 167, 217, 255), (205, 92, 115, 255), (94, 171, 96, 255), (172, 116, 208, 255), (232, 190, 72, 255)]
    image = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)); d = ImageDraw.Draw(image)
    c, o = colors[index], (24, 22, 29, 255)
    d.line((10, 2, 10, 6), fill=o, width=2); d.ellipse((4, 5, 16, 17), fill=c, outline=o)
    d.ellipse((7, 8, 13, 14), outline=(238, 238, 220, 255), width=1)
    d.point((9, 9), fill=(255, 255, 255, 255))
    return image


def build_icons() -> list[Image.Image]:
    base = [
        lambda: modern_icon("gold"), lambda: modern_icon("potion"), lambda: modern_icon("short_sword"),
        lambda: modern_icon("dagger"), lambda: modern_icon("club"), lambda: modern_icon("longsword"),
        lambda: modern_icon("leather"), lambda: modern_icon("chain"), lambda: modern_icon("scroll"),
    ]
    return [draw() for draw in base] + trophy_set() + [advanced_icon(index) for index in range(8)] + [charm(index) for index in range(5)]


if __name__ == "__main__":
    icons = build_icons()
    if len(icons) != 47:
        raise ValueError(f"expected 47 icons, got {len(icons)}")
    sheet = Image.new("RGBA", (CELL * len(icons), CELL), (0, 0, 0, 0))
    for index, icon in enumerate(icons): sheet.alpha_composite(icon, (index * CELL, 0))
    sheet.save(ASSETS / "item_icons.png")
    print(f"item_icons.png: {sheet.size[0]}x{sheet.size[1]} RGBA, {len(icons)} cells")
