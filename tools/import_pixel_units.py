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
16x16 tile is scaled x2 to 32x32. The player team uses the art as-is; the enemy
team gets a red multiply tint so the two sides read at a glance (matching the
old blue/crimson convention).

Usage:
    python3 tools/import_pixel_units.py
    godot --headless --import        # re-import the regenerated PNGs
"""
import os
from PIL import Image

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

# Enemy tint: multiply the sprite toward crimson so the two teams are distinct.
ENEMY_TINT = (255, 110, 110)


def _tile(tilemap: Image.Image, idx: int) -> Image.Image:
    c, r = idx % COLS, idx // COLS
    return tilemap.crop((c * TILE, r * TILE, c * TILE + TILE, r * TILE + TILE))


def _tinted(tile: Image.Image, rgb) -> Image.Image:
    out = tile.copy()
    px = out.load()
    tr, tg, tb = rgb
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = (r * tr // 255, g * tg // 255, b * tb // 255, a)
    return out


def _emit(tile: Image.Image, path: str) -> None:
    big = tile.resize((TILE * SCALE, TILE * SCALE), Image.NEAREST)
    big.save(path)


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
        _emit(_tinted(tile, ENEMY_TINT), os.path.join(OUT, f"{cls}_enemy.png"))
        print(f"  {cls:<11} <- tile {idx}")
    print(f"wrote {len(CLASS_TILE) * 2} sprites to assets/units/")


if __name__ == "__main__":
    main()
