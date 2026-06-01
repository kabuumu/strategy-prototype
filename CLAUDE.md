# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> A complementary `.github/copilot-instructions.md` exists with overlapping guidance. Keep the two in sync when changing conventions.

## Project

Godot 4.4 turn-based strategy game in GDScript. Renderer: Forward Plus. Viewport 1280×720, `canvas_items` stretch. Main scene: `src/title/title.tscn`.

## Assets

Sprites (`assets/units/`), SFX (`assets/sfx/`) and music (`assets/music/`) are committed. SFX come from `tools/gen_sfx.py`; chiptune music loops from `tools/gen_music.py` (pure-stdlib WAV synthesis, played by the `Music` autoload — `src/music.gd` — which loops a track per scene and rides the Master bus). Unit sprites (32×32, `<class>_<team>.png`, loaded by `unit.gd`) are sliced from the CC0 **Kenney Tiny Dungeon** tilemap by `tools/import_pixel_units.py` (per-class tile index + enemy crimson blend + grounding shadow in that file's header); `tools/gen_sprites.py` is the older procedural generator, kept as a fallback. After regenerating any of these, run `godot --headless --import`. Boot-test everything with `tools/smoke_test.sh`.

**Raw downloaded asset packs are NOT committed.** Source art (tilemaps, model packs) lives in the gitignored `assets/incoming/` staging area — re-download per the sources in `tools/import_pixel_units.py` / `assets/models/README.md` if absent. Only the processed outputs (`assets/units/*.png`, renamed `.glb`s) are kept.

**3D models are NOT committed.** `assets/models/*.glb` is gitignored (binary, large). The 3D skirmish mode (`src/skirmish3d/`) loads them if present and otherwise falls back to procedural low-poly figures — so the game always runs without them. Before assuming 3D models are available, check `assets/models/` and read `assets/models/README.md` (lists expected filenames + CC0 sources + the exact KayKit Adventurers mapping used). `SkirmishUnit3D.MODEL_FILES` maps unit type → filename.

## Commands

The game is normally run and tested through the Godot editor — there is no unit-test or lint suite.

Headless web export (mirrors CI in `.github/workflows/deploy.yml`, Godot 4.4):
```bash
godot --headless --import                                   # import assets first
godot --headless --export-release "Web" build/web/index.html
```
Push to `main` triggers the GitHub Pages build/deploy workflow. The CI adds a COOP/COEP service worker (Godot 4 WASM threading needs these headers, which Pages can't set) and cache-busts asset URLs with `?v=<short-sha>`.

## Architecture

Scene flow: `title.tscn → level_select.tscn ⇄ <battle scene>`. Title resets state and starts a run; `level_select` is the overworld map; a battle node launches one fight that returns to `level_select` when it ends. The battle scene depends on the run's `GameManager.battle_mode`: `"2d"` → `battle.tscn` (hex turn-based), `"3d"` → `skirmish3d.tscn` (real-time, `pending_skirmish`), `"auto"` → `autobattler.tscn` (auto-resolved fight, `pending_autobattle`), `"td"` → `towerdefense.tscn` (wave defence, `pending_td`), `"base"` → `basebuilder.tscn` (build-and-raze RTS, `pending_base`). Every one of these is *also* a standalone mode from the title (no campaign state). The shared contract for the campaign path of each: build the fight from `player_roster` + `get_battle_enemy_roster`/tier, then on resolution report back to GameManager (survivors via `set_roster` where applicable, `register_battle_won`, `battle_gold_reward`, elite `grant_random_relic`, `save_run`) on a win or `clear_run` on a loss — look at `_conclude_campaign` in autobattler/towerdefense/basebuilder for the pattern. The hex `battle.gd` does the same inline (`_trigger_win`/`_trigger_loss`).

### GameManager (autoload singleton) — `src/game_manager.gd`

The **only** place persistent cross-scene state lives. Scene scripts read/write it, then call `get_tree().change_scene_to_file(...)`. Never store run-state in individual scene scripts.

- `UNIT_TYPES` — canonical stat blocks. Always use exact lowercase keys: `"soldier"`, `"archer"`, `"scout"`.
- `player_roster`, `map_data` (2D `[tier][index]` array of node dicts), `current_tier`, `last_chosen_index`.
- `pending_battle_tier` / `pending_battle_elite` — set by `level_select` right before switching to `battle.tscn`.
- `reset()` runs at start of each new game and regenerates the map.

### Map (`level_select`)

5 tiers. Tier 0 = 2–3 varied starting nodes (one tougher `elite_battle`, never all battles — see `_starting_node_types`); middle tiers = 2–5 nodes; final tier = single boss (`elite_battle`). Connections wired per adjacent tier pair (proportional mapping + occasional branch); every target guaranteed an incoming edge. Reachable nodes come from the last visited node's `connections`; before any node is visited every tier-0 node is selectable. Node types: `battle`, `elite_battle`, `gain_unit`, `shop`, `heal`.

### Battle (`src/battle/`)

`battle.gd` runs a Phase state machine: `PLAYER_SELECT_UNIT → PLAYER_SELECT_MOVE → PLAYER_SELECT_ATTACK → AI_ACTING → PLAYER_SELECT_UNIT`, terminating in `BATTLE_WON` / `BATTLE_LOST`.

- Grid 10×8, `TILE_SIZE = 70`, origin `GRID_OFFSET = Vector2(40, 55)`. Mountain terrain blocks movement.
- Turns interleave: each player unit acting triggers one immediate AI response; "End Turn" runs all remaining AI sequentially via a recursive `await` chain.
- Objectives at fixed cells grant `"heal"` (+30 HP all allies) or `"reinforce"` (spawn Scout) when stepped on; captured objectives disappear.
- Enemy scaling: HP mult = `1.0 + tier*0.2 + (0.25 if elite)`; roster seeded from tier+elite (deterministic).

`unit.gd` is `class_name Unit extends Node2D`. Visual children (body rect, HP bar, label) built in `_build_visuals()`. Grid position in `grid_pos: Vector2i`; call `update_visual_position()` after changes.

## Conventions

- **All UI is built in code.** No UI nodes in `.tscn` files — create every `Label`/`Button`/`ColorRect`/`StyleBoxFlat` programmatically in `_build_ui()`/`_ready()`. Inline `StyleBoxFlat` applied via `add_theme_stylebox_override`; see `_circle_style()` (level_select) and `_btn_style()` (title).
- Naming: `_build_*` constructs UI, `_refresh_*` updates existing UI, `_update_ui()` is battle's per-phase refresh (calls `queue_redraw()`), `_try_*` validates player input before acting, `_on_*` are signal callbacks.
- Grid↔world: `world = grid_pos * TILE_SIZE + Vector2(TILE_SIZE/2, TILE_SIZE/2)` (centred); `cell = Vector2i(int((screen - GRID_OFFSET).x / TILE_SIZE), ...)`.
