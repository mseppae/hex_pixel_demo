#!/usr/bin/env python3
"""Assemble the native 32px item atlas, replacing cells as source art arrives."""

from pathlib import Path

from PIL import Image

import modern_item_icons as legacy


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SOURCES = ROOT / "art_source" / "item_pose_refs"
CELL = 32
SOURCE_BY_COLUMN = {
    0: "gold.png", 1: "healing_potion.png", 2: "short_sword.png", 3: "goblin_dagger.png", 4: "spiked_club.png",
    5: "longsword.png", 6: "leather_armor.png", 7: "chain_shirt.png",
    8: "town_portal_scroll.png",
    39: "wooden_shield.png", 40: "helmet.png",
    34: "hand_axe.png", 35: "mace.png",
    36: "war_hammer.png", 37: "spear.png",
    38: "rapier.png", 41: "antidote.png",
}
TROPHY_SOURCE_BY_FORM = ("trophy_ear.png", "trophy_fang.png", "trophy_tusk.png", "trophy_claw.png", "trophy_skull.png")
TROPHY_FAMILY_COLORS = ((87, 169, 74), (192, 108, 61), (144, 88, 175), (70, 137, 164), (184, 148, 61))
CHARM_COLORS = ((86, 166, 219), (207, 91, 113), (91, 176, 96), (177, 113, 210), (233, 188, 70))


def source_icon(name: str) -> Image.Image:
    image = Image.open(SOURCES / name).convert("RGBA")
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError(f"{name}: empty alpha")
    image = image.crop(box)
    scale = min(28 / image.width, 28 / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    image = image.resize(size, Image.Resampling.BOX)
    alpha = image.getchannel("A").point(lambda value: 255 if value >= 150 else 0)
    rgb = image.convert("RGB").quantize(colors=18, method=Image.Quantize.FASTOCTREE).convert("RGB")
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.paste(rgb, ((CELL - size[0]) // 2, (CELL - size[1]) // 2), alpha)
    return result


def trophy_icon(form: int, family: int) -> Image.Image:
    """Keep each generated trophy silhouette while giving each monster its color."""
    result = source_icon(TROPHY_SOURCE_BY_FORM[form])
    tint = TROPHY_FAMILY_COLORS[family]
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = result.getpixel((x, y))
            if not a or r + g + b < 110:
                continue
            intensity = (r + g + b) / (255 * 3)
            result.putpixel((x, y), (round(tint[0] * intensity), round(tint[1] * intensity), round(tint[2] * intensity), a))
    return result


def charm_icon(index: int) -> Image.Image:
    result = source_icon("charm.png")
    tint = CHARM_COLORS[index]
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = result.getpixel((x, y))
            if a and r + g + b > 330:
                result.putpixel((x, y), (tint[0], tint[1], tint[2], a))
    return result


def main() -> None:
    # Existing non-source cells stay at their current artwork, centred and
    # nearest-upscaled only until their own detailed source is available.
    legacy_icons = legacy.build_icons()
    atlas = Image.new("RGBA", (CELL * len(legacy_icons), CELL), (0, 0, 0, 0))
    for column, icon in enumerate(legacy_icons):
        if column in SOURCE_BY_COLUMN:
            icon = source_icon(SOURCE_BY_COLUMN[column])
        elif 9 <= column <= 33:
            icon = trophy_icon((column - 9) % 5, (column - 9) // 5)
        elif 42 <= column <= 46:
            icon = charm_icon(column - 42)
        else:
            icon = icon.resize((32, 32), Image.Resampling.NEAREST)
        atlas.alpha_composite(icon, (column * CELL, 0))
    atlas.save(ASSETS / "item_icons.png")
    print(f"item_icons.png: {atlas.size[0]}x{atlas.size[1]} RGBA, {len(legacy_icons)} cells")


if __name__ == "__main__":
    main()
