# Trees for the village edge: 4 variants and two wind frames, 48 x 64 each.
# Drawn as overlapping leaf clumps so the outline is ragged, never hexagonal.
# They are billboards standing on a hex, wider and taller than the hex itself,
# so their crowns spill over the edges and hide the grid.
import math
from PIL import Image

WIDTH, HEIGHT = 48, 64
OUTLINE = (22, 26, 20, 255)

# The extra source resolution makes foliage read at the same density as the new
# character art.  Coordinates below remain in the original 32x44 design space.
sx = lambda value: value * 1.5
sy = lambda value: value * (64 / 44)

def rgb(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5)) + (255,)

# More saturated, higher-contrast foliage holds its shape against the dark
# dungeon backdrop.  Each palette has a sunlit edge, a mid-tone and a deep core.
LEAVES = [(rgb("#3f7b45"), rgb("#82b85b"), rgb("#1f4d32")),
          (rgb("#4f8a48"), rgb("#9bc85d"), rgb("#285438")),
          (rgb("#2d6b58"), rgb("#69a873"), rgb("#174238"))]
TRUNK = (rgb("#6e4731"), rgb("#a87648"), rgb("#3b271e"))

class Blob:
    def __init__(self, colors): self.colors, self.pixels = colors, set()
    def ellipse(self, cx, cy, rx, ry):
        for y in range(HEIGHT):
            for x in range(WIDTH):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: self.pixels.add((x, y))
        return self
    def rect(self, l, t, r, b):
        for y in range(int(t), int(b) + 1):
            for x in range(int(l), int(r) + 1):
                if 0 <= x < WIDTH and 0 <= y < HEIGHT: self.pixels.add((x, y))
        return self

def compose(layers):
    image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    for layer in layers:
        base, light, dark = layer.colors
        for (x, y) in layer.pixels:
            for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if (nx, ny) not in layer.pixels and 0 <= nx < WIDTH and 0 <= ny < HEIGHT:
                    image.putpixel((nx, ny), OUTLINE)
        for (x, y) in layer.pixels:
            color = base
            if (x, y - 1) not in layer.pixels or (x - 1, y - 1) not in layer.pixels: color = light
            if (x, y + 1) not in layer.pixels or (x + 1, y) not in layer.pixels: color = dark
            image.putpixel((x, y), color)
    return image

def foliage_texture(image, foliage, colors, seed):
    """Small, deliberate leaf clusters—not random noise—inside a crown."""
    import random
    rng = random.Random(seed)
    light, dark = colors[1], colors[2]
    interior = [(x, y) for x, y in foliage.pixels
                if all((x + dx, y + dy) in foliage.pixels for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)))]
    for index, (x, y) in enumerate(interior):
        if rng.randrange(31) == 0:
            image.putpixel((x, y), light)
            if (x + 1, y + 1) in foliage.pixels: image.putpixel((x + 1, y + 1), dark)
    return image

def broadleaf(palette, crown_shift=0):
    # The trunk, roots and low branches never move: only foliage bends in the wind.
    trunk = Blob(TRUNK).rect(sx(14), sy(26), sx(17), sy(43)).rect(sx(11), sy(40), sx(20), sy(43))
    trunk.rect(sx(11), sy(29), sx(15), sy(31)).rect(sx(17), sy(27), sx(20), sy(29))
    crown = Blob(LEAVES[palette])
    # Several clumps of different sizes: the silhouette comes out lumpy, not round.
    for cx, cy, rx, ry in ((16, 14, 11, 9), (9, 18, 6.5, 5.5), (23, 17, 7, 6), (16, 7, 7.5, 5.5), (12, 23, 5, 4), (21, 24, 5.5, 4.5)):
        # The upper canopy catches more wind than the low foliage.
        shift = crown_shift if cy < 20 else int(crown_shift * 0.5)
        crown.ellipse(sx(cx + shift), sy(cy), sx(rx), sy(ry))
    return foliage_texture(compose([trunk, crown]), crown, LEAVES[palette], 100 + palette * 11 + crown_shift)

def conifer(palette, lean=0):
    # Fixed trunk and roots; the narrow upper boughs get the largest sway.
    trunk = Blob(TRUNK).rect(sx(14), sy(32), sx(17), sy(43)).rect(sx(12), sy(41), sx(19), sy(43))
    crown = Blob(LEAVES[palette])
    # Stacked triangles, each a little wider than the one above.
    for row, (top, half_width) in enumerate(((4, 4), (12, 7), (20, 10), (28, 12))):
        for y in range(top, top + 10):
            spread = half_width * (y - top) / 9
            # The lower boughs barely move; the crown catches the wind most.
            sway = lean * max(0, 3 - row)
            for x in range(int(sx(16 - spread + sway)), int(sx(16 + spread + sway)) + 1):
                # Fill every destination row: scaling must never turn a bough
                # into separated horizontal stripes.
                for scaled_y in range(int(sy(y)), int(sy(y + 1)) + 1):
                    if 0 <= x < WIDTH and 0 <= scaled_y < HEIGHT: crown.pixels.add((x, scaled_y))
    return foliage_texture(compose([trunk, crown]), crown, LEAVES[palette], 200 + lean)

def bush(palette, lean=0):
    clump = Blob(LEAVES[palette])
    for cx, cy, rx, ry in ((16, 34, 9, 6), (10, 37, 6, 5), (22, 36, 6.5, 5)):
        # Bushes have no visible trunk, but their low edge stays almost planted.
        clump.ellipse(sx(cx + (lean if cy < 36 else int(lean * 0.35))), sy(cy), sx(rx), sy(ry))
    return foliage_texture(compose([clump]), clump, LEAVES[palette], 300 + lean)

if __name__ == "__main__":
    # Frame 0 is the calm pose. Frame 1 is a small, asymmetric gust; it is
    # deliberately not a translated copy, which keeps roots and silhouettes crisp.
    frames = [
        [broadleaf(0), conifer(2), broadleaf(1), bush(0)],
        [broadleaf(0, crown_shift=-2), conifer(2, lean=-1), broadleaf(1, crown_shift=-2), bush(0, lean=-2)],
    ]
    sheet = Image.new("RGBA", (WIDTH * len(frames[0]), HEIGHT * len(frames)), (0, 0, 0, 0))
    for frame_index, trees in enumerate(frames):
        for index, tree in enumerate(trees): sheet.paste(tree, (index * WIDTH, frame_index * HEIGHT))
    sheet.save("trees.png")
    preview = Image.new("RGBA", sheet.size, (58, 62, 78, 255)); preview.alpha_composite(sheet)
    preview.resize((sheet.width * 5, sheet.height * 5), Image.NEAREST).save("/tmp/trees_preview.png")
    print(sheet.size)
