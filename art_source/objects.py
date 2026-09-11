# Item icons (16 x 16), corpses and chests, drawn from simple shapes.
# Each part is a layer: the script shades it (light top edge, dark bottom/right edge),
# outlines it, and stacks the layers back to front.
# The positions here must match the regions in items.odin.
import math
from PIL import Image

def rgb(hex_string):
    return tuple(int(hex_string[i:i+2], 16) for i in (1, 3, 5)) + (255,)

OUTLINE = rgb("#1b1a20")
MATERIALS = {
    "gold":     (rgb("#e0b040"), rgb("#f8e27a"), rgb("#a07820")),
    "steel":    (rgb("#b8c0c8"), rgb("#eef2f6"), rgb("#7c848c")),
    "wood":     (rgb("#8a6238"), rgb("#a67a48"), rgb("#5f4225")),
    "dark_wood":(rgb("#5f4225"), rgb("#74542f"), rgb("#43301a")),
    "leather":  (rgb("#8a5a30"), rgb("#a87040"), rgb("#603c1c")),
    "red":      (rgb("#c82828"), rgb("#f05858"), rgb("#801818")),
    "glass":    (rgb("#a8c8d8"), rgb("#e0f2fa"), rgb("#7090a0")),
    "chain":    (rgb("#9aa0a8"), rgb("#c4cad0"), rgb("#6a7078")),
    "goblin":   (rgb("#6aa84f"), rgb("#93c96f"), rgb("#4a7a38")),
    "tunic":    (rgb("#7a5230"), rgb("#94683e"), rgb("#56391f")),
    "hood":     (rgb("#3a6b8c"), rgb("#5a93b5"), rgb("#2b4f69")),
    "pants":    (rgb("#4a3b5c"), rgb("#5f4d74"), rgb("#342944")),
    "boots":    (rgb("#3b2a1b"), rgb("#4d3826"), rgb("#2a1d12")),
    "ogre":     (rgb("#8f9a5a"), rgb("#adb872"), rgb("#6b7440")),
    "fur":      (rgb("#6b4a2b"), rgb("#86603a"), rgb("#4e3520")),
    "inside":   (rgb("#2a1e14"), rgb("#3a2a1c"), rgb("#1e150e")),
}
DETAIL = {
    "dark": rgb("#1b1a20"), "shine": rgb("#ffffff"), "tusk": rgb("#e8e0c8"),
    "skin": rgb("#e8b796"), "eye_x": rgb("#1b1a20"), "gold": rgb("#f8e27a"), "gold_dark": rgb("#c89830"),
    "ring_dark": rgb("#6a7078"), "ring_light": rgb("#c4cad0"),
}

class Layer:
    def __init__(self, material, width, height):
        self.material, self.width, self.height = material, width, height
        self.pixels = set()
    def inside(self, x, y):
        return 0 <= x < self.width and 0 <= y < self.height
    def ellipse(self, cx, cy, rx, ry):
        for y in range(self.height):
            for x in range(self.width):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1:
                    self.pixels.add((x, y))
        return self
    def rect(self, left, top, right, bottom):
        for y in range(top, bottom + 1):
            for x in range(left, right + 1):
                if self.inside(x, y): self.pixels.add((x, y))
        return self
    def line(self, x0, y0, x1, y1, thickness):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 3) + 1
        radius = thickness / 2
        for step in range(steps + 1):
            t = step / steps
            px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for y in range(int(py - radius) - 1, int(py + radius) + 2):
                for x in range(int(px - radius) - 1, int(px + radius) + 2):
                    if (x + 0.5 - px) ** 2 + (y + 0.5 - py) ** 2 <= radius ** 2 and self.inside(x, y):
                        self.pixels.add((x, y))
        return self
    def tapered(self, x0, y0, x1, y1, t0, t1):
        for step in range(25):
            t = step / 24
            px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            self.line(px, py, px, py, t0 + (t1 - t0) * t)
        return self

def compose(width, height, layers, details=None):
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for layer in layers:
        base, light, dark = MATERIALS[layer.material]
        for (x, y) in layer.pixels:
            for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if (nx, ny) not in layer.pixels and 0 <= nx < width and 0 <= ny < height:
                    image.putpixel((nx, ny), OUTLINE)
        for (x, y) in layer.pixels:
            color = base
            if (x, y - 1) not in layer.pixels: color = light
            if (x, y + 1) not in layer.pixels or (x + 1, y) not in layer.pixels: color = dark
            image.putpixel((x, y), color)
    for (x, y), name in (details or {}).items():
        if 0 <= x < width and 0 <= y < height:
            image.putpixel((x, y), DETAIL[name])
    return image

# ---------------------------------------------------------------------------
# Item icons, 16 x 16, in Item_Kind order
# ---------------------------------------------------------------------------

def icon(*layers, details=None):
    return compose(16, 16, list(layers), details)

def L(material):
    return Layer(material, 16, 16)

def icon_gold():
    return icon(L("gold").ellipse(6, 11.5, 4.5, 2.4), L("gold").ellipse(10, 9.5, 4.5, 2.4), L("gold").ellipse(7, 6.5, 4.5, 2.4),
                details={(5, 6): "shine", (9, 9): "shine", (4, 11): "shine"})

def icon_potion():
    return icon(L("glass").rect(7, 3, 9, 6), L("red").ellipse(8, 10.5, 5, 4.6), L("wood").rect(7, 1, 9, 2),
                details={(6, 8): "shine", (5, 9): "shine"})

def icon_short_sword():
    return icon(L("steel").line(5, 11, 12.5, 3.5, 2.2), L("wood").line(2.5, 13.5, 4.5, 11.5, 2), L("gold").line(3, 9, 7, 13, 1.6),
                details={(12, 3): "shine"})

def icon_goblin_dagger():
    return icon(L("chain").tapered(5.5, 10.5, 11.5, 4.5, 2.6, 1.2), L("leather").line(3, 13, 5, 11, 2.2), L("dark_wood").line(4, 9, 7, 12, 1.4),
                details={(9, 6): "dark", (11, 5): "shine"})

def icon_spiked_club():
    return icon(L("wood").tapered(3.5, 12.5, 11, 5, 2.2, 5.5),
                details={(13, 5): "shine", (10, 2): "shine", (8, 5): "shine", (12, 8): "shine", (9, 9): "shine"})

def icon_longsword():
    return icon(L("steel").line(4.5, 11.5, 14, 2, 2.2), L("wood").line(1.5, 14.5, 3.5, 12.5, 2), L("gold").line(1.5, 9.5, 6.5, 14.5, 1.8),
                details={(13, 2): "shine", (1, 15): "gold"})

def armor_shape(material):
    return [L(material).rect(4, 4, 11, 13).ellipse(4, 5, 2.6, 2.4).ellipse(11.5, 5, 2.6, 2.4)]

def icon_leather_armor():
    layers = armor_shape("leather") + [L("dark_wood").rect(4, 10, 11, 10)]
    return icon(*layers, details={(7, 4): "dark", (8, 4): "dark", (7, 5): "dark", (8, 5): "dark", (9, 10): "gold"})

def icon_chain_shirt():
    details = {(7, 4): "dark", (8, 4): "dark", (7, 5): "dark", (8, 5): "dark"}
    for y in range(6, 13):
        for x in range(4, 12):
            if (x + y) % 2 == 0 and not (x in (7, 8) and y < 6): details[(x, y)] = "ring_dark" if y % 2 else "ring_light"
    return icon(*armor_shape("chain"), details=details)

ICONS = [icon_gold, icon_potion, icon_short_sword, icon_goblin_dagger, icon_spiked_club, icon_longsword, icon_leather_armor, icon_chain_shirt]

# ---------------------------------------------------------------------------
# Corpses and chests
# ---------------------------------------------------------------------------

def goblin_corpse():
    W, H = 24, 12
    layers = [Layer("chain", W, H).line(15, 10, 21, 10.5, 1.4),                        # dropped dagger
              Layer("goblin", W, H).rect(15, 5, 20, 6).rect(15, 7, 21, 8),              # legs
              Layer("tunic", W, H).ellipse(12, 6.5, 4.5, 3),                            # body
              Layer("goblin", W, H).line(10, 9, 14, 10, 1.6),                           # arm flopped out
              Layer("goblin", W, H).ellipse(5.5, 6, 3.2, 3).line(3, 5, 1, 2.5, 1.4)]   # head with ear
    return compose(W, H, layers, {(4, 5): "eye_x", (6, 5): "eye_x", (5, 7): "tusk"})

def adventurer_corpse():
    W, H = 24, 12
    layers = [Layer("steel", W, H).line(6, 10.5, 16, 10, 1.4),                          # sword on the floor
              Layer("boots", W, H).rect(18, 4, 21, 5).rect(18, 7, 21, 8),
              Layer("pants", W, H).rect(15, 4, 18, 8),
              Layer("hood", W, H).ellipse(11, 6.5, 5, 3.2),                             # cloak
              Layer("hood", W, H).ellipse(5, 6, 3.3, 3.2)]                              # hood
    return compose(W, H, layers, {(4, 6): "skin", (5, 6): "skin", (4, 7): "skin"})

def ogre_corpse():
    W, H = 48, 24
    layers = [Layer("wood", W, H).tapered(18, 21, 36, 20, 2, 5.5),                      # the club, dropped
              Layer("ogre", W, H).rect(34, 9, 42, 12).rect(34, 14, 43, 17),             # legs
              Layer("ogre", W, H).ellipse(23, 12.5, 12, 7),                             # torso
              Layer("fur", W, H).rect(30, 9, 34, 17),                                   # loincloth
              Layer("ogre", W, H).line(18, 17, 24, 19.5, 3.6),                          # arm
              Layer("ogre", W, H).ellipse(8.5, 11.5, 5.5, 5).rect(4, 13, 9, 16)]        # head and jaw
    return compose(W, H, layers, {(7, 10): "eye_x", (10, 10): "eye_x", (5, 14): "tusk", (9, 14): "tusk",
                                  (33, 21): "shine", (30, 18): "shine", (35, 18): "shine"})

def chest(open_lid):
    W, H = 20, 18
    layers = []
    if open_lid:
        layers.append(Layer("dark_wood", W, H).rect(2, 0, 17, 4))                       # lid tipped back
        layers.append(Layer("wood", W, H).rect(2, 6, 17, 16))                           # box
        layers.append(Layer("inside", W, H).rect(3, 6, 16, 8))                          # the dark inside
        layers.append(Layer("steel", W, H).rect(5, 6, 5, 16).rect(14, 6, 14, 16))
        details = {(6, 7): "gold", (7, 7): "gold", (8, 8): "gold_dark", (11, 7): "gold", (12, 8): "gold_dark", (10, 8): "gold"}
    else:
        layers.append(Layer("wood", W, H).rect(2, 8, 17, 16))                           # box
        layers.append(Layer("wood", W, H).rect(2, 4, 17, 7).ellipse(9.5, 5, 8, 2.5))    # rounded lid
        layers.append(Layer("steel", W, H).rect(5, 3, 5, 16).rect(14, 3, 14, 16))       # iron bands
        layers.append(Layer("gold", W, H).rect(9, 7, 10, 9))                            # lock
        details = {}
    return compose(W, H, layers, details)

def build_icons():
    sheet = Image.new("RGBA", (16 * len(ICONS), 16), (0, 0, 0, 0))
    for index, draw in enumerate(ICONS):
        sheet.paste(draw(), (index * 16, 0))
    return sheet

# Layout of objects.png (must match OBJECT_REGIONS in items.odin)
OBJECT_LAYOUT = {
    "goblin_corpse":     (0, 0),
    "adventurer_corpse": (24, 0),
    "ogre_corpse":       (48, 0),
    "chest_closed":      (0, 24),
    "chest_open":        (20, 24),
}

def build_objects():
    sheet = Image.new("RGBA", (96, 48), (0, 0, 0, 0))
    art = {"goblin_corpse": goblin_corpse(), "adventurer_corpse": adventurer_corpse(), "ogre_corpse": ogre_corpse(),
           "chest_closed": chest(False), "chest_open": chest(True)}
    for name, (x, y) in OBJECT_LAYOUT.items():
        sheet.paste(art[name], (x, y))
    return sheet

if __name__ == "__main__":
    icons, objects = build_icons(), build_objects()
    icons.save("item_icons.png")
    objects.save("objects.png")
    preview = Image.new("RGBA", (128 + 8, 16 + 8 + 48), (40, 44, 58, 255))
    preview.alpha_composite(icons, (0, 0))
    preview.alpha_composite(objects, (0, 24))
    preview.resize((preview.width * 7, preview.height * 7), Image.NEAREST).save("/tmp/objects_preview.png")
    print("ok")
