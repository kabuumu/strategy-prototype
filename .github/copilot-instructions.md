# Copilot Instructions

## Project

Godot 4.4 turn-based strategy game written in GDScript. Engine version: 4.4, renderer: Forward Plus, viewport: 1280×720 (`canvas_items` stretch).

There are no build/test/lint commands — the game is run and tested through the Godot editor.

## Assets

Sprites (`assets/units/`) and SFX (`assets/sfx/`) are committed and regenerated via `tools/gen_sprites.py` / `tools/gen_sfx.py`.

**3D models are NOT committed** — `assets/models/*.glb` is gitignored (large binaries). The 3D skirmish mode (`src/skirmish3d/`) uses them when present and falls back to procedural low-poly figures otherwise, so it always runs. Check `assets/models/` and `assets/models/README.md` (expected filenames + CC0 sources) before assuming models are available; `SkirmishUnit3D.MODEL_FILES` maps unit type → filename.

## Architecture

### Scene flow

```
title.tscn  →  level_select.tscn  ⇄  battle.tscn
```

The `title` screen resets state and starts a new run. `level_select` handles the overworld map. `battle` handles one tactical fight; when it ends the player is returned to `level_select`.

### GameManager (autoload singleton)

`src/game_manager.gd` is registered as an autoload named `GameManager`. It is the **only** place persistent cross-scene state lives:

- `player_roster: Array[String]` — list of unit type keys the player currently owns
- `map_data: Array` — 2D array `[tier][index]` of node dictionaries
- `current_tier`, `last_chosen_index` — map navigation cursor
- `pending_battle_tier`, `pending_battle_elite` — set by `level_select` immediately before switching to `battle.tscn` so the battle scene knows which encounter to load
- `UNIT_TYPES: Dictionary` — canonical stat block for all unit types (`soldier`, `archer`, `scout`)

`GameManager.reset()` is called at the start of each new game.

### Battle scene (`src/battle/`)

`battle.gd` drives a turn-based Phase state machine:

```
PLAYER_SELECT_UNIT → PLAYER_SELECT_MOVE → PLAYER_SELECT_ATTACK
                                                     ↓
                                               AI_ACTING  →  PLAYER_SELECT_UNIT
                                                     ↓
                                          BATTLE_WON / BATTLE_LOST
```

Key details:
- Grid is 10 columns × 8 rows, `TILE_SIZE = 70` px, origin at `GRID_OFFSET = Vector2(40, 55)`.
- Turns are **interleaved**: after each player unit acts, one AI unit responds immediately. Pressing "End Turn" causes all remaining AI units to act sequentially (recursive `await` chain).
- Objectives at fixed `OBJECTIVE_CELLS` grant `"heal"` (+30 HP to all allies) or `"reinforce"` (spawn a Scout) when a unit steps on them.
- Enemy scaling: HP multiplier = `1.0 + tier * 0.2 + (0.25 if elite)`. Enemy roster is seeded from tier+elite so it is deterministic.

`unit.gd` defines `class_name Unit extends Node2D`. All visual children (body rect, HP bar, label) are created programmatically in `_build_visuals()`. Grid position is stored as `grid_pos: Vector2i`; call `update_visual_position()` after any change.

### Level select scene (`src/level_select/`)

Map is 5 tiers × 3 nodes. Node types: `battle`, `elite_battle`, `gain_unit`, `heal`. Navigation rule: from `last_chosen_index` you may reach `index - 1`, `index`, or `index + 1` in the next tier.

## Key Conventions

### All UI is built in code — no scene-file UI nodes

Every `Label`, `Button`, `ColorRect`, and `StyleBoxFlat` is created in `_build_ui()` / `_ready()`. Do not add UI nodes to `.tscn` files; add them programmatically instead.

### StyleBoxFlat helper pattern

Scenes create `StyleBoxFlat` inline and apply it with `add_theme_stylebox_override`. The `_circle_style(color, radius)` helper in `level_select.gd` and the `_btn_style(color)` helper in `title.gd` show the canonical pattern.

### State mutation goes through GameManager

Never store run-state in individual scene scripts. All mutable game state belongs on `GameManager`. Scene scripts read from and write to `GameManager`, then call `get_tree().change_scene_to_file(...)` to navigate.

### Grid math

All grid↔world coordinate conversion goes through:
```gdscript
world_pos = grid_pos * TILE_SIZE + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)  # centred
cell = Vector2i(int((screen_pos - GRID_OFFSET).x / TILE_SIZE), ...)
```

### Naming patterns

- `_build_*()` — constructs UI nodes
- `_refresh_*()` — updates existing UI nodes to reflect current state  
- `_update_ui()` — main per-phase UI refresh in `battle.gd`, calls `queue_redraw()`
- `_try_*()` — player input handlers that validate before acting
- `_on_*` — signal callbacks

### Unit type keys

Always use the exact lowercase string keys from `GameManager.UNIT_TYPES`: `"soldier"`, `"archer"`, `"scout"`. Stats are looked up via `GameManager.UNIT_TYPES[unit_type]`.
