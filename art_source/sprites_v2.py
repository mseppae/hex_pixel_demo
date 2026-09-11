# Sprite sheets: 6 directions (columns) x 4 poses (rows): idle, walk A, walk B, attack wind-up.
from PIL import Image
from sprites import (ADVENTURER_PALETTE, GOBLIN_PALETTE,
                     ADVENTURER_FRONT_RIGHT, ADVENTURER_RIGHT, ADVENTURER_BACK_RIGHT,
                     GOBLIN_FRONT_RIGHT, GOBLIN_RIGHT, GOBLIN_BACK_RIGHT, rgb, mirror)

def rows_of(ascii_art):
    rows = ascii_art.strip("\n").split("\n")
    assert len(rows) == 24 and all(len(r) == 16 for r in rows), ascii_art
    return rows

def with_rows(base_rows, first_row_index, replacement):
    replacement_rows = replacement.strip("\n").split("\n")
    result = list(base_rows)
    for offset, row in enumerate(replacement_rows):
        assert len(row) == 16, (row, len(row))
        result[first_row_index + offset] = row
    return result

def with_pixels(base_rows, changes):
    result = [list(row) for row in base_rows]
    for (x, y), symbol in changes.items():
        result[y][x] = symbol
    return ["".join(row) for row in result]

# ---------------- Adventurer ----------------
adventurer_front_right = rows_of(ADVENTURER_FRONT_RIGHT)
adventurer_right_stride = rows_of(ADVENTURER_RIGHT)
adventurer_back_right = rows_of(ADVENTURER_BACK_RIGHT)

adventurer_right_idle = with_rows(adventurer_right_stride, 18, """
.....kppppk.....
.....kppppk.....
.....kppppk.....
.....kBBBBk.....
....kBBBBBBBk...
....kkkkkkkkk...
""")
adventurer_right_passing = with_rows(adventurer_right_stride, 18, """
.....kppppk.....
....kBBkppk.....
....kkkkppk.....
.......kBBk.....
.......kBBBBk...
.......kkkkkk...
""")

adventurer_front_right_step_a = with_rows(adventurer_front_right, 19, """
...kBBBkkppk....
...kkkkkkppk....
........kBBBk...
........kBBBBk..
........kkkkkk..
""")
adventurer_front_right_step_b = with_rows(adventurer_front_right, 19, """
....kppkkBBBBk..
....kppkkkkkkk..
....kBBk........
...kBBBk........
...kkkkk........
""")
adventurer_back_right_step_a = with_rows(adventurer_back_right, 19, """
...kBBBkkppk....
...kkkkkkppk....
........kBBk....
........kBBBk...
........kkkkk...
""")
adventurer_back_right_step_b = with_rows(adventurer_back_right, 19, """
....kppkkBBBk...
....kppkkkkkk...
....kBBk........
...kBBBk........
...kkkkk........
""")

# Attack wind-up: sword raised high
adventurer_front_right_attack = with_rows(adventurer_front_right, 0, """
..............w.
..............w.
..............w.
.....kkkkkk...w.
....khHHHhhk..w.
...khHHhhhhhk.w.
...khhssssssk.w.
...khhsseseSkggg
...khhsssssSk.s.
....khhhsssk.h..
...kchhhhhhhkh..
..kcchhhhHhhhk..
..kcchhhhhhhhk..
..kcsbbbbbbbbk..
""")
adventurer_right_attack = with_rows(adventurer_right_idle, 0, """
..............w.
..............w.
..............w.
.....kkkkk....w.
....khHHHhk...w.
...khHHhhhhk..w.
...khhhhhssk..w.
...khhhhhsek.ggg
...khhhhssssk.s.
....khhhhssk.h..
....kchhhhhkh...
...kcchhHhhk....
...kcchhhhhk....
...kcbbbbbbk....
""")
adventurer_back_right_attack = with_rows(adventurer_back_right, 0, """
..............w.
..............w.
..............w.
.....kkkkkk...w.
....khHHHHhk..w.
...khHHHhhhhk.w.
...khHhhhhhhk.w.
...khhhhhhhskggg
...khhhhhhhsk.s.
....khhhhhhk.h..
...kcccccccckh..
..kcccHcccccck..
..kccccccccccck.
..kcbbbbbbbbck..
""")

# ---------------- Goblin ----------------
goblin_front_right = rows_of(GOBLIN_FRONT_RIGHT)
goblin_right = rows_of(GOBLIN_RIGHT)
goblin_back_right = rows_of(GOBLIN_BACK_RIGHT)

goblin_front_right_step_a = with_rows(goblin_front_right, 20, """
...kDDDkkGGk....
...kkkkkkDDDk...
........kDDDDk..
........kkkkkk..
""")
goblin_front_right_step_b = with_rows(goblin_front_right, 20, """
....kGGkkDDDDk..
....kDDkkkkkkk..
...kDDDk........
...kkkkk........
""")
goblin_right_passing = with_rows(goblin_right, 18, """
....kGGGGk......
...kDDkGGk......
...kkkkGGk......
......kDDk......
......kDDDDk....
......kkkkkk....
""")
goblin_back_right_step_a = with_rows(goblin_back_right, 20, """
...kDDDkkGGk....
...kkkkkkDDk....
........kDDDk...
........kkkkk...
""")
goblin_back_right_step_b = with_rows(goblin_back_right, 20, """
....kGGkkDDDk...
....kDDkkkkkk...
...kDDDk........
...kkkkk........
""")

# Goblin attack: dagger raised in front / thrust forward
goblin_front_right_attack = with_pixels(goblin_front_right, {
    (14, 11): "w", (14, 12): "w", (14, 13): "w", (14, 14): "w", (14, 15): "n",
    (13, 16): "G", (13, 17): ".", (13, 18): ".", (13, 19): ".",
})
goblin_right_attack = with_rows(goblin_right, 15, """
....kmlllmGGnwww
....kmlllmk.....
""")
goblin_back_right_attack = with_pixels(goblin_back_right, {
    (14, 11): "w", (14, 12): "w", (14, 13): "w", (14, 14): "n",
    (13, 15): "G", (12, 16): "k", (13, 16): ".", (13, 17): ".", (13, 18): ".",
})

def render_rows(rows, palette):
    image = Image.new("RGBA", (16, 24), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        assert len(row) == 16, (y, row)
        for x, symbol in enumerate(row):
            if symbol != ".":
                image.putpixel((x, y), rgb(palette[symbol]))
    return image

def build_sheet(poses, palette):
    # poses: list of 4 rows; each row is (front_right, right, back_right) as row lists.
    sheet = Image.new("RGBA", (16 * 6, 24 * len(poses)), (0, 0, 0, 0))
    for pose_index, (front_right, right, back_right) in enumerate(poses):
        front_right, right, back_right = (render_rows(r, palette) for r in (front_right, right, back_right))
        # Column order = hexgrid.Direction order as seen on screen.
        frames = [right, back_right, mirror(back_right), mirror(right), mirror(front_right), front_right]
        for column, frame in enumerate(frames):
            sheet.paste(frame, (column * 16, pose_index * 24))
    return sheet

adventurer_sheet = build_sheet([
    (adventurer_front_right, adventurer_right_idle, adventurer_back_right),
    (adventurer_front_right_step_a, adventurer_right_stride, adventurer_back_right_step_a),
    (adventurer_front_right_step_b, adventurer_right_passing, adventurer_back_right_step_b),
    (adventurer_front_right_attack, adventurer_right_attack, adventurer_back_right_attack),
    (adventurer_front_right, adventurer_right_idle, adventurer_back_right),  # strike: same as idle
], ADVENTURER_PALETTE)
goblin_sheet = build_sheet([
    (goblin_front_right, goblin_right, goblin_back_right),
    (goblin_front_right_step_a, goblin_right_passing, goblin_back_right_step_a),
    (goblin_front_right_step_b, goblin_right_passing, goblin_back_right_step_b),
    (goblin_front_right_attack, goblin_right_attack, goblin_back_right_attack),
    (goblin_front_right, goblin_right, goblin_back_right),  # strike: same as idle
], GOBLIN_PALETTE)
adventurer_sheet.save("adventurer_sheet.png")
goblin_sheet.save("goblin_sheet.png")

preview = Image.new("RGBA", (96 * 2 + 8, 96), (40, 44, 58, 255))
preview.alpha_composite(adventurer_sheet, (0, 0))
preview.alpha_composite(goblin_sheet, (104, 0))
preview.resize((preview.width * 5, preview.height * 5), Image.NEAREST).save("/tmp/sheets_v2_preview.png")
print("ok")
