#!/usr/bin/env python3
"""Build the corpse and chest atlas from the current creature-sheet death poses."""

from pathlib import Path

from PIL import Image

import objects as old


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
old.MATERIALS.update({
    "rat": ((116, 93, 70, 255), (158, 128, 96, 255), (75, 58, 45, 255)),
    "bat": ((95, 68, 96, 255), (138, 98, 142, 255), (56, 39, 60, 255)),
    "spider": ((60, 50, 83, 255), (91, 76, 123, 255), (38, 29, 54, 255)),
    "slime": ((68, 139, 97, 255), (118, 192, 136, 255), (40, 88, 62, 255)),
    "mushroom": ((162, 65, 69, 255), (211, 102, 100, 255), (104, 38, 44, 255)),
    "stone": ((110, 112, 119, 255), (160, 164, 172, 255), (70, 72, 80, 255)),
    "troll": ((96, 112, 62, 255), (137, 153, 87, 255), (57, 67, 38, 255)),
})


def layer(material, width, height):
    return old.Layer(material, width, height)


def small_rat():
    w, h = 32, 16
    return old.compose(w, h, [
        layer("rat", w, h).line(10, 10, 2, 4, 1.2),
        layer("rat", w, h).ellipse(15, 10, 9, 4.2),
        layer("rat", w, h).ellipse(24, 8, 4.5, 3.5),
        layer("rat", w, h).ellipse(21, 5, 2, 1.7),
        layer("rat", w, h).rect(11, 12, 14, 14).rect(19, 12, 22, 14),
    ], {(26, 7): "eye_x", (29, 10): "tusk"})


def small_bat():
    w, h = 32, 16
    wing = layer("bat", w, h)
    wing.line(16, 8, 3, 3, 2.2).line(3, 3, 7, 13, 1.8)
    wing.line(16, 8, 29, 3, 2.2).line(29, 3, 25, 13, 1.8)
    return old.compose(w, h, [wing, layer("bat", w, h).ellipse(16, 9, 4.2, 5), layer("bat", w, h).ellipse(16, 4, 3, 2.8)], {(15, 4): "eye_x", (17, 4): "eye_x"})


def small_spider():
    w, h = 32, 16
    parts = []
    for side in (-1, 1):
        for y, reach in ((5, 11), (8, 14), (11, 12), (13, 9)):
            parts.append(layer("spider", w, h).line(16, 9, 16 + side * reach, y, 1.2))
    parts += [layer("spider", w, h).ellipse(12, 9, 6, 4.5), layer("spider", w, h).ellipse(20, 9, 4, 3.5)]
    return old.compose(w, h, parts, {(20, 8): "shine", (22, 8): "shine"})


def small_slime():
    w, h = 32, 16
    return old.compose(w, h, [layer("slime", w, h).ellipse(16, 11, 13, 4.4), layer("slime", w, h).ellipse(10, 8, 5, 3)], {(10, 8): "shine", (18, 11): "shine"})


def small_mushroom():
    w, h = 32, 16
    return old.compose(w, h, [layer("mushroom", w, h).rect(13, 7, 19, 14), layer("parchment", w, h).rect(14, 9, 18, 14), layer("mushroom", w, h).ellipse(16, 6, 11, 4)], {(10, 5): "shine", (17, 4): "shine", (22, 6): "shine"})


def small_skeleton():
    w, h = 32, 16
    bone = layer("bone", w, h)
    bone.line(6, 12, 26, 4, 1.7).line(8, 4, 24, 13, 1.7).ellipse(7, 4, 3.5, 3.2)
    return old.compose(w, h, [bone], {(6, 3): "eye_x", (8, 3): "eye_x"})


def fit(image, width, height):
    box = image.getbbox()
    assert box is not None
    image = image.crop(box)
    factor = min(width / image.width, height / image.height)
    image = image.resize((round(image.width * factor), round(image.height * factor)), Image.Resampling.NEAREST)
    result = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    result.alpha_composite(image, ((width - image.width) // 2, height - image.height))
    return result


def death_from_sheet(filename, cell_width, cell_height, width, height):
    """Use the real final death pose rather than a legacy corpse drawing."""
    sheet = Image.open(ASSETS / filename).convert("RGBA")
    # Every runtime creature contract uses column 5 for front-right and row 8
    # for its fully grounded corpse pose.
    frame = sheet.crop((5 * cell_width, 8 * cell_height, 6 * cell_width, 9 * cell_height))
    alpha_bounds = frame.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise ValueError(f"{filename}: missing grounded death pose")
    return fit(frame.crop(alpha_bounds), width, height)


def build():
    sheet = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    # These are the actual grounded death frames used by the character renderer.
    # Keeping corpses derived from them prevents an atlas from silently falling out
    # of date whenever a creature sheet is refreshed.
    small = [
        death_from_sheet("goblin_sheet.png", 32, 32, 32, 16),
        death_from_sheet("adventurer_sheet.png", 32, 32, 32, 16),
        death_from_sheet("rat_sheet.png", 32, 32, 32, 16),
        death_from_sheet("bat_sheet.png", 32, 32, 32, 16),
        death_from_sheet("spider_sheet.png", 32, 32, 32, 16),
        death_from_sheet("slime_sheet.png", 32, 32, 32, 16),
        death_from_sheet("mushroom_sheet.png", 32, 32, 32, 16),
        death_from_sheet("skeleton_sheet.png", 32, 32, 32, 16),
    ]
    for index, image in enumerate(small): sheet.alpha_composite(image, (index * 32, 0))
    large = [
        death_from_sheet("ogre_sheet.png", 40, 48, 64, 32),
        death_from_sheet("troll_sheet.png", 48, 64, 64, 32),
        death_from_sheet("golem_sheet.png", 48, 64, 64, 32),
    ]
    for index, image in enumerate(large): sheet.alpha_composite(image, (index * 64, 24))
    sheet.alpha_composite(fit(old.chest(False), 32, 28), (192, 24))
    sheet.alpha_composite(fit(old.chest(True), 32, 28), (224, 24))
    return sheet


if __name__ == "__main__":
    atlas = build()
    atlas.save(ASSETS / "objects.png")
    print(f"objects.png: {atlas.size[0]}x{atlas.size[1]} RGBA")
