# A Scroll of Town Portal's rift: a standing oval of swirling color, 20 x 32,
# in assets/portal.png. Drawn as concentric rings, like looking down a vortex.
from PIL import Image

WIDTH, HEIGHT = 20, 32
OUTLINE = (18, 12, 40, 255)

def rgb(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5)) + (255,)

RINGS = [
    # (rx, ry, base, light, dark) largest (outermost) first
    (7.0, 15.0, rgb("#3a2470"), rgb("#5c3aa8"), rgb("#241650")),
    (5.4, 12.2, rgb("#7d4fd6"), rgb("#a377f0"), rgb("#5a35a8")),
    (3.9,  9.4, rgb("#b98cf5"), rgb("#dcc4ff"), rgb("#8f63d0")),
    (2.4,  6.4, rgb("#160f38"), rgb("#241a52"), rgb("#0c081f")),
]
CORE = rgb("#eafcff")

class Layer:
    def __init__(self, colors): self.colors, self.pixels = colors, set()
    def ellipse(self, cx, cy, rx, ry):
        for y in range(HEIGHT):
            for x in range(WIDTH):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1:
                    self.pixels.add((x, y))
        return self

def compose(layers, details=None):
    image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    for layer in layers:
        base, light, dark = layer.colors
        for (x, y) in layer.pixels:
            for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if (nx, ny) not in layer.pixels and 0 <= nx < WIDTH and 0 <= ny < HEIGHT:
                    image.putpixel((nx, ny), OUTLINE)
        for (x, y) in layer.pixels:
            color = base
            if (x, y - 1) not in layer.pixels: color = light
            if (x, y + 1) not in layer.pixels or (x + 1, y) not in layer.pixels: color = dark
            image.putpixel((x, y), color)
    for (x, y) in (details or []):
        if 0 <= x < WIDTH and 0 <= y < HEIGHT:
            image.putpixel((x, y), CORE)
    return image

def portal():
    cx, cy = WIDTH / 2, HEIGHT / 2 - 1
    layers = [Layer((base, light, dark)).ellipse(cx, cy, rx, ry) for rx, ry, base, light, dark in RINGS]
    # A small bright glint near the top of the void, like light catching the swirl.
    details = [(int(cx) - 1, int(cy) - 4), (int(cx), int(cy) - 4)]
    return compose(layers, details)

if __name__ == "__main__":
    image = portal()
    image.save("portal.png")
    preview = Image.new("RGBA", (WIDTH + 8, HEIGHT + 8), (40, 44, 58, 255))
    preview.alpha_composite(image, (4, 4))
    preview.resize((preview.width * 8, preview.height * 8), Image.NEAREST).save("/tmp/portal_preview.png")
    print("ok")
