# Ogre sprite sheet: 40 x 48 frames, 6 directions x 5 poses.
# Each body part is drawn as filled shapes on its own layer; the script then shades
# each layer (light top edge, dark bottom/right edge) and gives it a 1-pixel outline,
# and stacks the layers back to front.
import math
from PIL import Image

FRAME_WIDTH, FRAME_HEIGHT = 40, 48

def rgb(hex_string):
    return tuple(int(hex_string[i:i+2], 16) for i in (1, 3, 5)) + (255,)

OUTLINE = rgb("#1e1a16")
MATERIALS = {
    # name: (base, light, dark)
    "skin":   (rgb("#8f9a5a"), rgb("#adb872"), rgb("#6b7440")),
    "belly":  (rgb("#a9a86c"), rgb("#c2c184"), rgb("#8a8a52")),
    "fur":    (rgb("#6b4a2b"), rgb("#86603a"), rgb("#4e3520")),
    "wood":   (rgb("#8a6238"), rgb("#a67a48"), rgb("#5f4225")),
    "strap":  (rgb("#3b2a1b"), rgb("#4d3826"), rgb("#2a1d12")),
}
DETAIL = {
    "eye": rgb("#d8402a"), "brow": rgb("#4f5530"), "mouth": rgb("#2a2616"),
    "tusk": rgb("#e8e0c8"), "nail": rgb("#c8c8c0"), "nail_dark": rgb("#8c8c84"),
}

class Layer:
    def __init__(self, material):
        self.material = material
        self.pixels = set()
    def ellipse(self, center_x, center_y, radius_x, radius_y):
        for y in range(FRAME_HEIGHT):
            for x in range(FRAME_WIDTH):
                if ((x + 0.5 - center_x) / radius_x) ** 2 + ((y + 0.5 - center_y) / radius_y) ** 2 <= 1:
                    self.pixels.add((x, y))
        return self
    def rect(self, left, top, right, bottom):
        for y in range(top, bottom + 1):
            for x in range(left, right + 1):
                if 0 <= x < FRAME_WIDTH and 0 <= y < FRAME_HEIGHT:
                    self.pixels.add((x, y))
        return self
    def thick_line(self, start_x, start_y, end_x, end_y, thickness):
        steps = int(max(abs(end_x - start_x), abs(end_y - start_y)) * 2) + 1
        radius = thickness / 2
        for step in range(steps + 1):
            t = step / steps
            px, py = start_x + (end_x - start_x) * t, start_y + (end_y - start_y) * t
            for y in range(int(py - radius) - 1, int(py + radius) + 2):
                for x in range(int(px - radius) - 1, int(px + radius) + 2):
                    if (x + 0.5 - px) ** 2 + (y + 0.5 - py) ** 2 <= radius ** 2 and 0 <= x < FRAME_WIDTH and 0 <= y < FRAME_HEIGHT:
                        self.pixels.add((x, y))
        return self
    def tapered_line(self, start_x, start_y, end_x, end_y, start_thickness, end_thickness):
        steps = 24
        for step in range(steps + 1):
            t = step / steps
            px, py = start_x + (end_x - start_x) * t, start_y + (end_y - start_y) * t
            self.thick_line(px, py, px, py, start_thickness + (end_thickness - start_thickness) * t)
        return self

def compose(layers, details):
    frame = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT), (0, 0, 0, 0))
    for layer in layers:
        base, light, dark = MATERIALS[layer.material]
        # Outline ring first, so it separates this part from whatever is behind it.
        for (x, y) in layer.pixels:
            for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if (nx, ny) not in layer.pixels and 0 <= nx < FRAME_WIDTH and 0 <= ny < FRAME_HEIGHT:
                    frame.putpixel((nx, ny), OUTLINE)
        for (x, y) in layer.pixels:
            color = base
            if (x, y - 1) not in layer.pixels or (x - 1, y - 1) not in layer.pixels and (x, y - 2) not in layer.pixels:
                color = light   # lit from above
            if (x, y + 1) not in layer.pixels or (x + 1, y) not in layer.pixels:
                color = dark    # shadowed bottom and right edges
            frame.putpixel((x, y), color)
    for (x, y), name in details.items():
        if 0 <= x < FRAME_WIDTH and 0 <= y < FRAME_HEIGHT:
            frame.putpixel((x, y), DETAIL[name])
    return frame

def club_layers(handle_x, handle_y, head_x, head_y):
    # A crude club: a thin shaft, then a thick knobbly head studded with nails.
    shaft = Layer("wood").thick_line(handle_x, handle_y, head_x + (handle_x - head_x) * 0.45, head_y + (handle_y - head_y) * 0.45, 2.2)
    head = Layer("wood").tapered_line(head_x + (handle_x - head_x) * 0.5, head_y + (handle_y - head_y) * 0.5, head_x, head_y, 3.2, 6.5)
    nails = {}
    length = math.hypot(head_x - handle_x, head_y - handle_y)
    across_x, across_y = -(head_y - handle_y) / length, (head_x - handle_x) / length
    for fraction, side, reach in ((0.1, 1, 3.6), (0.25, -1, 3.4), (0.38, 1, 2.8), (0.05, -1, 3.8)):
        px = head_x + (handle_x - head_x) * fraction + across_x * side * reach
        py = head_y + (handle_y - head_y) * fraction + across_y * side * reach
        nails[(int(round(px)), int(round(py)))] = "nail"
    return [shaft, head], nails

# ---------------------------------------------------------------------------
# Legs for each view: idle, step A (one foot lifted), step B (the other)
# ---------------------------------------------------------------------------

def front_legs(variant):
    layers = []
    left_lift = 5 if variant == "step_a" else 0
    right_lift = 5 if variant == "step_b" else 0
    layers.append(Layer("skin").rect(12, 36, 17, 43 - left_lift).rect(11, 43 - left_lift, 19, 45 - left_lift))
    layers.append(Layer("skin").rect(22, 36, 27, 43 - right_lift).rect(21, 43 - right_lift, 30, 45 - right_lift))
    return layers

def side_legs(variant):
    if variant == "step_a":   # wide stride
        return [Layer("skin").rect(10, 35, 15, 43).rect(8, 43, 16, 45),
                Layer("skin").rect(22, 35, 27, 43).rect(22, 43, 31, 45)]
    if variant == "step_b":   # passing: back foot lifted
        return [Layer("skin").rect(13, 35, 18, 40).rect(11, 40, 18, 42),
                Layer("skin").rect(18, 35, 23, 43).rect(18, 43, 27, 45)]
    return [Layer("skin").rect(13, 35, 18, 43).rect(12, 43, 20, 45),
            Layer("skin").rect(20, 35, 25, 43).rect(20, 43, 29, 45)]

# ---------------------------------------------------------------------------
# The three hand-set views. `pose` is "rest", "wind_up" or "strike".
# ---------------------------------------------------------------------------

def front_right(legs_variant, pose):
    layers, details = [], {}
    if pose == "wind_up":
        club, nails = club_layers(24, 9, 7, 5)
        layers += club
        details.update(nails)
    layers += front_legs(legs_variant)
    layers.append(Layer("skin").ellipse(19.5, 26, 12, 10.5))                 # torso
    layers.append(Layer("belly").ellipse(21.5, 29, 7, 5))                   # belly
    layers.append(Layer("fur").rect(10, 33, 29, 37).rect(11, 38, 13, 38).rect(16, 38, 19, 38).rect(23, 38, 26, 38))
    layers.append(Layer("strap").thick_line(11, 20, 29, 32, 1.6))           # strap across the chest
    layers.append(Layer("skin").ellipse(22, 15, 6.5, 5.5))                  # head
    details.update({(20, 13): "brow", (21, 13): "brow", (24, 13): "brow", (25, 13): "brow",
                    (21, 14): "eye", (25, 14): "eye", (23, 16): "mouth",
                    (20, 18): "mouth", (21, 18): "mouth", (22, 18): "mouth", (23, 18): "mouth", (24, 18): "mouth", (25, 18): "mouth",
                    (20, 17): "tusk", (25, 17): "tusk"})
    if pose == "rest":
        layers.append(Layer("skin").thick_line(10, 22, 21, 31, 4.5))        # back arm reaching across
        club, nails = club_layers(22, 34, 35, 7)
        layers += club
        details.update(nails)
        layers.append(Layer("skin").thick_line(30, 22, 26, 30, 4.5))        # front arm
        layers.append(Layer("skin").ellipse(22, 31, 2.6, 2.6))
        layers.append(Layer("skin").ellipse(26, 29.5, 2.6, 2.6))
    elif pose == "wind_up":
        layers.append(Layer("skin").thick_line(10, 22, 21, 9, 4.5))
        layers.append(Layer("skin").thick_line(30, 22, 27, 9, 4.5))
        layers.append(Layer("skin").ellipse(22, 8, 2.6, 2.6))
        layers.append(Layer("skin").ellipse(26, 7.5, 2.6, 2.6))
    else:  # strike: club smashed down in front
        layers.append(Layer("skin").thick_line(10, 22, 25, 32, 4.5))
        layers.append(Layer("skin").thick_line(30, 22, 30, 31, 4.5))
        club, nails = club_layers(28, 32, 36, 44)
        layers += club
        details.update(nails)
        layers.append(Layer("skin").ellipse(26, 32, 2.6, 2.6))
        layers.append(Layer("skin").ellipse(30, 32, 2.6, 2.6))
    return compose(layers, details)

def right(legs_variant, pose):
    layers, details = [], {}
    if pose == "rest":
        club, nails = club_layers(27, 31, 9, 6)
        layers += club
        details.update(nails)
    elif pose == "wind_up":
        club, nails = club_layers(24, 8, 7, 6)
        layers += club
        details.update(nails)
    layers += side_legs(legs_variant)
    layers.append(Layer("skin").ellipse(18, 27, 10, 10))                    # torso
    layers.append(Layer("skin").ellipse(14, 23, 7, 6))                      # hunched back
    layers.append(Layer("belly").ellipse(23, 30, 5, 5))
    layers.append(Layer("fur").rect(10, 33, 27, 37).rect(11, 38, 13, 38).rect(17, 38, 20, 38).rect(24, 38, 26, 38))
    layers.append(Layer("skin").ellipse(27, 18, 5.5, 5).rect(27, 19, 32, 22))  # head with jutting jaw
    details.update({(27, 15): "brow", (28, 15): "brow", (29, 15): "brow", (29, 16): "eye",
                    (31, 17): "mouth", (28, 21): "mouth", (29, 21): "mouth", (30, 21): "mouth", (31, 21): "mouth",
                    (31, 20): "tusk"})
    if pose == "rest":
        layers.append(Layer("skin").thick_line(18, 22, 27, 30, 4.5))
        layers.append(Layer("skin").ellipse(27.5, 30.5, 2.8, 2.8))
    elif pose == "wind_up":
        layers.append(Layer("skin").thick_line(18, 22, 23, 9, 4.5))
        layers.append(Layer("skin").ellipse(23.5, 8, 2.8, 2.8))
    else:
        layers.append(Layer("skin").thick_line(18, 22, 30, 29, 4.5))
        club, nails = club_layers(30, 30, 38, 43)
        layers += club
        details.update(nails)
        layers.append(Layer("skin").ellipse(30.5, 29.5, 2.8, 2.8))
    return compose(layers, details)

def back_right(legs_variant, pose):
    layers, details = [], {}
    if pose == "strike":
        club, nails = club_layers(28, 27, 34, 19)   # club head lands out ahead, beyond the body
        layers += club
        details.update(nails)
    layers += front_legs(legs_variant)
    layers.append(Layer("skin").ellipse(19.5, 26, 12, 10.5))
    layers.append(Layer("skin").ellipse(18, 22, 8, 5))                      # shoulder hump
    layers.append(Layer("fur").rect(10, 33, 29, 37).rect(11, 38, 13, 38).rect(16, 38, 19, 38).rect(23, 38, 26, 38))
    layers.append(Layer("strap").thick_line(29, 20, 11, 32, 1.6))
    layers.append(Layer("skin").ellipse(23, 15, 6, 5.5))                    # back of the head
    details.update({(29, 14): "brow"})
    if pose == "rest":
        club, nails = club_layers(28, 31, 34, 5)
        layers += club
        details.update(nails)
        layers.append(Layer("skin").thick_line(30, 22, 28, 30, 4.5))
        layers.append(Layer("skin").ellipse(28, 31, 2.6, 2.6))
    elif pose == "wind_up":
        layers.append(Layer("skin").thick_line(10, 22, 20, 9, 4.5))
        layers.append(Layer("skin").thick_line(30, 22, 26, 9, 4.5))
        club, nails = club_layers(24, 9, 8, 5)
        layers += club
        details.update(nails)
        layers.append(Layer("skin").ellipse(21, 8, 2.6, 2.6))
        layers.append(Layer("skin").ellipse(26, 8, 2.6, 2.6))
    else:
        layers.append(Layer("skin").thick_line(30, 22, 30, 28, 4.5))
        layers.append(Layer("skin").ellipse(29.5, 28, 2.6, 2.6))
    return compose(layers, details)

POSES = [("idle", "rest"), ("step_a", "rest"), ("step_b", "rest"), ("idle", "wind_up"), ("idle", "strike")]

def mirror(image):
    return image.transpose(Image.FLIP_LEFT_RIGHT)

def build_ogre_sheet():
    sheet = Image.new("RGBA", (FRAME_WIDTH * 6, FRAME_HEIGHT * len(POSES)), (0, 0, 0, 0))
    for row, (legs_variant, pose) in enumerate(POSES):
        fr, rt, br = front_right(legs_variant, pose), right(legs_variant, pose), back_right(legs_variant, pose)
        frames = [rt, br, mirror(br), mirror(rt), mirror(fr), fr]   # hexgrid.Direction order on screen
        for column, frame in enumerate(frames):
            sheet.paste(frame, (column * FRAME_WIDTH, row * FRAME_HEIGHT))
    return sheet

if __name__ == "__main__":
    sheet = build_ogre_sheet()
    sheet.save("ogre_sheet.png")
    preview = Image.new("RGBA", sheet.size, (40, 44, 58, 255))
    preview.alpha_composite(sheet)
    preview.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save("/tmp/ogre_preview.png")
    print(sheet.size)
