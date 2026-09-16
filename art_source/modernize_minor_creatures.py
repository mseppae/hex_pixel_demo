#!/usr/bin/env python3
"""Build the small-creature sheets on the current 32 px / 6x9 contract.

The source silhouettes are deliberately redrawn in creatures_new.py and
creatures_set2.py.  This assembler gives each one a consistent canvas, planted
anchor, and complete idle/walk/attack/hurt/death set instead of preserving the
old mixed 14--24 px 6x5 atlases.
"""

from pathlib import Path

from PIL import Image

from creatures_new import build_sheet, rat, skeleton, spider
from creatures_set2 import bat, slime, mushroom


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
CELL = 32
COLS = 6
ROWS = 9
ANCHOR = (16, 30)

# name: source drawing, original canvas, maximum modern silhouette size.
CREATURES = {
    "rat_sheet.png":      (rat,      20, 16, (29, 22)),
    "bat_sheet.png":      (bat,      18, 16, (30, 24)),
    "spider_sheet.png":   (spider,   22, 18, (31, 23)),
    "slime_sheet.png":    (slime,    18, 14, (29, 22)),
    "mushroom_sheet.png": (mushroom, 16, 22, (25, 30)),
    "skeleton_sheet.png": (skeleton, 16, 24, (26, 30)),
}


def rescale_to_cell(source: Image.Image, maximum: tuple[int, int]) -> Image.Image:
    """Expand the hand-drawn silhouette with nearest pixels, never a blurry atlas resize."""
    bounds = source.getbbox()
    if bounds is None:
        raise ValueError("empty source pose")
    silhouette = source.crop(bounds)
    scale = min(maximum[0] / silhouette.width, maximum[1] / silhouette.height)
    size = (max(1, round(silhouette.width * scale)), max(1, round(silhouette.height * scale)))
    silhouette = silhouette.resize(size, Image.Resampling.NEAREST)
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.alpha_composite(silhouette, (ANCHOR[0] - size[0] // 2, ANCHOR[1] - size[1] + 1))
    return result


def shifted(frame: Image.Image, dx: int, dy: int = 0) -> Image.Image:
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.alpha_composite(frame, (dx, dy))
    return result


def hurt(frame: Image.Image) -> Image.Image:
    """A compact red recoil read, with no detached pixels or moving anchor."""
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = frame.getpixel((x, y))
            if a:
                result.putpixel((x, y), (min(255, int(r * .72 + 64)), int(g * .65), int(b * .65), a))
    return shifted(result, -1)


def death_start(frame: Image.Image) -> Image.Image:
    bounds = frame.getbbox()
    assert bounds is not None
    body = frame.crop(bounds).resize((22, 18), Image.Resampling.NEAREST)
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.alpha_composite(body, (5, 12))
    return result


def death_down(frame: Image.Image) -> Image.Image:
    bounds = frame.getbbox()
    assert bounds is not None
    body = frame.crop(bounds).resize((30, 10), Image.Resampling.NEAREST)
    result = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    result.alpha_composite(body, (1, 20))
    return result


def build_modern_sheet(draw, width: int, height: int, maximum: tuple[int, int]) -> Image.Image:
    legacy = build_sheet(width, height, draw)
    sheet = Image.new("RGBA", (CELL * COLS, CELL * ROWS), (0, 0, 0, 0))
    for column in range(COLS):
        poses = []
        for row in range(5):
            source = legacy.crop((column * width, row * height, (column + 1) * width, (row + 1) * height))
            poses.append(rescale_to_cell(source, maximum))
        idle = poses[0]
        frames = poses + [shifted(idle, -1 if column in (0, 1, 5) else 1), hurt(idle), death_start(idle), death_down(idle)]
        for row, frame in enumerate(frames):
            sheet.alpha_composite(frame, (column * CELL, row * CELL))
    return sheet


def validate(image: Image.Image, name: str) -> None:
    if image.size != (CELL * COLS, CELL * ROWS) or image.mode != "RGBA":
        raise ValueError(f"{name}: wrong sheet contract")
    for row in range(ROWS):
        for column in range(COLS):
            cell = image.crop((column * CELL, row * CELL, (column + 1) * CELL, (row + 1) * CELL))
            if cell.getbbox() is None:
                raise ValueError(f"{name}: empty cell {column},{row}")
            if cell.getbbox()[3] > ANCHOR[1] + 1:
                raise ValueError(f"{name}: pixels below anchor in {column},{row}")


def main() -> None:
    for name, (draw, width, height, maximum) in CREATURES.items():
        sheet = build_modern_sheet(draw, width, height, maximum)
        validate(sheet, name)
        sheet.save(ASSETS / name)
        print(f"{name}: {sheet.size[0]}x{sheet.size[1]} RGBA, 6x9 cells")


if __name__ == "__main__":
    main()
