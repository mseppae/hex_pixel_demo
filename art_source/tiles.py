# Tile atlas: floor variants, wall variants (top + matching side), stairs down/up.
# The positions here must match the Atlas_Region constants in hex_prism_mesh.odin.
import math, random
from PIL import Image, ImageDraw, ImageFont

ATLAS_SIZE = 128
TOP_W, TOP_H = 28, 32
HEX_SIZE_PIXELS = 16

def slot(column, row):   # top-face slots are 32 x 36 apart, with a 2 px border
    return (2 + 32 * column, 2 + 36 * row)

FLOOR_TOPS  = [slot(0, 0), slot(1, 0), slot(2, 0), slot(3, 0)]   # plain, cracked, pebbles, mossy
WALL_TOPS   = [slot(0, 1), slot(1, 1), slot(2, 1)]               # plain, mossy, cracked
STAIRS_DOWN = slot(3, 1)
STAIRS_UP   = slot(0, 2)
WALL_SIDES  = [(34, 74), (54, 74), (74, 74)]                     # 16 x 24 each, same order as WALL_TOPS
FLOOR_SIDE  = (94, 74)                                           # 16 x 4

def rgb(hex_string):
    return tuple(int(hex_string[i:i+2], 16) for i in (1, 3, 5)) + (255,)

def in_hex(px, py):
    x = px + 0.5 - TOP_W / 2
    y = py + 0.5 - TOP_H / 2
    return abs(x) <= math.sqrt(3) / 2 * HEX_SIZE_PIXELS and abs(y) <= HEX_SIZE_PIXELS - abs(x) / math.sqrt(3)

def blank_top():
    return [[None] * TOP_W for _ in range(TOP_H)]

def speckle(cell, base, dark, light, speck_chance, rng):
    for py in range(TOP_H):
        for px in range(TOP_W):
            if in_hex(px, py):
                roll = rng.random()
                cell[py][px] = dark if roll < speck_chance else light if roll < speck_chance * 1.6 else base

def crack(cell, color, start_x, start_y, steps, rng):
    x, y = start_x, start_y
    for _ in range(steps):
        if 0 <= x < TOP_W and 0 <= y < TOP_H and cell[py_guard(y)][x] is not None:
            cell[y][x] = color
        x += rng.choice((-1, 0, 1)); y += 1

def py_guard(y):
    return max(0, min(TOP_H - 1, y))

def rim(cell, light, outline):
    result = [row[:] for row in cell]
    for py in range(TOP_H):
        for px in range(TOP_W):
            if cell[py][px] is None: continue
            neighbors = [(px-1,py),(px+1,py),(px,py-1),(px,py+1)]
            outside = [n for n in neighbors if not (0 <= n[0] < TOP_W and 0 <= n[1] < TOP_H) or not in_hex(*n)]
            if outside:
                upper_left = any(n[1] < py or n[0] < px for n in outside) and py < TOP_H // 2
                result[py][px] = light if upper_left else outline
    return result

def paste_top(atlas, origin, cell, outline):
    left, top = origin
    for py in range(TOP_H):
        for px in range(TOP_W):
            # Outside the hex: the outline color, so sampling at the edges never bleeds.
            atlas.putpixel((left + px, top + py), cell[py][px] or outline)

FLOOR = dict(base=rgb("#b59a74"), dark=rgb("#8c7456"), light=rgb("#cdb48d"), outline=rgb("#6e5a43"))
WALL = dict(base=rgb("#6f7482"), dark=rgb("#555a66"), light=rgb("#8e94a3"), outline=rgb("#3e424c"))
MOSS, MOSS_DARK = rgb("#6f8f45"), rgb("#4f6a30")

def floor_top(variant, rng):
    cell = blank_top()
    speckle(cell, FLOOR["base"], FLOOR["dark"], FLOOR["light"], 0.10, rng)
    if variant == 1:    # cracked
        for start in ((6, 5, 12), (15, 12, 10), (20, 4, 8)):
            crack(cell, FLOOR["outline"], *start, rng)
    elif variant == 2:  # loose pebbles
        for _ in range(9):
            x, y = rng.randrange(4, 24), rng.randrange(6, 26)
            if in_hex(x, y) and in_hex(x + 1, y + 1):
                cell[y][x] = FLOOR["light"]; cell[y][x + 1] = FLOOR["light"]
                cell[y + 1][x] = FLOOR["dark"]; cell[y + 1][x + 1] = FLOOR["dark"]
    elif variant == 3:  # moss creeping in
        for _ in range(70):
            x, y = int(rng.gauss(9, 4)), int(rng.gauss(20, 4))
            if 0 <= x < TOP_W and 0 <= y < TOP_H and in_hex(x, y):
                cell[y][x] = MOSS if rng.random() < 0.7 else MOSS_DARK
    return rim(cell, FLOOR["light"], FLOOR["outline"])

def wall_top(variant, rng):
    cell = blank_top()
    speckle(cell, WALL["base"], WALL["dark"], WALL["light"], 0.12, rng)
    if variant == 1:
        for _ in range(90):
            x, y = int(rng.gauss(18, 5)), int(rng.gauss(10, 5))
            if 0 <= x < TOP_W and 0 <= y < TOP_H and in_hex(x, y):
                cell[y][x] = MOSS if rng.random() < 0.7 else MOSS_DARK
    elif variant == 2:
        for start in ((8, 3, 14), (18, 10, 14)):
            crack(cell, WALL["outline"], *start, rng)
    return rim(cell, WALL["light"], WALL["outline"])

def stairs_down_top(rng):
    cell = floor_top(0, rng)
    # A dark opening with steps descending into it: each step darker than the one above.
    step_colors = [rgb("#8f8a80"), rgb("#6d6960"), rgb("#4e4b45"), rgb("#34322e"), rgb("#1f1d1b")]
    left, right, top = 7, 20, 8
    for index, color in enumerate(step_colors):
        for y in range(top + index * 3, top + index * 3 + 3):
            for x in range(left, right + 1):
                cell[y][x] = FLOOR["outline"] if x in (left, right) else color
    for x in range(left, right + 1):
        cell[top - 1][x] = FLOOR["outline"]
        cell[top + 15][x] = FLOOR["outline"]
    return cell

def stairs_up_top(rng):
    cell = floor_top(0, rng)
    # Pale stone steps rising toward the top of the tile, each with a shadow line under it.
    left, right, top = 7, 20, 7
    for index in range(5):
        y0 = top + index * 3
        stone = rgb("#e2dccf") if index < 2 else rgb("#cfc7b6") if index < 4 else rgb("#bdb4a1")
        for x in range(left, right + 1):
            cell[y0][x] = rgb("#f2eee6")            # lit front edge
            cell[y0 + 1][x] = stone
            cell[y0 + 2][x] = rgb("#9a917f")        # shadow under the step
        cell[y0][left] = cell[y0 + 1][left] = cell[y0 + 2][left] = FLOOR["outline"]
        cell[y0][right] = cell[y0 + 1][right] = cell[y0 + 2][right] = FLOOR["outline"]
    for x in range(left, right + 1):
        cell[top - 1][x] = FLOOR["outline"]
    return cell

def wall_side(variant, rng):
    mortar, brick, brick_dark, brick_light = rgb("#3e424c"), rgb("#6a6f7c"), rgb("#545865"), rgb("#7f8594")
    pixels = [[None] * 16 for _ in range(24)]
    for py in range(24):
        row = py // 6
        for px in range(16):
            in_row = py % 6
            offset = 0 if row % 2 == 0 else 4
            if in_row == 5 or (px + offset) % 8 == 7:
                color = mortar
            elif in_row == 0:
                color = brick_light
            else:
                color = brick_dark if rng.random() < 0.15 else brick
            pixels[py][px] = color
    if variant == 1:   # moss dripping from the top
        for px in range(16):
            length = rng.choice((1, 2, 3, 4, 6, 8))
            for py in range(length):
                pixels[py][px] = MOSS if rng.random() < 0.75 else MOSS_DARK
    elif variant == 2: # a crack running down
        x = 6
        for py in range(2, 24):
            pixels[py][x] = mortar
            if rng.random() < 0.4: x = max(1, min(14, x + rng.choice((-1, 1))))
    return pixels

def extrude_rect(atlas, left, top, width, height):
    # Copy the edge pixels one step outward, so sampling right at an edge never picks up a neighbor.
    for x in range(left, left + width):
        atlas.putpixel((x, top - 1), atlas.getpixel((x, top)))
        atlas.putpixel((x, top + height), atlas.getpixel((x, top + height - 1)))
    for y in range(top - 1, top + height + 1):
        atlas.putpixel((left - 1, y), atlas.getpixel((left, min(max(y, top), top + height - 1))))
        atlas.putpixel((left + width, y), atlas.getpixel((left + width - 1, min(max(y, top), top + height - 1))))

def build_atlas():
    rng = random.Random(7)
    atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE), (0, 0, 0, 0))
    for variant, origin in enumerate(FLOOR_TOPS):
        paste_top(atlas, origin, floor_top(variant, rng), FLOOR["outline"])
    for variant, origin in enumerate(WALL_TOPS):
        paste_top(atlas, origin, wall_top(variant, rng), WALL["outline"])
    paste_top(atlas, STAIRS_DOWN, stairs_down_top(rng), FLOOR["outline"])
    paste_top(atlas, STAIRS_UP, stairs_up_top(rng), FLOOR["outline"])
    for variant, (left, top) in enumerate(WALL_SIDES):
        pixels = wall_side(variant, rng)
        for py in range(24):
            for px in range(16):
                atlas.putpixel((left + px, top + py), pixels[py][px])
        extrude_rect(atlas, left, top, 16, 24)
    left, top = FLOOR_SIDE
    for py in range(4):
        for px in range(16):
            atlas.putpixel((left + px, top + py), rgb("#8c7456") if py == 0 else rgb("#5c4a36"))
    extrude_rect(atlas, left, top, 16, 4)
    return atlas

def build_guide(atlas):
    scale = 6
    big = atlas.resize((ATLAS_SIZE * scale, ATLAS_SIZE * scale), Image.NEAREST)
    canvas = Image.new("RGBA", (ATLAS_SIZE * scale + 330, ATLAS_SIZE * scale), (245, 245, 240, 255))
    checker = Image.new("RGBA", big.size, (255, 255, 255, 255))
    draw = ImageDraw.Draw(checker)
    for y in range(ATLAS_SIZE):
        for x in range(ATLAS_SIZE):
            if (x + y) % 2: draw.rectangle([x*scale, y*scale, x*scale+scale-1, y*scale+scale-1], fill=(228, 228, 228, 255))
    checker.alpha_composite(big)
    canvas.paste(checker, (0, 0))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=18)
    small = ImageFont.load_default(size=14)
    entries = [(f"floor {i}", o, 28, 32, (230, 90, 40)) for i, o in enumerate(FLOOR_TOPS)]
    entries += [(f"wall top {i}", o, 28, 32, (40, 120, 220)) for i, o in enumerate(WALL_TOPS)]
    entries += [("stairs down", STAIRS_DOWN, 28, 32, (150, 70, 200)), ("stairs up", STAIRS_UP, 28, 32, (150, 70, 200))]
    entries += [(f"wall side {i}", o, 16, 24, (40, 160, 90)) for i, o in enumerate(WALL_SIDES)]
    entries += [("floor side", FLOOR_SIDE, 16, 4, (120, 90, 40))]
    x_text = ATLAS_SIZE * scale + 20
    draw.text((x_text, 16), "assets/tiles.png (128 x 128)", fill=(30, 30, 30), font=font)
    y = 50
    for name, (left, top), width, height, color in entries:
        draw.rectangle([left*scale, top*scale, (left+width)*scale - 1, (top+height)*scale - 1], outline=color, width=2)
        draw.text((x_text, y), f"{name}: {width} x {height} at ({left}, {top})", fill=color, font=small)
        y += 24
    y += 10
    for line in ["A wall's top and side share a variant", "number (top 1 goes with side 1).", "",
                 "Pixels outside each hex are never", "shown; they're filled with the edge",
                 "color so edges never bleed."]:
        draw.text((x_text, y), line, fill=(60, 60, 60), font=small); y += 20
    return canvas

if __name__ == "__main__":
    atlas = build_atlas()
    atlas.save("tiles.png")
    build_guide(atlas).save("atlas_layout_guide.png")
    print("ok")
