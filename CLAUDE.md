# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> A complementary `.github/copilot-instructions.md` exists with overlapping guidance. Keep the two in sync when changing conventions.

## Project

Godot 4.4 turn-based strategy game in GDScript. Renderer: Forward Plus. Viewport 1280×720, `canvas_items` stretch. Main scene: `src/title/title.tscn`.

## Commands

The game is normally run and tested through the Godot editor — there is no unit-test or lint suite.

Headless web export (mirrors CI in `.github/workflows/deploy.yml`, Godot 4.4):
```bash
godot --headless --import                                   # import assets first
godot --headless --export-release "Web" build/web/index.html
```
Push to `main` triggers the GitHub Pages build/deploy workflow. The CI adds a COOP/COEP service worker (Godot 4 WASM threading needs these headers, which Pages can't set) and cache-busts asset URLs with `?v=<short-sha>`.

## Architecture

Scene flow: `title.tscn → level_select.tscn ⇄ battle.tscn`. Title resets state and starts a run; `level_select` is the overworld map; `battle` is one tactical fight that returns to `level_select` when it ends.

### GameManager (autoload singleton) — `src/game_manager.gd`

The **only** place persistent cross-scene state lives. Scene scripts read/write it, then call `get_tree().change_scene_to_file(...)`. Never store run-state in individual scene scripts.

- `UNIT_TYPES` — canonical stat blocks. Always use exact lowercase keys: `"soldier"`, `"archer"`, `"scout"`.
- `player_roster`, `map_data` (2D `[tier][index]` array of node dicts), `current_tier`, `last_chosen_index`.
- `pending_battle_tier` / `pending_battle_elite` — set by `level_select` right before switching to `battle.tscn`.
- `reset()` runs at start of each new game and regenerates the map.

### Map (`level_select`)

5 tiers. Tier 0 = single start node; middle tiers = 2–5 nodes; final tier = single boss (`elite_battle`). Connections wired per adjacent tier pair (proportional mapping + occasional branch); every target guaranteed an incoming edge. Reachable nodes come from the last visited node's `connections`. Node types: `battle`, `elite_battle`, `gain_unit`, `heal`.

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
