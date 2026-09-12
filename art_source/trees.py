# Trees for the village edge: 3 variants, 32 x 44 each, in assets/trees.png.
# Drawn as overlapping leaf clumps so the outline is ragged, never hexagonal.
# They are billboards standing on a hex, wider and taller than the hex itself,
# so their crowns spill over the edges and hide the grid.
import math
from PIL import Image

WIDTH, HEIGHT = 32, 44
OUTLINE = (22, 26, 20, 255)

def rgb(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5)) + (255,)

LEAVES = [(rgb("#3f6b34"), rgb("#5d8f45"), rgb("#2c4d26")),   # summer green
          (rgb("#4a7338"), rgb("#6fa04f"), rgb("#33512a")),   # lighter
          (rgb("#3a5f3c"), rgb("#557f52"), rgb("#28422b"))]   # bluish
TRUNK = (rgb("#5a4230"), rgb("#74563d"), rgb("#3c2b1e"))

class Blob:
    def __init__(self, colors): self.colors, self.pixels = colors, set()
    def ellipse(self, cx, cy, rx, ry):
        for y in range(HEIGHT):
            for x in range(WIDTH):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: self.pixels.add((x, y))
        return self
    def rect(self, l, t, r, b):
        for y in range(t, b + 1):
            for x in range(l, r + 1):
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

def broadleaf(palette, lean=0):
    trunk = Blob(TRUNK).rect(14 + lean, 26, 17 + lean, 43).rect(12 + lean, 40, 19 + lean, 43)
    crown = Blob(LEAVES[palette])
    # Several clumps of different sizes: the silhouette comes out lumpy, not round.
    for cx, cy, rx, ry in ((16, 14, 11, 9), (9, 18, 6.5, 5.5), (23, 17, 7, 6), (16, 7, 7.5, 5.5), (12, 23, 5, 4), (21, 24, 5.5, 4.5)):
        crown.ellipse(cx + lean * 0.5, cy, rx, ry)
    return compose([trunk, crown])

def conifer(palette):
    trunk = Blob(TRUNK).rect(14, 32, 17, 43)
    crown = Blob(LEAVES[palette])
    # Stacked triangles, each a little wider than the one above.
    for row, (top, half_width) in enumerate(((4, 4), (12, 7), (20, 10), (28, 12))):
        for y in range(top, top + 10):
            spread = half_width * (y - top) / 9
            for x in range(int(16 - spread), int(16 + spread) + 1):
                if 0 <= x < WIDTH and 0 <= y < HEIGHT: crown.pixels.add((x, y))
    return compose([trunk, crown])

def bush(palette):
    clump = Blob(LEAVES[palette])
    for cx, cy, rx, ry in ((16, 34, 9, 6), (10, 37, 6, 5), (22, 36, 6.5, 5)):
        clump.ellipse(cx, cy, rx, ry)
    return compose([clump])

if __name__ == "__main__":
    trees = [broadleaf(0), conifer(2), broadleaf(1, lean=1), bush(0)]
    sheet = Image.new("RGBA", (WIDTH * len(trees), HEIGHT), (0, 0, 0, 0))
    for index, tree in enumerate(trees): sheet.paste(tree, (index * WIDTH, 0))
    sheet.save("trees.png")
    preview = Image.new("RGBA", sheet.size, (58, 62, 78, 255)); preview.alpha_composite(sheet)
    preview.resize((sheet.width * 5, sheet.height * 5), Image.NEAREST).save("/tmp/trees_preview.png")
    print(sheet.size)
