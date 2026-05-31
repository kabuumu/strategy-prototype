#!/usr/bin/env python3
"""Generate 32x32 pixel-art unit sprites for the strategy prototype.

Three classes (soldier, archer, scout) x two teams (player, enemy).
Output: assets/units/<class>_<team>.png   plus a scaled preview sheet.

Class is conveyed by silhouette/gear; team by palette (player=steel blue,
enemy=crimson). Hand-drawn with PIL primitives at 32x32 so the result stays
crisp pixel art when scaled up with nearest-neighbour filtering in Godot.
"""
import os
from PIL import Image, ImageDraw

S = 32
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "units")

OUTLINE = (26, 20, 32, 255)
SKIN = (224, 176, 136, 255)
SKIN_D = (176, 128, 96, 255)
METAL = (216, 216, 224, 255)   # blades
METAL_D = (140, 140, 156, 255)
WOOD = (138, 90, 48, 255)
WOOD_D = (96, 60, 30, 255)

PALETTES = {
    "player": {
        "armor":  (74, 120, 192, 255),
        "armor_d": (46, 77, 128, 255),
        "accent": (120, 176, 255, 255),
    },
    "enemy": {
        "armor":  (192, 67, 58, 255),
        "armor_d": (128, 42, 37, 255),
        "accent": (255, 122, 110, 255),
    },
}


def px(d, x, y, c):
    d.point((x, y), fill=c)


def rect(d, x0, y0, x1, y1, c):
    d.rectangle((x0, y0, x1, y1), fill=c)


def outline_box(d, x0, y0, x1, y1, fill, line=OUTLINE):
    """Filled box with a 1px dark outline."""
    d.rectangle((x0, y0, x1, y1), fill=line)
    d.rectangle((x0 + 1, y0 + 1, x1 - 1, y1 - 1), fill=fill)


# ---------------------------------------------------------------------------
def soldier(d, p):
    # Plume on helmet top
    rect(d, 15, 2, 16, 5, p["accent"])
    # Helmet
    outline_box(d, 11, 5, 20, 12, p["armor"])
    rect(d, 12, 9, 19, 11, SKIN)            # face slit
    px(d, 12, 12, p["armor_d"]); px(d, 19, 12, p["armor_d"])
    # Torso armour (broad)
    outline_box(d, 9, 13, 22, 24, p["armor"])
    rect(d, 14, 14, 17, 23, p["armor_d"])    # central seam
    rect(d, 10, 15, 12, 18, p["accent"])     # pauldron highlight
    # Shield (left arm)
    outline_box(d, 5, 14, 9, 25, p["armor_d"])
    rect(d, 6, 16, 7, 23, p["accent"])
    # Sword (right arm)
    rect(d, 24, 4, 25, 22, OUTLINE)
    rect(d, 23, 5, 24, 21, METAL)
    rect(d, 22, 21, 26, 23, WOOD)            # crossguard
    rect(d, 23, 23, 24, 26, WOOD_D)          # grip
    # Legs
    outline_box(d, 11, 24, 14, 30, p["armor_d"])
    outline_box(d, 17, 24, 20, 30, p["armor_d"])


def archer(d, p):
    # Pointed hood
    d.polygon([(16, 2), (10, 12), (22, 12)], fill=OUTLINE)
    d.polygon([(16, 4), (11, 11), (21, 11)], fill=p["armor"])
    rect(d, 13, 9, 19, 12, SKIN)             # face
    px(d, 13, 12, SKIN_D); px(d, 18, 12, SKIN_D)
    # Slim tunic
    outline_box(d, 11, 13, 20, 23, p["armor"])
    rect(d, 15, 14, 16, 22, p["armor_d"])
    rect(d, 12, 15, 13, 20, p["accent"])     # quiver strap
    # Bow arc (left side) + string
    for y in range(4, 28):
        t = (y - 16) / 12.0
        bx = int(7 - 3 * (1 - t * t))        # curved limb
        px(d, bx, y, WOOD_D)
        px(d, bx + 1, y, WOOD)
    d.line((6, 5, 6, 27), fill=METAL_D)      # string
    # Arrow nocked
    d.line((6, 16, 21, 16), fill=WOOD)
    d.polygon([(21, 16), (19, 14), (19, 18)], fill=METAL)
    # Legs
    outline_box(d, 12, 23, 15, 30, p["armor_d"])
    outline_box(d, 17, 23, 20, 30, p["armor_d"])


def scout(d, p):
    # Small cap with brim
    outline_box(d, 12, 4, 20, 9, p["armor"])
    rect(d, 19, 6, 23, 7, p["armor_d"])      # brim, pointing ahead
    rect(d, 13, 8, 19, 11, SKIN)             # face
    px(d, 18, 9, SKIN_D)
    # Light leaned-forward torso (speedy)
    d.polygon([(11, 11), (21, 12), (22, 21), (12, 22)], fill=OUTLINE)
    d.polygon([(12, 12), (20, 13), (21, 20), (13, 21)], fill=p["armor"])
    rect(d, 14, 14, 18, 15, p["accent"])     # sash
    rect(d, 13, 13, 22, 14, WOOD)            # shoulder cape line
    # Dagger (right hand, forward)
    rect(d, 22, 17, 26, 18, METAL)
    px(d, 26, 17, METAL); px(d, 27, 17, METAL_D)
    rect(d, 21, 17, 22, 19, WOOD_D)          # hilt
    # Dynamic legs (running)
    outline_box(d, 12, 21, 15, 27, p["armor_d"])
    outline_box(d, 17, 22, 20, 30, p["armor_d"])
    rect(d, 13, 27, 16, 28, OUTLINE)         # trailing foot


def healer(d, p):
    WHITE = (255, 255, 255, 255)
    # Rounded hood/head
    outline_box(d, 12, 5, 20, 12, p["armor"])
    rect(d, 13, 9, 19, 12, SKIN)
    # Robe body
    outline_box(d, 11, 13, 21, 25, p["armor"])
    rect(d, 15, 14, 16, 24, p["armor_d"])
    # White medic cross on the chest
    rect(d, 15, 16, 16, 22, WHITE)
    rect(d, 13, 18, 18, 19, WHITE)
    # Staff with a healing orb
    rect(d, 24, 6, 25, 26, WOOD_D)
    d.ellipse((22, 3, 28, 9), fill=p["accent"])
    d.ellipse((23, 4, 27, 8), fill=WHITE)
    # Legs
    outline_box(d, 12, 25, 15, 30, p["armor_d"])
    outline_box(d, 17, 25, 20, 30, p["armor_d"])


GOLD = (235, 200, 70, 255)
GOLD_D = (170, 135, 35, 255)
FLAME = (255, 140, 30, 255)
FLAME_HOT = (255, 225, 90, 255)


def warlord(d, p):
    # Tattered cape behind the body
    d.polygon([(7, 14), (25, 14), (28, 31), (4, 31)], fill=p["armor_d"])
    # Broad armoured torso
    outline_box(d, 8, 13, 24, 27, p["armor"])
    rect(d, 15, 14, 16, 26, p["armor_d"])         # central seam
    # Gold pauldrons
    outline_box(d, 5, 13, 9, 18, GOLD, GOLD_D)
    outline_box(d, 23, 13, 27, 18, GOLD, GOLD_D)
    # Horned, crowned helm
    outline_box(d, 10, 4, 22, 12, p["armor"])
    rect(d, 12, 8, 20, 11, SKIN)                  # face slit
    rect(d, 13, 9, 14, 10, OUTLINE); rect(d, 18, 9, 19, 10, OUTLINE)  # eyes
    d.polygon([(10, 4), (7, -1), (13, 3)], fill=GOLD)   # left horn
    d.polygon([(22, 4), (25, -1), (19, 3)], fill=GOLD)  # right horn
    for cx in (13, 16, 19):                       # crown spikes
        d.polygon([(cx - 1, 4), (cx + 1, 4), (cx, 0)], fill=GOLD)
    # Massive sword on the right
    rect(d, 26, 2, 28, 24, OUTLINE)
    rect(d, 26, 3, 27, 23, METAL)
    rect(d, 24, 22, 30, 24, GOLD)                 # crossguard
    rect(d, 26, 24, 27, 28, WOOD_D)
    # Legs
    outline_box(d, 10, 27, 14, 31, p["armor_d"])
    outline_box(d, 18, 27, 22, 31, p["armor_d"])


def pyromancer(d, p):
    # Long hooded robe
    d.polygon([(16, 3), (9, 14), (23, 14)], fill=OUTLINE)     # hood outline
    d.polygon([(16, 5), (10, 13), (22, 13)], fill=p["armor"])
    rect(d, 13, 10, 19, 13, SKIN)
    rect(d, 13, 11, 14, 12, FLAME); rect(d, 18, 11, 19, 12, FLAME)  # glowing eyes
    # Robe body, flares to the base
    d.polygon([(11, 14), (21, 14), (24, 30), (8, 30)], fill=OUTLINE)
    d.polygon([(12, 14), (20, 14), (22, 29), (10, 29)], fill=p["armor"])
    rect(d, 15, 15, 16, 28, p["armor_d"])
    # Staff with a flaming orb (left hand)
    rect(d, 6, 6, 7, 30, WOOD_D)
    d.ellipse((2, 1, 11, 10), fill=FLAME)
    d.ellipse((4, 3, 9, 8), fill=FLAME_HOT)
    # Little flames licking off the shoulders
    d.polygon([(21, 16), (24, 10), (26, 17)], fill=FLAME)
    d.polygon([(22, 16), (24, 13), (25, 17)], fill=FLAME_HOT)


def juggernaut(d, p):
    # Enormous spiked shoulders
    outline_box(d, 3, 11, 29, 22, p["armor"])
    for sx in (4, 27):
        d.polygon([(sx, 11), (sx + 1, 5), (sx + 2, 11)], fill=METAL)  # spikes
    # Heavy chest plate
    outline_box(d, 9, 13, 23, 25, p["armor_d"])
    rect(d, 11, 15, 21, 17, GOLD_D)               # belt/trim
    # Tiny sunken head
    outline_box(d, 13, 6, 19, 12, p["armor"])
    rect(d, 14, 9, 18, 11, OUTLINE)               # visor slit
    rect(d, 15, 10, 16, 10, FLAME)                # glowing visor
    # Massive fists
    outline_box(d, 2, 20, 8, 27, p["armor_d"])
    outline_box(d, 24, 20, 30, 27, p["armor_d"])
    # Stubby legs
    outline_box(d, 11, 25, 15, 31, p["armor_d"])
    outline_box(d, 17, 25, 21, 31, p["armor_d"])


DRAW = {
    "soldier": soldier, "archer": archer, "scout": scout, "healer": healer,
    "warlord": warlord, "pyromancer": pyromancer, "juggernaut": juggernaut,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    sprites = {}
    for cls, fn in DRAW.items():
        for team, pal in PALETTES.items():
            img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            fn(d, pal)
            path = os.path.join(OUT, f"{cls}_{team}.png")
            img.save(path)
            sprites[(cls, team)] = img
            print("wrote", os.path.relpath(path))

    # Preview sheet: 3 cols (classes) x 2 rows (teams), scaled 8x
    scale = 8
    cols = len(DRAW)
    sheet = Image.new("RGBA", (cols * S * scale, 2 * S * scale), (40, 44, 40, 255))
    for ci, cls in enumerate(DRAW):
        for ri, team in enumerate(PALETTES):
            big = sprites[(cls, team)].resize((S * scale, S * scale), Image.NEAREST)
            sheet.paste(big, (ci * S * scale, ri * S * scale), big)
    prev = os.path.join(os.path.dirname(__file__), "sprite_preview.png")
    sheet.save(prev)
    print("wrote", os.path.relpath(prev))


if __name__ == "__main__":
    main()
