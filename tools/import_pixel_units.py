#!/usr/bin/env python3
"""Slice unit sprites for the 2D battle from the Kenney Tiny Dungeon tilemap.

Replaces the procedural sprites from gen_sprites.py with hand-drawn CC0 pixel
art so the 2D modes have nicer figures. Output mirrors gen_sprites.py exactly so
nothing else in the game has to change:

    assets/units/<class>_<team>.png   (32x32, RGBA, NEAREST-friendly)

loaded by src/battle/unit.gd via load("res://assets/units/%s_%s.png").

Source pack (NOT committed — download once into assets/incoming/):
    Kenney "Tiny Dungeon"  https://kenney.nl/assets/tiny-dungeon  (CC0)
    -> Tilemap/tilemap_packed.png  (12 cols x 11 rows of 16x16 tiles)

The class -> tile mapping below was chosen by eye from the pack's character
tiles (run this file's --contact-sheet to regenerate the labelled picker). Each
16x16 tile is scaled x2 to 32x32, composited over a soft grounding shadow. The
player team uses the art as-is; the enemy team is blended toward crimson (a
detail-preserving lerp, not a flat multiply) so the two sides read at a glance.

Usage:
    python3 tools/import_pixel_units.py
    godot --headless --import        # re-import the regenerated PNGs
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
TILEMAP = os.path.join(HERE, "..", "assets", "incoming", "2d",
                       "kenney_tiny-dungeon", "Tilemap", "tilemap_packed.png")
OUT = os.path.join(HERE, "..", "assets", "units")

COLS = 12          # tilemap is 12 tiles wide
TILE = 16          # source tile size
SCALE = 2          # 16 -> 32 to match the existing 32x32 sprites

# class -> tile index (index = row*12 + col). See the contact sheet.
CLASS_TILE = {
    "soldier":    96,    # full-helm knight        — line infantry
    "archer":     112,   # green-headband ranger   — bow
    "scout":      98,    # light brown-tunic man   — fast skirmisher
    "healer":     84,    # purple-robed wizard      — support caster
    "pyromancer": 99,    # robed mage              — offensive caster
    "warlord":    87,    # horned-helm veteran     — commander
    "juggernaut": 110,   # red heavy-armoured brute — tank
}

# Enemy recolour: blend toward crimson while preserving the sprite's detail
# (a luminance-keeping lerp reads far cleaner than a flat multiply).
ENEMY_CRIMSON = (196, 44, 44)
ENEMY_BLEND = 0.36


def _tile(tilemap: Image.Image, idx: int) -> Image.Image:
    c, r = idx % COLS, idx // COLS
    return tilemap.crop((c * TILE, r * TILE, c * TILE + TILE, r * TILE + TILE))


def _blend_enemy(tile: Image.Image) -> Image.Image:
    out = tile.copy()
    px = out.load()
    cr, cg, cb = ENEMY_CRIMSON
    f = ENEMY_BLEND
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = (
                int(r * (1 - f) + cr * f),
                int(g * (1 - f) + cg * f),
                int(b * (1 - f) + cb * f),
                a,
            )
    return out


def _emit(tile: Image.Image, path: str) -> None:
    big = tile.resize((TILE * SCALE, TILE * SCALE), Image.NEAREST)
    size = TILE * SCALE
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Soft grounding shadow under the feet so the unit sits on the tile.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([size * 0.22, size * 0.80, size * 0.78, size * 0.96], fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(big)
    canvas.save(path)


def contact_sheet(tilemap: Image.Image, path: str = "/tmp/td_charsheet.png") -> None:
    """Labelled picker of tiles 72..131 (the humanoid/monster rows)."""
    from PIL import ImageDraw
    start, end, sc = 72, 132, 6
    cw, ch = TILE * sc + 4, TILE * sc + 16
    rows = (end - start + COLS - 1) // COLS
    sheet = Image.new("RGBA", (COLS * cw, rows * ch), (30, 30, 36, 255))
    d = ImageDraw.Draw(sheet)
    for n in range(end - start):
        idx = start + n
        t = _tile(tilemap, idx).resize((TILE * sc, TILE * sc), Image.NEAREST)
        gx, gy = (n % COLS) * cw, (n // COLS) * ch
        sheet.paste(t, (gx + 2, gy + 2), t)
        d.text((gx + 2, gy + TILE * sc + 2), str(idx), fill=(255, 235, 140, 255))
    sheet.save(path)
    print("contact sheet ->", path)


def main() -> None:
    import sys
    tilemap = Image.open(TILEMAP).convert("RGBA")
    if "--contact-sheet" in sys.argv:
        contact_sheet(tilemap)
        return
    os.makedirs(OUT, exist_ok=True)
    for cls, idx in CLASS_TILE.items():
        tile = _tile(tilemap, idx)
        _emit(tile, os.path.join(OUT, f"{cls}_player.png"))
        _emit(_blend_enemy(tile), os.path.join(OUT, f"{cls}_enemy.png"))
        print(f"  {cls:<11} <- tile {idx}")
    print(f"wrote {len(CLASS_TILE) * 2} sprites to assets/units/")


if __name__ == "__main__":
    main()
