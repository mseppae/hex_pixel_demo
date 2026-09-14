# Big creatures for the deep levels. Same sheet layout (6 direction columns x 5 pose
# rows), but large frames, meant for multi-hex footprints like the ogre's triangle.
from creatures_new import Layer, compose, build_sheet, MATERIALS, rgb
from PIL import Image

MATERIALS.update({
    "troll_hide": (rgb("#6f7a4a"), rgb("#8d9a62"), rgb("#4e5633")),
    "troll_dark": (rgb("#54603a"), rgb("#6f7a4a"), rgb("#3b4428")),
    "moss":       (rgb("#4a7a38"), rgb("#6fa04f"), rgb("#33512a")),
    "stone_body": (rgb("#7c7a74"), rgb("#9c9a93"), rgb("#56544f")),
    "stone_dark": (rgb("#5e5c57"), rgb("#7c7a74"), rgb("#403e3a")),
    "rune":       (rgb("#d86a2a"), rgb("#f4a050"), rgb("#9c4418")),
    "claw":       (rgb("#e8e0c8"), rgb("#f8f4e6"), rgb("#b0a88e")),
})
DEEP_DETAIL = {"eye_green": rgb("#b8f04a"), "eye_rune": rgb("#f4a050"), "tusk": rgb("#e8e0c8"), "dark": rgb("#14120f")}
from creatures_new import DETAIL
DETAIL.update(DEEP_DETAIL)

# ---------------------------------------------------------------------------
# Cave troll: 40 x 52. Long arms, hunched, moss on its back.
# ---------------------------------------------------------------------------
W1, H1 = 40, 52
def troll(view, pose):
    L = lambda m: Layer(m, W1, H1)
    layers, details = [], {}
    lift_left = 5 if pose == "walk_a" else 0
    lift_right = 5 if pose == "walk_b" else 0
    lean = {"wind_up": -2, "strike": 3}.get(pose, 0)

    if pose == "wind_up":   # the far arm drawn back behind the body
        layers.append(L("troll_dark").line(14, 26, 4, 14, 6))
        layers.append(L("troll_dark").ellipse(4, 12, 4, 4))
    # legs: short and thick
    layers.append(L("troll_dark").rect(11, 36, 17, 46 - lift_left).rect(9, 46 - lift_left, 19, 49 - lift_left))
    layers.append(L("troll_dark").rect(22, 36, 28, 46 - lift_right).rect(22, 46 - lift_right, 32, 49 - lift_right))
    # torso, wider at the shoulders, hunched forward
    layers.append(L("troll_hide").ellipse(20 + lean, 26, 13, 11))
    layers.append(L("troll_hide").ellipse(16 + lean, 18, 10, 6))       # hunched shoulders
    layers.append(L("moss").ellipse(12 + lean, 16, 5, 2.6))            # moss on the back
    layers.append(L("moss").ellipse(24 + lean, 15, 4, 2.2))
    # head: low, jutting jaw
    layers.append(L("troll_dark").rect(22 + lean, 12, 26 + lean, 18))          # neck, darker so the head reads
    layers.append(L("troll_hide").ellipse(28 + lean, 11, 6.5, 5.5))            # head, set forward and up
    layers.append(L("troll_hide").rect(28 + lean, 12, 35 + lean, 16))          # jutting jaw
    if view != "back_right":
        details.update({(27 + lean, 8): "eye_green", (31 + lean, 8): "eye_green",
                        (33 + lean, 15): "tusk", (30 + lean, 16): "tusk", (27 + lean, 16): "tusk"})
    # arms: long enough to reach the ground
    if pose == "strike":
        layers.append(L("troll_hide").line(28 + lean, 22, 38, 34, 6))
        layers.append(L("claw").line(38, 34, 39, 39, 2))
    elif pose == "wind_up":
        layers.append(L("troll_hide").line(26 + lean, 22, 32, 10, 6))
        layers.append(L("claw").line(32, 10, 34, 5, 2))
    else:
        layers.append(L("troll_hide").line(28 + lean, 22, 33, 40, 6))
        layers.append(L("claw").line(33, 40, 34, 45, 2))
    if view != "back_right":
        layers.append(L("troll_hide").line(11 + lean, 22, 7, 40, 5.5))
        layers.append(L("claw").line(7, 40, 6, 45, 2))
    return compose(W1, H1, layers, details)

# ---------------------------------------------------------------------------
# Stone golem: 44 x 54. Blocky, slow, rune-lit cracks.
# ---------------------------------------------------------------------------
W2, H2 = 44, 54
def golem(view, pose):
    L = lambda m: Layer(m, W2, H2)
    layers, details = [], {}
    step = 4 if pose == "walk_a" else (-4 if pose == "walk_b" else 0)
    lean = {"wind_up": -2, "strike": 4}.get(pose, 0)

    if pose == "wind_up":
        layers.append(L("stone_dark").rect(4, 8, 14, 20))              # fist drawn back
    layers.append(L("stone_dark").rect(12, 38, 20, 49 - max(0, step)).rect(10, 49 - max(0, step), 22, 51 - max(0, step)))
    layers.append(L("stone_dark").rect(24, 38, 32, 49 + min(0, step)).rect(24, 49 + min(0, step), 36, 51 + min(0, step)))
    layers.append(L("stone_body").rect(10 + lean, 16, 34 + lean, 40))  # slab torso
    layers.append(L("stone_dark").rect(14 + lean, 12, 30 + lean, 17))  # shoulders
    layers.append(L("stone_body").rect(18 + lean, 4, 28 + lean, 14))   # blocky head
    # glowing cracks
    for x, y in ((16, 24), (17, 25), (18, 26), (19, 27), (26, 30), (27, 31), (28, 32), (22, 20)):
        details[(x + lean, y)] = "eye_rune"
    if view != "back_right":
        details.update({(20 + lean, 8): "eye_rune", (21 + lean, 8): "eye_rune",
                        (25 + lean, 8): "eye_rune", (26 + lean, 8): "eye_rune"})
    # arms: heavy slabs ending in fists
    if pose == "strike":
        layers.append(L("stone_body").rect(32 + lean, 20, 40, 28))
        layers.append(L("stone_dark").rect(36, 26, 43, 34))
    elif pose == "wind_up":
        layers.append(L("stone_body").rect(30 + lean, 10, 38, 18))
    else:
        layers.append(L("stone_body").rect(32 + lean, 18, 38, 36))
        layers.append(L("stone_dark").rect(31 + lean, 34, 39, 41))
    if view != "back_right":
        layers.append(L("stone_body").rect(6 + lean, 18, 12, 36))
        layers.append(L("stone_dark").rect(5 + lean, 34, 13, 41))
    return compose(W2, H2, layers, details)

SHEETS = {"troll_sheet.png": (W1, H1, troll), "golem_sheet.png": (W2, H2, golem)}

if __name__ == "__main__":
    previews = []
    for name, (width, height, draw) in SHEETS.items():
        sheet = build_sheet(width, height, draw)
        sheet.save(name)
        print(f"{name}: {sheet.size[0]} x {sheet.size[1]} (frames {width} x {height})")
        previews.append(sheet)
    canvas = Image.new("RGBA", (sum(s.width + 20 for s in previews), max(s.height for s in previews)), (58, 62, 78, 255))
    x = 0
    for sheet in previews:
        canvas.alpha_composite(sheet, (x, 0)); x += sheet.width + 20
    canvas.resize((int(canvas.width * 1.6), int(canvas.height * 1.6)), Image.NEAREST).save("/tmp/deep.png")
