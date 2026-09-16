#!/usr/bin/env python3
"""Turn an isolated high-detail troll pose into its 48x64 gameplay sheet."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source" / "modern_pose_refs" / "troll_idle_front_right.png"
OUTPUT = ROOT / "assets" / "troll_sheet.png"
CELL_W, CELL_H = 48, 64
ANCHOR = (24, 60)
TARGET_SIZE = (46, 55)


def source_pose() -> Image.Image:
    original = Image.open(SOURCE).convert("RGBA")
    box = original.getbbox()
    if box is None:
        raise ValueError("troll source is empty")
    pose = original.crop(box).resize(TARGET_SIZE, Image.Resampling.BOX)
    alpha = pose.getchannel("A").point(lambda value: 255 if value >= 150 else 0)
    rgb = pose.convert("RGB").quantize(colors=18, method=Image.Quantize.FASTOCTREE).convert("RGB")
    return Image.merge("RGBA", (*rgb.split(), alpha))


def place(pose: Image.Image, dx: int = 0, dy: int = 0) -> Image.Image:
    frame = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    frame.alpha_composite(pose, (ANCHOR[0] - pose.width // 2 + dx, ANCHOR[1] - pose.height + 1 + dy))
    return frame


def move(frame: Image.Image, dx: int, dy: int = 0) -> Image.Image:
    result = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    result.alpha_composite(frame, (dx, dy))
    return result


def recoil(frame: Image.Image, dx: int) -> Image.Image:
    result = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    for y in range(CELL_H):
        for x in range(CELL_W):
            r, g, b, a = frame.getpixel((x, y))
            if a:
                result.putpixel((x, y), (min(255, int(r * .7 + 72)), int(g * .56), int(b * .56), a))
    return move(result, dx)


def fallen(frame: Image.Image, size: tuple[int, int], top: int) -> Image.Image:
    box = frame.getbbox()
    assert box is not None
    body = frame.crop(box).resize(size, Image.Resampling.NEAREST)
    result = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    result.alpha_composite(body, ((CELL_W - size[0]) // 2, top))
    return result


def main() -> None:
    base = source_pose()
    sheet = Image.new("RGBA", (CELL_W * 6, CELL_H * 9), (0, 0, 0, 0))
    for column in range(6):
        left = column in (2, 3, 4)
        pose = base.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if left else base
        idle = place(pose)
        frames = [
            idle,
            place(pose, -2 if left else 2),
            # The base of a large actor is its gameplay anchor. Horizontal
            # weight shifts animate the pose without letting a foot drift
            # below that anchor.
            place(pose, 2 if left else -2),
            place(pose, 3 if left else -3),
            place(pose, -3 if left else 3),
            move(idle, 2 if left else -2),
            recoil(idle, -2 if left else 2),
            fallen(recoil(idle, 0), (38, 34), 25),
            fallen(idle, (46, 18), 43),
        ]
        for row, frame in enumerate(frames):
            if frame.getbbox() is None:
                raise ValueError(f"empty troll cell {column},{row}")
            sheet.alpha_composite(frame, (column * CELL_W, row * CELL_H))
    if sheet.size != (288, 576):
        raise ValueError("troll sheet contract failed")
    sheet.save(OUTPUT)
    print(f"wrote {OUTPUT}: {sheet.size[0]}x{sheet.size[1]} RGBA")


if __name__ == "__main__":
    main()
