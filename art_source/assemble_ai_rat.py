#!/usr/bin/env python3
"""Turn the isolated high-detail rat redraw into a clean 32 px game sheet."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source" / "modern_pose_refs" / "rat_idle_front_right.png"
OUTPUT = ROOT / "assets" / "rat_sheet.png"
CELL = 32
ANCHOR = (16, 30)
TARGET_SIZE = (30, 23)


def clean_source() -> Image.Image:
    original = Image.open(SOURCE).convert("RGBA")
    box = original.getbbox()
    if box is None:
        raise ValueError("rat source is empty")
    source = original.crop(box).resize(TARGET_SIZE, Image.Resampling.BOX)
    # Soft generation fringes are not pixels in the final game; keep a binary
    # silhouette, then reduce the surviving RGB pixels to a deliberate palette.
    alpha = source.getchannel("A").point(lambda value: 255 if value >= 150 else 0)
    rgb = source.convert("RGB").quantize(colors=12, method=Image.Quantize.FASTOCTREE).convert("RGB")
    result = Image.merge("RGBA", (*rgb.split(), alpha))
    # Image generation can leave fully transparent padding *inside* the crop.
    # The renderer's shadow is correctly centred on the declared foot anchor;
    # remove that padding so a low creature's visible feet meet that anchor too.
    visible = alpha.getbbox()
    if visible is None:
        raise ValueError("rat source lost all visible pixels during cleanup")
    return result.crop(visible)


def place(sprite: Image.Image, dx: int = 0, dy: int = 0) -> Image.Image:
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.alpha_composite(sprite, (ANCHOR[0] - sprite.width // 2 + dx, ANCHOR[1] - sprite.height + 1 + dy))
    return cell


def shift(frame: Image.Image, dx: int, dy: int = 0) -> Image.Image:
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.alpha_composite(frame, (dx, dy))
    return result


def hurt(frame: Image.Image) -> Image.Image:
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = frame.getpixel((x, y))
            if a: result.putpixel((x, y), (min(255, int(r * .7 + 70)), int(g * .58), int(b * .58), a))
    return shift(result, -1)


def fallen(frame: Image.Image, width: int, height: int, top: int) -> Image.Image:
    box = frame.getbbox()
    assert box is not None
    body = frame.crop(box).resize((width, height), Image.Resampling.NEAREST)
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.alpha_composite(body, ((CELL - width) // 2, top))
    return result


def main() -> None:
    base = clean_source()
    sheet = Image.new("RGBA", (CELL * 6, CELL * 9), (0, 0, 0, 0))
    # The source faces screen-right.  Mirroring supplies its opposing family;
    # modest weight/aim changes keep all six directions distinct and intact.
    for column in range(6):
        facing_left = column in (2, 3, 4)
        pose = base.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if facing_left else base
        idle = place(pose)
        walk_a = place(pose, -1 if facing_left else 1, 0)
        # World-space walking supplies the hop.  Sprite frames only shift their
        # weight sideways so every low creature keeps contact with its shadow.
        walk_b = place(pose, 1 if facing_left else -1)
        windup = place(pose, 1 if facing_left else -1)
        strike = place(pose, -2 if facing_left else 2, 0)
        frames = [idle, walk_a, walk_b, windup, strike, shift(idle, 1 if facing_left else -1), hurt(idle), fallen(hurt(idle), 23, 16, 13), fallen(idle, 30, 9, 21)]
        for row, frame in enumerate(frames): sheet.alpha_composite(frame, (column * CELL, row * CELL))
    if sheet.size != (192, 288) or any(sheet.crop((x * CELL, y * CELL, (x + 1) * CELL, (y + 1) * CELL)).getbbox() is None for y in range(9) for x in range(6)):
        raise ValueError("rat sheet contract failed")
    sheet.save(OUTPUT)
    print(f"wrote {OUTPUT}: {sheet.size[0]}x{sheet.size[1]} RGBA")


if __name__ == "__main__":
    main()
