# Three new creature sprite sheets, in the same layout as the existing ones:
# 6 columns (directions, as seen on screen: right, back-right, back-left, left,
# front-left, front-right) x 5 rows (idle, walk A, walk B, attack wind-up, strike).
# Only right, back-right and front-right are drawn; the other three are mirrored.
#
# Drawn from shapes on layers; the script shades each layer (light top edge, dark
# bottom/right edge) and outlines it, then stacks them back to front.
import math
from PIL import Image

OUTLINE = (20, 18, 24, 255)

def rgb(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5)) + (255,)

MATERIALS = {
    "bone":    (rgb("#ded8c4"), rgb("#f4f0e2"), rgb("#a9a189")),
    "bone_dark":(rgb("#b5ad97"), rgb("#cfc7b2"), rgb("#8a8270")),
    "rust":    (rgb("#7a6a52"), rgb("#95836a"), rgb("#574a38")),
    "steel":   (rgb("#b8c0c8"), rgb("#eef2f6"), rgb("#7c848c")),
    "fur":     (rgb("#6b5a45"), rgb("#8a7457"), rgb("#4a3e30")),
    "fur_pale":(rgb("#8a7a63"), rgb("#a89a7d"), rgb("#665844")),
    "flesh":   (rgb("#c08a7a"), rgb("#d8a698"), rgb("#96695c")),
    "chitin":  (rgb("#3c3350"), rgb("#584a72"), rgb("#272036")),
    "chitin_pale":(rgb("#584a72"), rgb("#6f5e8f"), rgb("#3c3350")),
}
DETAIL = {"eye": rgb("#d84a3a"), "eye_pale": rgb("#f0c040"), "tooth": rgb("#f4f0e2"),
          "dark": rgb("#20121a"), "shine": rgb("#ffffff")}

class Layer:
    def __init__(self, material, width, height):
        self.material, self.width, self.height = material, width, height
        self.pixels = set()
    def inside(self, x, y): return 0 <= x < self.width and 0 <= y < self.height
    def ellipse(self, cx, cy, rx, ry):
        for y in range(self.height):
            for x in range(self.width):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: self.pixels.add((x, y))
        return self
    def rect(self, l, t, r, b):
        for y in range(int(t), int(b) + 1):
            for x in range(int(l), int(r) + 1):
                if self.inside(x, y): self.pixels.add((x, y))
        return self
    def line(self, x0, y0, x1, y1, thickness=1.2):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 3) + 1
        radius = thickness / 2
        for step in range(steps + 1):
            t = step / steps
            px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for y in range(int(py - radius) - 1, int(py + radius) + 2):
                for x in range(int(px - radius) - 1, int(px + radius) + 2):
                    if (x + .5 - px) ** 2 + (y + .5 - py) ** 2 <= radius ** 2 and self.inside(x, y):
                        self.pixels.add((x, y))
        return self

def compose(width, height, layers, details=None):
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for layer in layers:
        base, light, dark = MATERIALS[layer.material]
        for (x, y) in layer.pixels:
            for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if (nx, ny) not in layer.pixels and 0 <= nx < width and 0 <= ny < height:
                    image.putpixel((nx, ny), OUTLINE)
        for (x, y) in layer.pixels:
            color = base
            if (x, y - 1) not in layer.pixels: color = light
            if (x, y + 1) not in layer.pixels or (x + 1, y) not in layer.pixels: color = dark
            image.putpixel((x, y), color)
    for (x, y), name in (details or {}).items():
        if 0 <= x < width and 0 <= y < height: image.putpixel((x, y), DETAIL[name])
    return image

def build_sheet(width, height, draw_view):
    """draw_view(view, pose) -> Image, for view in 'front_right'|'right'|'back_right'."""
    poses = ["idle", "walk_a", "walk_b", "wind_up", "strike"]
    sheet = Image.new("RGBA", (width * 6, height * len(poses)), (0, 0, 0, 0))
    for row, pose in enumerate(poses):
        front_right = draw_view("front_right", pose)
        right = draw_view("right", pose)
        back_right = draw_view("back_right", pose)
        frames = [right, back_right, back_right.transpose(Image.FLIP_LEFT_RIGHT),
                  right.transpose(Image.FLIP_LEFT_RIGHT),
                  front_right.transpose(Image.FLIP_LEFT_RIGHT), front_right]
        for column, frame in enumerate(frames):
            sheet.paste(frame, (column * width, row * height))
    return sheet

# ---------------------------------------------------------------------------
# Skeleton: 16 x 24, a humanoid of bone with a rusted sword
# ---------------------------------------------------------------------------
W1, H1 = 16, 24

def skeleton(view, pose):
    L = lambda m: Layer(m, W1, H1)
    layers, details = [], {}
    lift_left = 4 if pose == "walk_a" else 0
    lift_right = 4 if pose == "walk_b" else 0
    lean = 1 if pose == "strike" else (-1 if pose == "wind_up" else 0)

    # the sword, behind the body while winding up
    if pose == "wind_up":
        layers.append(L("rust").line(11, 9, 14, 1, 1.6))
    # legs
    layers.append(L("bone").rect(6, 16, 7, 21 - lift_left).rect(5, 21 - lift_left, 8, 22 - lift_left))
    layers.append(L("bone").rect(9, 16, 10, 21 - lift_right).rect(9, 21 - lift_right, 12, 22 - lift_right))
    # spine and two rib bands: a couple of clear shapes read better than five stripes
    layers.append(L("bone_dark").rect(7 + lean, 10, 8 + lean, 16))
    layers.append(L("bone").rect(5 + lean, 11, 10 + lean, 11))
    layers.append(L("bone").rect(5 + lean, 13, 10 + lean, 13))
    layers.append(L("bone_dark").rect(6 + lean, 15, 9 + lean, 16))  # pelvis
    # skull
    layers.append(L("bone").ellipse(8 + lean, 6, 2.8, 2.6).rect(7 + lean, 7, 9 + lean, 8))
    details.update({(7 + lean, 5): "dark", (9 + lean, 5): "dark", (8 + lean, 8): "dark"})
    if view == "back_right":
        details = {}  # the back of a skull: no face
    # arms and weapon
    if pose == "wind_up":
        layers.append(L("bone").line(11 + lean, 11, 12, 9, 1.4))
    elif pose == "strike":
        layers.append(L("bone").line(11 + lean, 11, 14, 13, 1.4))
        layers.append(L("rust").line(14, 13, 15, 19, 1.6))
    else:
        layers.append(L("bone").line(11 + lean, 11, 12, 15, 1.4))
        layers.append(L("rust").line(13, 15, 15, 8, 1.6))
    if view != "back_right":
        layers.append(L("bone").line(5 + lean, 11, 4, 15, 1.4))
    return compose(W1, H1, layers, details)

# ---------------------------------------------------------------------------
# Giant rat: 20 x 16, low and long
# ---------------------------------------------------------------------------
W2, H2 = 20, 16

def rat(view, pose):
    L = lambda m: Layer(m, W2, H2)
    layers, details = [], {}
    crouch = 1 if pose == "wind_up" else 0
    lunge = 2 if pose == "strike" else 0
    step = 1 if pose == "walk_a" else (-1 if pose == "walk_b" else 0)

    layers.append(L("flesh").line(3, 10, 0, 5, 1.1))                    # long tail
    # legs first, so the body sits in front of them and they show below
    layers.append(L("fur").rect(5, 11 + crouch, 6, 14 + step).rect(4, 14 + step, 7, 14 + step))
    layers.append(L("fur").rect(12, 11 + crouch, 13, 14 - step).rect(11, 14 - step, 14, 14 - step))
    layers.append(L("fur_pale").ellipse(9 - lunge // 2, 9 + crouch, 6, 3.2)) # body, lower and leaner
    head_x = 15 + lunge
    layers.append(L("fur_pale").ellipse(head_x - 2, 9 + crouch, 3.4, 2.8))  # head
    layers.append(L("fur").ellipse(head_x - 4, 6 + crouch, 1.6, 1.8))   # ear
    if view == "front_right":
        layers.append(L("fur").ellipse(head_x - 7, 6 + crouch, 1.6, 1.8))
    if view != "back_right":
        snout = L("flesh").line(head_x + 1, 9 + crouch, head_x + 3, 10 + crouch, 1.4)
        layers.append(snout)
        details[(head_x, 8 + crouch)] = "eye"
        if pose in ("wind_up", "strike"):
            details[(head_x + 2, 11 + crouch)] = "tooth"
            details[(head_x + 3, 11 + crouch)] = "tooth"
    return compose(W2, H2, layers, details)

# ---------------------------------------------------------------------------
# Cave spider: 22 x 18, wide and leggy
# ---------------------------------------------------------------------------
W3, H3 = 22, 18

def spider(view, pose):
    L = lambda m: Layer(m, W3, H3)
    layers, details = [], {}
    rear = 2 if pose == "wind_up" else 0
    lunge = 1 if pose == "strike" else 0
    sway = 1 if pose == "walk_a" else (-1 if pose == "walk_b" else 0)

    # Eight legs, each a knee-bend: they reach well past the body and use the paler
    # shade, or they disappear into it. Drawn first, so the body sits in front.
    body_y = 7 - rear
    for side in (-1, 1):
        for index, (reach, knee_lift) in enumerate(((8, 2), (9, 1), (8, 0), (6, -1))):
            wiggle = (sway if index % 2 else -sway)
            knee_x = 11 + side * reach * 0.55
            knee_y = body_y - knee_lift + wiggle
            layers.append(L("chitin_pale").line(11, body_y + 2, knee_x, knee_y, 1.0))
            layers.append(L("chitin_pale").line(knee_x, knee_y, 11 + side * reach, 16, 1.0))
    layers.append(L("chitin").ellipse(8, body_y + 1, 4.6, 3.6))         # abdomen
    layers.append(L("chitin_pale").ellipse(7, body_y, 2, 1.6))          # marking
    layers.append(L("chitin").ellipse(14 + lunge, body_y + 2, 3, 2.6))  # head
    if view != "back_right":
        details.update({(13 + lunge, body_y + 1): "eye_pale", (15 + lunge, body_y + 1): "eye_pale",
                        (14 + lunge, body_y + 3): "eye_pale"})
        if pose in ("wind_up", "strike"):
            layers.append(L("chitin_pale").line(16 + lunge, body_y + 3, 18 + lunge, body_y + 4, 1.2))
    return compose(W3, H3, layers, details)

SHEETS = {"skeleton_sheet.png": (W1, H1, skeleton),
          "rat_sheet.png": (W2, H2, rat),
          "spider_sheet.png": (W3, H3, spider)}

if __name__ == "__main__":
    previews = []
    for name, (width, height, draw) in SHEETS.items():
        sheet = build_sheet(width, height, draw)
        sheet.save(name)
        print(f"{name}: {sheet.size[0]} x {sheet.size[1]} (frames {width} x {height})")
        previews.append((name, sheet))
    total_width = sum(sheet.width for _, sheet in previews) + 20 * len(previews)
    total_height = max(sheet.height for _, sheet in previews)
    canvas = Image.new("RGBA", (total_width, total_height), (58, 62, 78, 255))
    x = 0
    for _, sheet in previews:
        canvas.alpha_composite(sheet, (x, 0)); x += sheet.width + 20
    canvas.resize((canvas.width * 4, canvas.height * 4), Image.NEAREST).save("/tmp/new_sheets.png")
