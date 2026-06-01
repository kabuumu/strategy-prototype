# Copilot Instructions

## Project

Godot 4.4 auto-battler strategy roguelite written in GDScript. Engine version: 4.4, renderer: Forward Plus, viewport: 1280×720 (`canvas_items` stretch). The only fight mode is the auto-battler (`src/autobattler/`) — your roster auto-resolves each encounter.

There are no build/test/lint commands — the game is run and tested through the Godot editor. Boot-test scenes headless with `tools/smoke_test.sh`.

## Assets

Sprites (`assets/units/`) and SFX (`assets/sfx/`) are committed. SFX via `tools/gen_sfx.py`. Unit sprites (32×32 `<class>_<team>.png`) are sliced from the CC0 Kenney Tiny Dungeon tilemap by `tools/import_pixel_units.py` (tile map + enemy tint in its header); `tools/gen_sprites.py` is the older procedural fallback. Raw source packs live in the gitignored `assets/incoming/` staging area.

## Architecture

### Scene flow

```
title.tscn  →  charselect.tscn  →  level_select.tscn  ⇄  autobattler.tscn
```

`title` New Campaign → `charselect` (pick a hero; does `reset()` + `select_hero`) → `level_select` (overworld map). A battle node opens a pre-battle popup (hero **Fight** or **Buff**), sets `pending_autobattle = true`, and switches to `autobattler`, which auto-resolves one fight and returns to `level_select`. The auto-battler is also a standalone Quick Auto Battle from the title (no campaign/hero state).

**Hero:** one per run (`GameManager.HEROES`, chosen on `charselect`). Each battle the player toggles `hero_battle_mode`: **fight** (hero spawns as an extra auto-battler card, never persisted) or **buff** (hero sits out; spend **Valor**, a buff-only resource earned on wins, to apply a team buff via `_apply_hero_buff`).

**Recruiting:** `gain_unit` nodes offer 2–3 candidates (`GameManager.recruit_candidates`), each with a `sway` type resolved in `level_select`: **dialogue** (pick the right response; hero `dialogue` aptitude hints it), **persuasion** (pay gold, discounted by `persuasion` aptitude), or **duel** (1v1 in the autobattler via `pending_duel`/`_start_duel_fight`/`duel_outcome`; recruited on a win). `hero_sway_aptitude(type)` gates the help.

### GameManager (autoload singleton)

`src/game_manager.gd` is registered as an autoload named `GameManager`. It is the **only** place persistent cross-scene state lives:

- `player_roster: Array[String]` — list of unit type keys the player currently owns
- `map_data: Array` — 2D array `[tier][index]` of node dictionaries
- `current_tier`, `last_chosen_index` — map navigation cursor
- `pending_battle_tier`, `pending_battle_elite` — set by `level_select` immediately before switching to `autobattler.tscn` so the fight knows which encounter to load
- `UNIT_TYPES: Dictionary` — canonical stat block for all unit types (`soldier`, `archer`, `scout`)

`GameManager.reset()` is called at the start of each new game.

### Auto-battler scene (`src/autobattler/`)

`autobattler.gd` builds both armies from rosters and auto-resolves the fight — no player input during combat. It uses `rtbattle/rt_unit.gd` (the only surviving file in `src/rtbattle/`) for per-unit combat behaviour and loads `assets/units/*.png` for sprites. Enemy scaling: HP multiplier = `1.0 + tier * 0.2 + (0.25 if elite)`; roster seeded from tier+elite so it is deterministic. Win/loss reporting goes through `_conclude_campaign`.

### Level select scene (`src/level_select/`)

Map is 12–15 tiers (randomized per run). Node types: `battle`, `elite_battle`, `gain_unit`, `shop`, `heal`. Reachable nodes come from the last visited node's `connections`; before any node is visited every tier-0 node is selectable.

## Key Conventions

### All UI is built in code — no scene-file UI nodes

Every `Label`, `Button`, `ColorRect`, and `StyleBoxFlat` is created in `_build_ui()` / `_ready()`. Do not add UI nodes to `.tscn` files; add them programmatically instead.

### StyleBoxFlat helper pattern

Scenes create `StyleBoxFlat` inline and apply it with `add_theme_stylebox_override`. The `_circle_style(color, radius)` helper in `level_select.gd` and the `_btn_style(color)` helper in `title.gd` show the canonical pattern.

### State mutation goes through GameManager

Never store run-state in individual scene scripts. All mutable game state belongs on `GameManager`. Scene scripts read from and write to `GameManager`, then call `get_tree().change_scene_to_file(...)` to navigate.

### Naming patterns

- `_build_*()` — constructs UI nodes
- `_refresh_*()` — updates existing UI nodes to reflect current state
- `_try_*()` — player input handlers that validate before acting
- `_on_*` — signal callbacks

### Unit type keys

Always use the exact lowercase string keys from `GameManager.UNIT_TYPES`: `"soldier"`, `"archer"`, `"scout"`. Stats are looked up via `GameManager.UNIT_TYPES[unit_type]`.
