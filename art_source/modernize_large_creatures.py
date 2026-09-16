#!/usr/bin/env python3
"""Assemble the troll and golem on the 48x64 large-creature sheet contract."""

from pathlib import Path

from PIL import Image

from creatures_deep import golem, troll
from creatures_new import build_sheet


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
CELL_W, CELL_H = 48, 64
COLS, ROWS = 6, 9
ANCHOR = (24, 60)
CREATURES = {
    "troll_sheet.png": (troll, 40, 52, (45, 56)),
    "golem_sheet.png": (golem, 44, 54, (46, 57)),
}


def place(source: Image.Image, maximum: tuple[int, int]) -> Image.Image:
    box = source.getbbox()
    if box is None:
        raise ValueError("empty source pose")
    silhouette = source.crop(box)
    factor = min(maximum[0] / silhouette.width, maximum[1] / silhouette.height)
    size = (max(1, round(silhouette.width * factor)), max(1, round(silhouette.height * factor)))
    silhouette = silhouette.resize(size, Image.Resampling.NEAREST)
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    cell.alpha_composite(silhouette, (ANCHOR[0] - size[0] // 2, ANCHOR[1] - size[1] + 1))
    return cell


def tint_recoil(frame: Image.Image, dx: int) -> Image.Image:
    result = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    for y in range(CELL_H):
        for x in range(CELL_W):
            r, g, b, a = frame.getpixel((x, y))
            if a:
                result.putpixel((x, y), (min(255, int(r * .72 + 58)), int(g * .68), int(b * .68), a))
    shifted = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    shifted.alpha_composite(result, (dx, 0))
    return shifted


def defeated(frame: Image.Image, size: tuple[int, int], y: int) -> Image.Image:
    box = frame.getbbox()
    assert box is not None
    body = frame.crop(box).resize(size, Image.Resampling.NEAREST)
    result = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    result.alpha_composite(body, ((CELL_W - size[0]) // 2, y))
    return result


def build(draw, source_w: int, source_h: int, maximum: tuple[int, int]) -> Image.Image:
    legacy = build_sheet(source_w, source_h, draw)
    sheet = Image.new("RGBA", (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    for column in range(COLS):
        base = []
        for row in range(5):
            source = legacy.crop((column * source_w, row * source_h, (column + 1) * source_w, (row + 1) * source_h))
            base.append(place(source, maximum))
        idle_b = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        idle_b.alpha_composite(base[0], (-2 if column in (0, 1, 5) else 2, 0))
        frames = base + [idle_b, tint_recoil(base[0], -2 if column in (0, 1, 5) else 2), defeated(base[0], (35, 34), 23), defeated(base[0], (46, 16), 43)]
        for row, frame in enumerate(frames):
            if frame.getbbox() is None:
                raise ValueError(f"empty cell {column},{row}")
            sheet.alpha_composite(frame, (column * CELL_W, row * CELL_H))
    return sheet


def main() -> None:
    for name, values in CREATURES.items():
        image = build(*values)
        if image.size != (CELL_W * COLS, CELL_H * ROWS):
            raise ValueError(f"{name}: wrong size")
        image.save(ASSETS / name)
        print(f"{name}: {image.size[0]}x{image.size[1]} RGBA, 6x9 cells")


if __name__ == "__main__":
    main()
