#!/usr/bin/env python3
"""Validate every runtime graphic atlas against its active renderer contract."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"


def image(name: str) -> Image.Image:
    result = Image.open(ASSETS / name)
    if result.mode != "RGBA":
        raise AssertionError(f"{name}: expected RGBA, got {result.mode}")
    if not any(pixel[3] == 0 for pixel in result.get_flattened_data()):
        raise AssertionError(f"{name}: needs genuine transparency")
    return result


def validate_creatures() -> None:
    content = json.loads((ASSETS / "content.json").read_text())
    for creature in content["creatures"]:
        name = creature["sprite_sheet"]
        frame_w, frame_h = creature["frame_size"]
        atlas = image(name)
        if atlas.size != (frame_w * 6, frame_h * 9):
            raise AssertionError(f"{name}: expected {(frame_w * 6, frame_h * 9)}, got {atlas.size}")
        anchor = creature.get("sprite_anchor", [frame_w // 2, frame_h])
        for row in range(9):
            for column in range(6):
                cell = atlas.crop((column * frame_w, row * frame_h, (column + 1) * frame_w, (row + 1) * frame_h))
                if cell.getbbox() is None:
                    raise AssertionError(f"{name}: empty cell {column},{row}")
                if cell.getbbox()[3] > anchor[1] + 1:
                    raise AssertionError(f"{name}: cell {column},{row} extends below its anchor")


def validate_static_atlases() -> None:
    expected = {
        "tiles.png": (128, 128),
        "trees.png": (192, 128),
        "portal.png": (32, 48),
        "objects.png": (256, 64),
        "item_icons.png": (32 * 47, 32),
    }
    for name, size in expected.items():
        if image(name).size != size:
            raise AssertionError(f"{name}: expected {size}, got {image(name).size}")

    # Active source rectangles from items.odin must all be inside objects.png.
    objects = image("objects.png")
    rectangles = [(0, 0, 32, 16), (32, 0, 32, 16), (0, 24, 64, 32),
                  (192, 24, 32, 28), (64, 0, 32, 16), (96, 0, 32, 16),
                  (128, 0, 32, 16), (160, 0, 32, 16), (192, 0, 32, 16),
                  (224, 0, 32, 16), (64, 24, 64, 32), (128, 24, 64, 32),
                  (224, 24, 32, 28)]
    for left, top, width, height in rectangles:
        if left < 0 or top < 0 or left + width > objects.width or top + height > objects.height:
            raise AssertionError(f"objects.png: out-of-bounds rectangle {(left, top, width, height)}")


if __name__ == "__main__":
    validate_creatures()
    validate_static_atlases()
    print("graphics contract: all runtime sheets valid")
