#!/usr/bin/env python3
"""Assemble the modern Ogre from isolated generated pose triptychs.

Each source image contains three intentionally separated, full-body references:
right, back-right, and front-right.  This script crops each independently,
reduces it with BOX sampling, thresholds alpha, limits the palette, and places
it in an exact 40x48 cell.  The remaining engine directions are true mirrors
of their corresponding views; no generated atlas boundaries are sampled.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SOURCES = ROOT / "art_source" / "ogre_modern_poses"
CONTRACT = json.loads((ASSETS / "ogre_sprite_contract.json").read_text())
CELL_W, CELL_H = CONTRACT["frame_size"]
COLS, ROWS = CONTRACT["grid"]
ANCHOR_X, ANCHOR_Y = CONTRACT["anchor"]
POSES = tuple(CONTRACT["rows"])


def threshold_alpha(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    rgb = image.convert("RGB").quantize(colors=28, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGB")
    result = Image.new("RGBA", image.size, (0, 0, 0, 0))
    result.paste(rgb, mask=alpha)
    return result


def components(cell: Image.Image) -> list[set[tuple[int, int]]]:
    remaining = {(x, y) for y in range(CELL_H) for x in range(CELL_W) if cell.getpixel((x, y))[3]}
    found = []
    while remaining:
        component = {remaining.pop()}
        pending = list(component)
        while pending:
            x, y = pending.pop()
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.add(neighbor)
                    pending.append(neighbor)
        found.append(component)
    return found


def clean_silhouette(cell: Image.Image) -> Image.Image:
    """Reject speckles and join any separately generated held-weapon component."""
    cleaned = cell.copy()
    for component in components(cleaned):
        if len(component) <= 16:
            for x, y in component:
                cleaned.putpixel((x, y), (0, 0, 0, 0))

    # A detached club is still part of one pose.  Connect it to the nearest body
    # pixel with the component's own colour, then repeat until one silhouette remains.
    while True:
        parts = components(cleaned)
        if len(parts) <= 1:
            return cleaned
        main = max(parts, key=len)
        part = max((candidate for candidate in parts if candidate is not main), key=len)
        first, second = min(((a, b) for a in main for b in part), key=lambda pair: abs(pair[0][0] - pair[1][0]) + abs(pair[0][1] - pair[1][1]))
        color = cleaned.getpixel(second)
        ImageDraw.Draw(cleaned).line((first, second), fill=color, width=2)


def extract_pose(path: Path, view: int) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    left = source.width * view // 3
    right = source.width * (view + 1) // 3
    segment = source.crop((left, 0, right, source.height))
    bounds = segment.getbbox()
    if bounds is None:
        raise ValueError(f"{path.name}: empty view {view}")
    silhouette = segment.crop(bounds)
    # The forward view carries the club beside the broadest part of the body.
    # Leave a real safety margin there; previously its far pixels landed on the
    # cell edge and appeared to vanish during the forward walk frames.
    horizontal_padding = 4 if view == 2 else 2
    scale = min((CELL_W - horizontal_padding) / silhouette.width, (ANCHOR_Y + 1) / silhouette.height)
    size = (max(1, round(silhouette.width * scale)), max(1, round(silhouette.height * scale)))
    reduced = threshold_alpha(silhouette.resize(size, Image.Resampling.BOX))
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    x = max(0, min(CELL_W - reduced.width, ANCHOR_X - reduced.width // 2))
    y = ANCHOR_Y - reduced.height + 1
    cell.alpha_composite(reduced, (x, y))
    return clean_silhouette(cell)


def build_sheet() -> Image.Image:
    sheet = Image.new("RGBA", (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    for row, pose in enumerate(POSES):
        source = SOURCES / f"{pose}.png"
        right, back_right, front_right = (extract_pose(source, view) for view in range(3))
        frames = (right, back_right, back_right.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
                  right.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
                  front_right.transpose(Image.Transpose.FLIP_LEFT_RIGHT), front_right)
        for column, frame in enumerate(frames):
            sheet.alpha_composite(frame, (column * CELL_W, row * CELL_H))
    return sheet


def validate(sheet: Image.Image) -> None:
    if sheet.mode != "RGBA" or list(sheet.size) != CONTRACT["sheet_size"]:
        raise ValueError(f"expected RGBA {CONTRACT['sheet_size']}, got {sheet.mode} {sheet.size}")
    cells = []
    for row in range(ROWS):
        for column in range(COLS):
            cell = sheet.crop((column * CELL_W, row * CELL_H, (column + 1) * CELL_W, (row + 1) * CELL_H))
            opaque = [(x, y) for y in range(CELL_H) for x in range(CELL_W) if cell.getpixel((x, y))[3]]
            if not opaque:
                raise ValueError(f"empty cell ({column}, {row})")
            if max(y for _, y in opaque) > ANCHOR_Y:
                raise ValueError(f"cell ({column}, {row}) exceeds anchor y={ANCHOR_Y}")
            if len(components(cell)) != 1:
                raise ValueError(f"cell ({column}, {row}) has detached sprite fragments")
            cells.append(cell.tobytes())
    if len(set(cells)) != COLS * ROWS:
        raise ValueError("all Ogre cells must be unique")
    if not any(pixel[3] == 0 for pixel in sheet.get_flattened_data()):
        raise ValueError("expected genuine transparency")


def main() -> None:
    sheet = build_sheet()
    validate(sheet)
    destination = ASSETS / "ogre_sheet.png"
    sheet.save(destination)
    print(f"validated {destination.name}: {sheet.width}x{sheet.height} RGBA, {COLS}x{ROWS} cells")


if __name__ == "__main__":
    main()
