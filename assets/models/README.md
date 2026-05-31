# 3D model assets (not committed)

The 3D skirmish mode (`src/skirmish3d/`) can use external low-poly character
models for the regiment lead figures. These `.glb` files are **deliberately
not committed** — they're binary and would bloat the repo — so this folder is
gitignored except for this README.

**The game works without them.** If a model is missing, the unit falls back to
a procedural low-poly figure built from primitives (`skirmish_unit_3d.gd
_build_figure`). Drop the files in to upgrade the look.

## Expected files

Place these in `assets/models/` (exact names matter — see
`SkirmishUnit3D.MODEL_FILES`):

| File            | Used for (regiment) |
|-----------------|---------------------|
| `infantry.glb`  | Infantry (soldier)  |
| `archer.glb`    | Archers (archer)    |
| `cavalry.glb`   | Cavalry (scout)     |
| `spearman.glb`  | Spearmen (healer)   |

Models should be roughly **1.5–2 units tall**, facing +X (they're rotated to
face inward per team), origin at the feet. A team-coloured base disc is added
under each so the two sides stay distinguishable with a shared model.

## Where to get CC0 models

Any CC0 / public-domain low-poly humanoids work. Recommended:

- **Kenney — Mini Characters / Blocky Characters / Castle Kit**
  <https://kenney.nl/assets> (CC0). Export/rename the character `.glb`s to the
  names above.
- **Quaternius — Universal Animation Library / Ultimate Modular Characters**
  <https://quaternius.com/> (CC0).
- **Poly Pizza** <https://poly.pizza/> (filter by CC0).

After adding files, open the project in the Godot editor once so it imports the
`.glb`s (or run `godot --headless --import`). The generated `.import` files are
also gitignored.

## License

Only add assets you have the right to use. Prefer CC0 so no attribution is
required. If you use assets needing attribution, record it here.
