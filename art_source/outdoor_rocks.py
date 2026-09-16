"""Three pointed outdoor-rock formations, 48x64, for the village edge."""
from PIL import Image, ImageDraw

W, H = 48, 64
PALETTES = [((96,113,130,255),(156,178,190,255),(48,62,79,255)), ((86,104,119,255),(143,166,177,255),(42,57,72,255)), ((106,117,127,255),(173,187,192,255),(56,65,75,255))]
OUTLINE=(25,34,44,255)

def rock(kind, palette):
    base, light, dark = palette
    im=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(im)
    points=[[(6,60),(12,43),(18,47),(22,19),(29,42),(35,46),(42,60)],
            [(5,60),(10,48),(18,51),(25,12),(31,42),(39,49),(43,60)],
            [(4,60),(13,46),(20,50),(28,23),(34,43),(42,52),(44,60)]][kind]
    d.polygon(points,fill=OUTLINE)
    inner=[(x, y-2 if y>25 else y+2) for x,y in points]
    d.polygon(inner,fill=base)
    d.polygon(inner[:4],fill=light)
    d.polygon([inner[3],inner[4],inner[5],inner[6],inner[0]],fill=dark)
    # angular facets
    d.line([(18,49),(22,23),(28,43)],fill=OUTLINE,width=2)
    d.line([(22,23),(26,37)],fill=light,width=1)
    d.line([(10,55),(18,49)],fill=light,width=1)
    return im

if __name__=='__main__':
    sheet=Image.new('RGBA',(W*3,H),(0,0,0,0))
    for i,p in enumerate(PALETTES): sheet.alpha_composite(rock(i,p),(i*W,0))
    sheet.save('outdoor_rocks.png')
    print(sheet.size)
