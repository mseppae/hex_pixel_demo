#!/usr/bin/env python3
"""Extend the V4 humanoid sheets with idle, hurt, and death animation rows.

Rows 0-4 are preserved.  Rows 5-8 are assembled from the accepted V4 poses,
using only nearest-neighbour pixel operations so no generated-atlas fragments
can enter a 32x32 cell.  Run this after updating sprite_contract.json.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
CONTRACT = json.loads((ASSETS / "sprite_contract.json").read_text())
CELL_W, CELL_H = CONTRACT["frame_size"]
COLS, ROWS = CONTRACT["grid"]
ANCHOR_X, ANCHOR_Y = CONTRACT["anchor"]
BASE_ROWS = 5

# E, NE, NW, W, SW, SE — confirmed renderer direction-column order.
FACING = ((1, 0), (1, -1), (-1, -1), (-1, 0), (-1, 0), (1, 0))
UPPER_BODY_BOTTOM = 20


def opaque(pixel: tuple[int, int, int, int]) -> bool:
    return pixel[3] != 0


def shifted_upper(base: Image.Image, source: Image.Image, dx: int, dy: int, tint: float = 1.0) -> Image.Image:
    """Move only torso/weapon pixels; planted legs remain on the anchor baseline."""
    frame = base.copy()
    for y in range(UPPER_BODY_BOTTOM + 1):
        for x in range(CELL_W):
            frame.putpixel((x, y), (0, 0, 0, 0))
    for y in range(UPPER_BODY_BOTTOM + 1):
        for x in range(CELL_W):
            r, g, b, a = source.getpixel((x, y))
            tx, ty = x + dx, y + dy
            if a and 0 <= tx < CELL_W and 0 <= ty <= UPPER_BODY_BOTTOM:
                # The hurt pose is a readable but restrained warm recoil tint.
                if tint != 1.0:
                    r = min(255, int(r * tint + 52 * (1 - tint)))
                    g = int(g * tint)
                    b = int(b * tint)
                frame.putpixel((tx, ty), (r, g, b, a))
    return frame


def shifted_pose(frame: Image.Image, dx: int) -> Image.Image:
    """A whole-pose weight shift: never separates torso, legs, or feet."""
    result = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    for y in range(CELL_H):
        for x in range(CELL_W):
            pixel = frame.getpixel((x, y))
            target_x = x + dx
            if opaque(pixel) and 0 <= target_x < CELL_W:
                result.putpixel((target_x, y), pixel)
    return result


def crop_silhouette(frame: Image.Image) -> Image.Image:
    bounds = frame.getbbox()
    if bounds is None:
        raise ValueError("cannot make a pose from an empty frame")
    return frame.crop(bounds)


def grounded_resize(frame: Image.Image, width: int, height: int, facing_x: int) -> Image.Image:
    """Scale a pose onto the ground, keeping its action biased toward facing."""
    result = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    silhouette = crop_silhouette(frame).resize((width, height), Image.Resampling.NEAREST)
    x = ANCHOR_X - width // 2
    if facing_x > 0:
        x += 2
    elif facing_x < 0:
        x -= 2
    x = max(0, min(CELL_W - width, x))
    y = ANCHOR_Y - height + 1
    result.alpha_composite(silhouette, (x, y))
    return result


def build_sheet(source: Image.Image) -> Image.Image:
    if source.width != CELL_W * COLS or source.height < CELL_H * BASE_ROWS:
        raise ValueError("input sheet does not contain the required V4 6x5 base")
    sheet = Image.new("RGBA", (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    sheet.alpha_composite(source.crop((0, 0, CELL_W * COLS, CELL_H * BASE_ROWS)))

    for column, (dx, dy) in enumerate(FACING):
        x0 = column * CELL_W
        idle = source.crop((x0, 0, x0 + CELL_W, CELL_H))

        # A quiet sideways weight shift.  Move the entire silhouette so no body
        # part is detached from the feet during the idle loop.
        idle_b = shifted_pose(idle, -dx)
        # A recoil leaning away from the target, with a restrained warm flash.
        hurt = shifted_upper(idle, idle, -dx, max(0, -dy) + 1, tint=0.72)
        # Crouch, then settle into a low horizontal defeated pose.
        death_start = grounded_resize(hurt, 18, 22, dx)
        death_down = grounded_resize(death_start, 28, 11, dx)

        for row, frame in ((5, idle_b), (6, hurt), (7, death_start), (8, death_down)):
            sheet.alpha_composite(frame, (x0, row * CELL_H))
    return sheet


def validate(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    if image.size != tuple(CONTRACT["sheet_size"]):
        raise ValueError(f"{path.name}: expected {CONTRACT['sheet_size']}, got {image.size}")
    if image.mode != "RGBA":
        raise ValueError(f"{path.name}: expected RGBA, got {image.mode}")
    cells = []
    for row in range(ROWS):
        for column in range(COLS):
            cell = image.crop((column * CELL_W, row * CELL_H, (column + 1) * CELL_W, (row + 1) * CELL_H))
            pixels = list(cell.get_flattened_data())
            opaque_pixels = [pixel for pixel in pixels if opaque(pixel)]
            if not opaque_pixels:
                raise ValueError(f"{path.name}: empty cell ({column}, {row})")
            if max(y for y in range(CELL_H) if any(opaque(cell.getpixel((x, y))) for x in range(CELL_W))) > ANCHOR_Y:
                raise ValueError(f"{path.name}: cell ({column}, {row}) extends below anchor y={ANCHOR_Y}")
            cells.append(cell.tobytes())
    if len(set(cells)) != COLS * ROWS:
        raise ValueError(f"{path.name}: all cells must be unique")
    if not any(pixel[3] == 0 for pixel in image.get_flattened_data()):
        raise ValueError(f"{path.name}: expected genuine transparency")


def main() -> None:
    for filename in ("adventurer_sheet.png", "goblin_sheet.png"):
        path = ASSETS / filename
        finished = build_sheet(Image.open(path).convert("RGBA"))
        finished.save(path)
        validate(path)
        print(f"validated {filename}: {finished.width}x{finished.height} RGBA, 6x{ROWS} cells")


if __name__ == "__main__":
    main()
