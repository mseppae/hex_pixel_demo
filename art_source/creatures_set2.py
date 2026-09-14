# A second set of creature sheets, same layout as the first (6 direction columns x
# 5 pose rows). These are new silhouettes rather than recolours.
from creatures_new import Layer, compose, build_sheet, MATERIALS, DETAIL, rgb
from PIL import Image

MATERIALS.update({
    "slime":      (rgb("#4f9a6a"), rgb("#7fc493"), rgb("#356b4a")),
    "slime_pale": (rgb("#7fc493"), rgb("#a8e0b4"), rgb("#4f9a6a")),
    "leather_wing":(rgb("#5a4258"), rgb("#775a74"), rgb("#3c2b3a")),
    "bat_fur":    (rgb("#6b5566"), rgb("#8a7186"), rgb("#4a3a46")),
    "mush_cap":   (rgb("#a04a4a"), rgb("#c46a64"), rgb("#6e3030")),
    "mush_stalk": (rgb("#d8cbb0"), rgb("#efe6d0"), rgb("#a89a80")),
})

# --- Cave bat: 18 x 16, wide wings, hangs low ---
W1, H1 = 18, 16
def bat(view, pose):
    L = lambda m: Layer(m, W1, H1)
    layers, details = [], {}
    # wings: up when winding up, spread when striking, mid otherwise
    spread = {"idle": 0, "walk_a": -2, "walk_b": 2, "wind_up": -3, "strike": 3}[pose]
    for side in (-1, 1):
        tip_y = 6 + spread * (1 if side > 0 else 1)
        wing = L("leather_wing")
        wing.line(9, 8, 9 + side * 4, 7 + spread // 2, 2.2)
        wing.line(9 + side * 4, 7 + spread // 2, 9 + side * 8, tip_y, 1.8)
        wing.line(9 + side * 8, tip_y, 9 + side * 5, 12, 1.4)
        wing.line(9 + side * 5, 12, 9 + side * 2, 10, 1.6)
        layers.append(wing)
    layers.append(L("bat_fur").ellipse(9, 9, 2.6, 3.2))          # body
    layers.append(L("bat_fur").ellipse(9, 5.5, 2.4, 2))          # head
    layers.append(L("bat_fur").line(7.5, 4, 6.5, 1.5, 1.2))      # ears
    layers.append(L("bat_fur").line(10.5, 4, 11.5, 1.5, 1.2))
    if view != "back_right":
        details.update({(8, 5): "eye", (10, 5): "eye"})
        if pose in ("wind_up", "strike"): details[(9, 7)] = "tooth"
    return compose(W1, H1, layers, details)

# --- Slime: 18 x 14, a blob that squashes and stretches ---
W2, H2 = 18, 14
def slime(view, pose):
    L = lambda m: Layer(m, W2, H2)
    layers, details = [], {}
    squash = {"idle": 0, "walk_a": 1, "walk_b": -1, "wind_up": 2, "strike": -2}[pose]
    width, height = 6 + squash, 4.5 - squash * 0.6
    layers.append(L("slime").ellipse(9, 9.5 + squash * 0.4, width, height))
    layers.append(L("slime_pale").ellipse(7, 8 + squash * 0.4, width * 0.35, height * 0.35))
    if pose == "strike":  # a pseudopod thrown forward
        layers.append(L("slime").line(13, 10, 16, 8, 2.2))
    if view != "back_right":
        eye_y = int(8 + squash * 0.4)
        details.update({(8, eye_y): "dark", (11, eye_y): "dark"})
    # drips
    details[(5, int(12 + squash * 0.3))] = "green" if "green" in DETAIL else "shine"
    return compose(W2, H2, layers, details)

# --- Mushroom walker: 16 x 22, a capped fungus on stubby legs ---
W3, H3 = 16, 22
def mushroom(view, pose):
    L = lambda m: Layer(m, W3, H3)
    layers, details = [], {}
    step = {"idle": 0, "walk_a": 2, "walk_b": -2, "wind_up": 0, "strike": 0}[pose]
    lean = {"wind_up": -1, "strike": 2}.get(pose, 0)
    layers.append(L("mush_stalk").rect(6, 16, 7, 20 - max(0, step)))
    layers.append(L("mush_stalk").rect(9, 16, 10, 20 + min(0, step)))
    layers.append(L("mush_stalk").ellipse(8 + lean, 13, 3.4, 4.6))       # stalk body
    layers.append(L("mush_cap").ellipse(8 + lean, 7, 6.4, 4))            # cap
    layers.append(L("mush_cap").rect(2 + lean, 7, 14 + lean, 8))
    for x, y in ((5, 5), (9, 4), (11, 6)):
        details[(x + lean, y)] = "shine"
    if view != "back_right":
        details.update({(7 + lean, 12): "dark", (10 + lean, 12): "dark"})
    return compose(W3, H3, layers, details)

SHEETS = {"bat_sheet.png": (W1, H1, bat), "slime_sheet.png": (W2, H2, slime),
          "mushroom_sheet.png": (W3, H3, mushroom)}

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
    canvas.resize((canvas.width * 4, canvas.height * 4), Image.NEAREST).save("/tmp/set2.png")
