# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> A complementary `.github/copilot-instructions.md` exists with overlapping guidance. Keep the two in sync when changing conventions.

## Project

Godot 4.4 auto-battler strategy roguelite in GDScript. Renderer: Forward Plus. Viewport 1280×720, `canvas_items` stretch. Main scene: `src/title/title.tscn`. The only fight mode is the auto-battler (`src/autobattler/`); your roster auto-resolves each encounter.

## Assets

Sprites (`assets/units/`), SFX (`assets/sfx/`) and music (`assets/music/`) are committed. SFX come from `tools/gen_sfx.py`; chiptune music loops from `tools/gen_music.py` (pure-stdlib WAV synthesis, played by the `Music` autoload — `src/music.gd` — which loops a track per scene and rides the Master bus). Unit sprites (32×32, `<class>_<team>.png`, loaded by `autobattler.gd` / `rtbattle/rt_unit.gd`) are sliced from the CC0 **Kenney Tiny Dungeon** tilemap by `tools/import_pixel_units.py` (per-class tile index + enemy crimson blend + grounding shadow in that file's header); `tools/gen_sprites.py` is the older procedural generator, kept as a fallback. After regenerating any of these, run `godot --headless --import`. Boot-test everything with `tools/smoke_test.sh`.

**Raw downloaded asset packs are NOT committed.** Source art (tilemaps) lives in the gitignored `assets/incoming/` staging area — re-download per the sources in `tools/import_pixel_units.py` if absent. Only the processed outputs (`assets/units/*.png`) are kept.

## Commands

The game is normally run and tested through the Godot editor — there is no unit-test or lint suite.

Headless web export (mirrors CI in `.github/workflows/deploy.yml`, Godot 4.4):
```bash
godot --headless --import                                   # import assets first
godot --headless --export-release "Web" build/web/index.html
```
Push to `main` triggers the GitHub Pages build/deploy workflow. The CI adds a COOP/COEP service worker (Godot 4 WASM threading needs these headers, which Pages can't set) and cache-busts asset URLs with `?v=<short-sha>`.

## Architecture

Scene flow: `title.tscn → charselect.tscn → level_select.tscn ⇄ autobattler.tscn`. New Campaign goes to `charselect` (pick a hero), which does `reset()` → `select_hero(id)` → `level_select`. `level_select` is the overworld map; a battle node opens a pre-battle popup (hero **Fight** or **Buff**), sets `pending_autobattle = true`, and switches to `autobattler.tscn`. The auto-battler is *also* a standalone Quick Auto Battle from the title (no campaign/hero state). Campaign contract: build the fight from `player_roster` + `get_battle_enemy_roster`/tier, then on resolution report back to GameManager (survivors via `set_roster`, `register_battle_won`, `battle_gold_reward`, `add_valor`, elite `grant_random_relic`, `save_run`) on a win or `clear_run` on a loss — see `_conclude_campaign` in `autobattler.gd`. `GameManager.battle_mode` is always `"auto"` (vestigial; kept in the save schema).

### Hero (`charselect` + GameManager.HEROES)

A run has one hero (chosen on `charselect`). `GameManager.HEROES` holds the stat blocks (`fight_archetype`/`fight_level`, `buff {id,name,desc,cost}`, `sway_aptitudes`, `start_bonus`); helpers: `select_hero`, `has_hero`, `hero_data`, `add_valor`/`spend_valor`. Per battle the player picks `hero_battle_mode`: **fight** (hero spawns as an extra auto-battler card built from its archetype/level — `_start_campaign_fight` appends it with a `null` roster entry so it's never persisted/permakilled) or **buff** (hero sits out; spend **Valor** to apply `pending_hero_buff` across the team via `_apply_hero_buff` — `aegis`/`march`/`warchest`). Valor is buff-only, earned +2/win (+1 elite).

**Progression:** the hero gains XP per battle win (`hero_gain_xp` in `register_battle_won`), levelling every `HERO_XP_PER_LEVEL` wins up to `HERO_MAX_LEVEL`. Each level passively scales `hero_fight_mult`/`hero_buff_mult`, and flags `pending_hero_perk` so `level_select` offers a permanent perk pick (`HERO_PERKS`: warlord/veteran_hero/inspiring/thrifty/silver_tongue). Perks feed the same helpers (`hero_fight_mult`, `hero_fight_bonus_level`, `hero_buff_mult`, `hero_buff_cost`, and `hero_sway_aptitude` for silver_tongue), read by the autobattler (fight/buff/duel scaling) and the prebattle popup (buff cost). Level/xp/perks persist in the run save.

### Recruiting / sway (`gain_unit` nodes)

A `gain_unit` node offers 2–3 candidates (`GameManager.recruit_candidates(tier,index)`, deterministic — each `{type, sway, scene, personality}`). Each carries a `personality` (`RECRUIT_PERSONALITIES`) for flavour and, for dialogue, a `scene` index into `DIALOGUE_SCENES` (prompt + 3 options + `correct`). Approaching one runs its `sway` resolver (`level_select`): **dialogue** (pick the scene's right response; hero `dialogue` aptitude hints it), **persuasion** (pay `recruit_persuasion_cost(type,tier)` gold, 40% off with `persuasion` aptitude), or **duel** (a 1v1 in the auto-battler — `pending_duel`/`duel_recruit_type`, `_start_duel_fight`/`_conclude_duel` set `duel_outcome`; `level_select._ready` recruits on a win). Roadside encounters reuse `GameManager.encounter_recruit(seed)` (dialogue/persuasion only). `hero_sway_aptitude(type)` gates the discounts/hints; the hero is buffed +25% in a duel with `duel` aptitude. See `docs/superpowers/specs/2026-06-01-sway-recruiting-design.md`.

**Battle clarity:** `GameManager.battle_odds(tier, elite, mode)` returns a heuristic Favorable/Even/Risky/Dire from `army_power_for(mode)` vs `enemy_power(tier,elite)` (rough power estimate, not the combat sim). Shown per option in `level_select`'s prebattle popup (fight vs buff), in the node detail, and in the autobattler campaign header.

### GameManager (autoload singleton) — `src/game_manager.gd`

The **only** place persistent cross-scene state lives. Scene scripts read/write it, then call `get_tree().change_scene_to_file(...)`. Never store run-state in individual scene scripts.

- `UNIT_TYPES` — canonical stat blocks. Always use exact lowercase keys: `"soldier"`, `"archer"`, `"scout"`.
- `player_roster`, `map_data` (2D `[tier][index]` array of node dicts), `current_tier`, `last_chosen_index`.
- `pending_battle_tier` / `pending_battle_elite` — set by `level_select` right before switching to `autobattler.tscn`.
- `reset()` runs at start of each new game and regenerates the map.

### Map (`level_select`) — walkable overworld

The same tier/node/connection graph (below) is presented as **one continuous horizontal world**: the hero avatar walks left→right (`x = MARGIN_X + tier*TIER_DX`, `y` = lane within the tier), steering into forks with ↑↓ and holding →/D to travel an edge. A camera (`_cam_x`) follows the avatar. A small `Nav` state machine (`AT_NODE`/`TRAVELING`) lives in `level_select`: `_anchor_to_current` sets the avatar on the current node + computes `_targets` from `get_reachable_indices`; `_begin_travel`→`_update_travel`→`_arrive` walks an edge (collecting seeded gold/Valor pickups, ~25% roadside encounter = `random_event` or a dialogue/persuasion recruit); arrival calls `_trigger_node` (the old `_on_node_pressed` body) which fires the node handler. Scene-changing nodes (battle/duel) set `_leaving`; popup nodes set `_awaiting_resolve` (re-anchored in `_process` when the popup closes). All rendering is in `_draw` (placeholder shapes + the hero sprite), including a bottom-left **minimap** (`_draw_minimap`) — the whole graph scaled down with visited/current/reachable/selected markers + a camera-viewport box, restoring route planning the side-scroll camera loses. See `docs/superpowers/specs/2026-06-01-walkable-overworld-design.md`.

Graph data: 12–15 tiers (randomized per run, `MAP_TIERS_RANGE`). Tier 0 = single start node (always a regular `battle`); middle tiers = 2–5 nodes; final tier = single boss (`elite_battle`). Connections wired per adjacent tier pair (proportional mapping + occasional branch); every target guaranteed an incoming edge. Reachable nodes come from the last visited node's `connections`; before any node is visited every tier-0 node is selectable. Node types: `battle`, `elite_battle`, `gain_unit`, `shop`, `heal`.

### Auto-battler (`src/autobattler/`)

`autobattler.gd` builds both armies from rosters and auto-resolves the fight with no player input during combat — strength comes from the army built across the run. It uses `rtbattle/rt_unit.gd` (the only surviving file in `src/rtbattle/`) for per-unit combat behaviour and loads `assets/units/*.png` for sprites. Enemy scaling: HP mult = `1.0 + tier*0.2 + (0.25 if elite)`; roster seeded from tier+elite (deterministic). Win/loss reporting goes through `_conclude_campaign`.

## Conventions

- **All UI is built in code.** No UI nodes in `.tscn` files — create every `Label`/`Button`/`ColorRect`/`StyleBoxFlat` programmatically in `_build_ui()`/`_ready()`. Inline `StyleBoxFlat` applied via `add_theme_stylebox_override`; see `_circle_style()` (level_select) and `_btn_style()` (title).
- Naming: `_build_*` constructs UI, `_refresh_*` updates existing UI, `_try_*` validates player input before acting, `_on_*` are signal callbacks.
