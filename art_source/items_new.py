# New 16 x 16 item icons, in the same style as assets/item_icons.png.
# Output: new_item_icons.png, one row, to be appended to the existing sheet
# (or kept separate). The order here is the order of the new Item_Kind entries.
from PIL import Image

OUTLINE = (27, 26, 32, 255)
def rgb(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5)) + (255,)

MATERIALS = {
    "steel":   (rgb("#b8c0c8"), rgb("#eef2f6"), rgb("#7c848c")),
    "iron":    (rgb("#8f97a0"), rgb("#b9c0c8"), rgb("#5f666e")),
    "wood":    (rgb("#8a6238"), rgb("#a67a48"), rgb("#5f4225")),
    "dark_wood":(rgb("#5f4225"), rgb("#74542f"), rgb("#43301a")),
    "leather": (rgb("#8a5a30"), rgb("#a87040"), rgb("#603c1c")),
    "gold":    (rgb("#e0b040"), rgb("#f8e27a"), rgb("#a07820")),
    "cord":    (rgb("#cfc2a4"), rgb("#e8dec4"), rgb("#9b8f76")),
    "stone":   (rgb("#8d8a84"), rgb("#aeaba4"), rgb("#63615c")),
    "cloth":   (rgb("#4a6f8c"), rgb("#6a93b0"), rgb("#33506a")),
    "bone":    (rgb("#ded8c4"), rgb("#f4f0e2"), rgb("#a9a189")),
    "green":   (rgb("#4f8f45"), rgb("#6fb35f"), rgb("#356030")),
}
DETAIL = {"shine": rgb("#ffffff"), "dark": rgb("#1b1a20"), "gold": rgb("#f8e27a"),
          "red": rgb("#c82828"), "green": rgb("#6fb35f")}

class Layer:
    def __init__(self, material): self.material, self.pixels = material, set()
    def inside(self, x, y): return 0 <= x < 16 and 0 <= y < 16
    def ellipse(self, cx, cy, rx, ry):
        for y in range(16):
            for x in range(16):
                if ((x+.5-cx)/rx)**2 + ((y+.5-cy)/ry)**2 <= 1: self.pixels.add((x, y))
        return self
    def ring(self, cx, cy, radius, thickness=1.2):
        for y in range(16):
            for x in range(16):
                d = ((x+.5-cx)**2 + (y+.5-cy)**2) ** .5
                if abs(d - radius) <= thickness / 2: self.pixels.add((x, y))
        return self
    def arc(self, cx, cy, radius, start_degrees, end_degrees, thickness=1.2):
        import math
        for y in range(16):
            for x in range(16):
                dx, dy = x+.5-cx, y+.5-cy
                d = (dx*dx + dy*dy) ** .5
                angle = math.degrees(math.atan2(dy, dx)) % 360
                within = start_degrees <= angle <= end_degrees
                if end_degrees > 360: # a range that wraps past 0, e.g. 280..440
                    within = angle >= start_degrees or angle <= end_degrees - 360
                if abs(d - radius) <= thickness/2 and within:
                    self.pixels.add((x, y))
        return self
    def rect(self, l, t, r, b):
        for y in range(int(t), int(b)+1):
            for x in range(int(l), int(r)+1):
                if self.inside(x, y): self.pixels.add((x, y))
        return self
    def line(self, x0, y0, x1, y1, thickness=1.4):
        steps = int(max(abs(x1-x0), abs(y1-y0)) * 3) + 1
        radius = thickness / 2
        for step in range(steps+1):
            t = step/steps
            px, py = x0+(x1-x0)*t, y0+(y1-y0)*t
            for y in range(int(py-radius)-1, int(py+radius)+2):
                for x in range(int(px-radius)-1, int(px+radius)+2):
                    if (x+.5-px)**2 + (y+.5-py)**2 <= radius**2 and self.inside(x, y):
                        self.pixels.add((x, y))
        return self
    def tapered(self, x0, y0, x1, y1, t0, t1):
        for step in range(25):
            t = step/24
            px, py = x0+(x1-x0)*t, y0+(y1-y0)*t
            self.line(px, py, px, py, t0+(t1-t0)*t)
        return self

def icon(*layers, details=None):
    image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for layer in layers:
        base, light, dark = MATERIALS[layer.material]
        for (x, y) in layer.pixels:
            for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if (nx, ny) not in layer.pixels and 0 <= nx < 16 and 0 <= ny < 16:
                    image.putpixel((nx, ny), OUTLINE)
        for (x, y) in layer.pixels:
            color = base
            if (x, y-1) not in layer.pixels: color = light
            if (x, y+1) not in layer.pixels or (x+1, y) not in layer.pixels: color = dark
            image.putpixel((x, y), color)
    for (x, y), name in (details or {}).items():
        if 0 <= x < 16 and 0 <= y < 16: image.putpixel((x, y), DETAIL[name])
    return image

L = Layer

# ---- melee weapons ----
def hand_axe():
    return icon(L("wood").line(3.5, 13.5, 10, 6, 1.8),
                L("steel").ellipse(11.5, 4.5, 3.6, 3.2), L("wood").rect(9, 3, 10, 7),
                details={(13, 3): "shine"})

def mace():
    return icon(L("wood").line(3.5, 13.5, 9, 8, 1.8), L("iron").ellipse(11, 5.5, 3.4, 3.2),
                details={(11, 2): "dark", (14, 5): "dark", (8, 5): "dark", (11, 9): "dark", (10, 4): "shine"})

def war_hammer():
    return icon(L("dark_wood").line(4, 14, 10, 6, 2),
                L("iron").rect(8, 2, 14, 6), L("iron").rect(7, 3, 8, 5),
                details={(9, 2): "shine", (13, 6): "dark"})

def spear():
    return icon(L("wood").line(2.5, 14.5, 11, 5, 1.6), L("steel").tapered(10, 6, 14, 1, 2.6, 0.8),
                L("cord").rect(9, 6, 10, 7), details={(13, 2): "shine"})

def rapier():
    return icon(L("steel").line(5, 12, 14, 2, 1.2), L("dark_wood").line(2.5, 14.5, 4.5, 12.5, 1.8),
                L("gold").ring(5.5, 11.5, 2.2, 1.0), details={(13, 2): "shine"})

def buckler():
    return icon(L("iron").ellipse(8, 8, 6.2, 6.2), L("iron").ellipse(8, 8, 2, 2),
                details={(5, 4): "shine", (8, 8): "shine"})

# ---- ranged weapons ----
def short_bow():
    # At 16 pixels a true arc looks straight, so the limbs are drawn as angled
    # segments meeting at the grip: that reads as a bow at a glance.
    limb = L("wood")
    limb.line(10, 1, 5.5, 4.5, 1.6); limb.line(5.5, 4.5, 4, 8, 1.6)
    limb.line(4, 8, 5.5, 11.5, 1.6); limb.line(5.5, 11.5, 10, 15, 1.6)
    return icon(limb, L("leather").rect(3, 7, 5, 9), L("cord").line(10.5, 1, 10.5, 15, 1.0))

def crossbow():
    return icon(L("dark_wood").rect(7, 5, 9, 15),                    # stock
                L("wood").arc(8, 10, 6.5, 200, 340, 1.6),            # limbs, bowing upward
                L("cord").line(2.5, 8.5, 13.5, 8.5, 1.0),            # string
                L("steel").tapered(8, 7, 8, 2, 1.8, 0.8),            # the loaded bolt
                L("iron").rect(6, 12, 10, 13))

def sling():
    return icon(L("cord").line(4, 1, 6, 8, 1.0), L("cord").line(12, 1, 10, 8, 1.0),
                L("leather").ellipse(8, 10, 3.6, 2.8), L("stone").ellipse(8, 10, 1.8, 1.6))

def boomerang():
    return icon(L("wood").line(2, 12, 8, 3, 2.4), L("wood").line(8, 3, 14, 11, 2.4),
                details={(8, 3): "shine", (3, 12): "dark"})

# ---- ammunition ----
def arrows():
    layers = []
    for offset, tilt in ((-3, 0), (0, 1), (3, 0)):
        layers.append(L("wood").line(8+offset-tilt, 14, 8+offset+tilt, 4, 1.0))
        layers.append(L("steel").tapered(8+offset+tilt, 5, 8+offset+tilt, 1, 1.6, 0.6))
        layers.append(L("cloth").line(8+offset-tilt, 13, 8+offset-tilt, 11, 1.6))
    return icon(*layers)

def bolts():
    layers = []
    for offset in (-3, 1):
        layers.append(L("dark_wood").line(8+offset, 13, 8+offset, 5, 1.4))
        layers.append(L("iron").tapered(8+offset, 6, 8+offset, 2, 2.0, 0.8))
        layers.append(L("cloth").rect(7+offset, 11, 9+offset, 12))
    return icon(*layers)

def rocks():
    return icon(L("stone").ellipse(6, 11, 4, 3.4), L("stone").ellipse(11, 8, 3.4, 3),
                L("stone").ellipse(8, 5, 2.6, 2.2), details={(4, 9): "shine", (10, 6): "shine"})

# ---- other gear ----
def wooden_shield():
    return icon(L("wood").rect(3, 2, 12, 9), L("wood").ellipse(7.5, 9, 5, 4.5),
                L("iron").rect(7, 2, 8, 13), details={(5, 3): "shine"})

def helmet():
    layers = [L("iron").ellipse(8, 7, 5.4, 5), L("iron").rect(3, 7, 12, 12), L("iron").rect(7, 5, 8, 12)]
    details = {(5, 3): "shine", (6, 3): "shine"}
    for x in (4, 5, 6, 9, 10, 11):    # the visor slit
        details[(x, 8)] = "dark"; details[(x, 9)] = "dark"
    return icon(*layers, details=details)

def bone_charm():
    return icon(L("cord").arc(8, 9, 6, 200, 340, 1.0),
                L("bone").ellipse(8, 9, 3.6, 3.2), L("bone").rect(6, 11, 10, 13),
                details={(6, 8): "dark", (7, 8): "dark", (9, 8): "dark", (10, 8): "dark",
                         (7, 12): "dark", (9, 12): "dark"})

def antidote():
    return icon(L("cloth").rect(7, 3, 9, 6), L("green").ellipse(8, 10.5, 4.6, 4.4),
                L("dark_wood").rect(7, 1, 9, 2), details={(6, 8): "shine"})

ICONS = [("Hand_Axe", hand_axe), ("Mace", mace), ("War_Hammer", war_hammer), ("Spear", spear),
         ("Rapier", rapier), ("Buckler", buckler), ("Short_Bow", short_bow), ("Crossbow", crossbow),
         ("Sling", sling), ("Boomerang", boomerang), ("Arrow", arrows), ("Bolt", bolts),
         ("Rock", rocks), ("Wooden_Shield", wooden_shield), ("Helmet", helmet),
         ("Bone_Charm", bone_charm), ("Antidote", antidote)]

if __name__ == "__main__":
    sheet = Image.new("RGBA", (16 * len(ICONS), 16), (0, 0, 0, 0))
    for index, (name, draw) in enumerate(ICONS):
        sheet.paste(draw(), (index * 16, 0))
    sheet.save("new_item_icons.png")
    print(sheet.size, len(ICONS), "icons")
    preview = Image.new("RGBA", sheet.size, (42, 40, 52, 255)); preview.alpha_composite(sheet)
    preview.resize((sheet.width * 6, sheet.height * 6), Image.NEAREST).save("/tmp/new_items.png")
