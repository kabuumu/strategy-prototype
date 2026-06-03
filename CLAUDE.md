# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. **You may create or edit any file in this codebase** — there is no read-only area; make the changes the task needs.

> Sibling instruction files carry the same guidance for other assistants: `.github/copilot-instructions.md` (Copilot), `AGENTS.md` (the cross-tool standard, e.g. Codex), and `GEMINI.md` (Gemini CLI). **Keep all four in sync** when changing conventions.

## Project

Godot 4.4 auto-battler strategy roguelite in GDScript. Renderer: Forward Plus. Viewport 1280×720, `canvas_items` stretch. Main scene: `src/title/title.tscn`. The only fight mode is the auto-battler (`src/autobattler/`); your roster auto-resolves each encounter.

## Assets

Sprites (`assets/units/`), SFX (`assets/sfx/`) and music (`assets/music/`) are committed. SFX come from `tools/gen_sfx.py`; chiptune music loops from `tools/gen_music.py` (pure-stdlib WAV synthesis, played by the `Music` autoload — `src/music.gd` — which loops a track per scene and rides the Master bus). Unit sprites (32×32, `<class>_<team>.png`, loaded by `autobattler.gd` / `rtbattle/rt_unit.gd`) are sliced from the CC0 **Kenney Tiny Dungeon** tilemap by `tools/import_pixel_units.py` (`CLASS_TILE` per-class tile index + enemy crimson blend + grounding shadow). Heroes get their OWN distinct sprites via `HERO_TILE` (`<hero_id>_player/enemy.png`, gold leader-ring) so a hero never looks like a line troop; each hero's `sprite_key` is its id, and `_build_hero_card`/`_spawn_unit` carry it into combat. The recurring villain has its own `villain_*.png` (`VILLAIN_TILE`, purple ring). `tools/gen_sprites.py` is the older procedural generator, kept as a fallback. After regenerating any of these, run `godot --headless --import`. Boot-test everything with `tools/smoke_test.sh`.

**Raw downloaded asset packs are NOT committed.** Source art (tilemaps) lives in the gitignored `assets/incoming/` staging area — re-download per the sources in `tools/import_pixel_units.py` if absent. Only the processed outputs (`assets/units/*.png`) are kept.

## Commands

The game is normally run and tested through the Godot editor.

**Tests (headless, no addon):**
```bash
tools/smoke_test.sh     # boots every scene a few frames; fails on any script/parse error
tools/run_tests.sh      # runs the GDScript unit suite under tests/
```
The unit suite is a dependency-free harness (matching the pure-stdlib tooling ethos): `tests/framework.gd` (assertions), `tests/run_tests.gd` (a `SceneTree` runner invoked via `godot --headless --script res://tests/run_tests.gd` that discovers `tests/test_*.gd` and runs each `test_*` method), exiting non-zero on failure. Tests instantiate their own `GameManager` copy (`load("res://src/game_manager.gd").new()`) since autoloads aren't loaded under `--script`. **Add a `tests/test_*.gd` regression test when changing game logic.**

Headless web export (mirrors CI in `.github/workflows/deploy.yml`, Godot 4.4):
```bash
godot --headless --import                                   # import assets first
godot --headless --export-release "Web" build/web/index.html
```
Push to `main` triggers the GitHub Pages build/deploy workflow. The CI adds a COOP/COEP service worker (Godot 4 WASM threading needs these headers, which Pages can't set) and cache-busts asset URLs with `?v=<short-sha>`.

## Architecture

Scene flow: `title.tscn → charselect.tscn → level_select.tscn ⇄ autobattler.tscn`. New Campaign goes to `charselect` (pick a hero), which does `reset()` → `select_hero(id)` → `level_select`. `level_select` is the overworld map; a battle node sets `pending_autobattle = true` and switches straight to `autobattler.tscn` (no pre-battle popup — the hero always deploys). The auto-battler is *also* a standalone Quick Auto Battle from the title (no campaign/hero state). Campaign contract: build the fight from `player_roster` + `get_battle_enemy_roster`/tier, then on resolution report back to GameManager (keep the roster via `set_roster`, `add_gold`, `register_battle_won`, elite `grant_random_relic`, `save_run`) on a win or `clear_run` on a loss — see `_conclude_campaign` in `autobattler.gd`. `GameManager.battle_mode` is always `"auto"` (vestigial; kept in the save schema).

### Hero (`charselect` + GameManager.HEROES)

A run has one hero (chosen on `charselect`). Six heroes exist: three starters + three **unlockable** (`HERO_UNLOCK` — gated on meta stats `runs_won`/`best_tier_reached`/`best_streak_ever`; `is_hero_unlocked`/`hero_unlock_hint`; `charselect` greys + locks the rest). `GameManager.HEROES` holds the stat blocks (`fight_archetype`/`fight_level`, `buff {id,name,desc}` — now the Command leader **aura**, `sway_aptitudes`, `start_bonus`); helpers: `select_hero`, `has_hero`, `hero_data`. The hero is a permanent lineup unit: in PREP it **always deploys** (front) alongside the troops you pick — see Auto-battler below — and applies its aura to the team at battle start (`_apply_hero_aura`). (The older `hero_battle_mode` fight/buff split and the Valor economy are gone.)

**Progression:** the hero's only progression is the **permanent skill tree** (Spec A). Each battle win banks tree XP (`hero_award_battle_xp` in `register_battle_won`); XP is spent between/within runs to buy tree levels (`hero_buy_level`, `hero_level_cost`) and place points on `HERO_TREE` nodes (`hero_buy_node`). The tree feeds the live helpers read by combat and sway: `hero_tree_bonus_level` / `hero_hp_mult_tree` / `hero_damage_mult_tree` / `hero_attack_cooldown_mult` (the hero's combat card + `hero_fight_power` odds), `hero_aura_mult_tree` (Command aura), `hero_tree_sway_bonus` (folded into `hero_sway_aptitude`), and the deck-cap helpers. (The old per-run level/perk system — `hero_gain_xp`/`HERO_PERKS`/fight-buff mults — has been removed.)

### Recruiting / sway (`gain_unit` nodes)

A `gain_unit` node offers 2–3 candidates (`GameManager.recruit_candidates(tier,index)`, deterministic — each `{type, sway, scene, personality}`). Each carries a `personality` (`RECRUIT_PERSONALITIES`) for flavour and, for dialogue, a `scene` index into `DIALOGUE_SCENES` (prompt + 3 options + `correct`). Approaching one runs its `sway` resolver (`level_select`): **dialogue** (pick the scene's right response; hero `dialogue` aptitude hints it), **persuasion** (pay `recruit_persuasion_cost(type,tier)` gold, 40% off with `persuasion` aptitude), or **duel** (a 1v1 in the auto-battler — `pending_duel`/`duel_recruit_type`, `_start_duel_fight`/`_conclude_duel` set `duel_outcome`; `level_select._ready` recruits on a win). Roadside encounters reuse `GameManager.encounter_recruit(seed)` (dialogue/persuasion only). `hero_sway_aptitude(type)` gates the discounts/hints; the hero is buffed +25% in a duel with `duel` aptitude. See `docs/superpowers/specs/2026-06-01-sway-recruiting-design.md`.

**Battle clarity:** `GameManager.battle_odds(tier, elite, mode)` returns a heuristic Favorable/Even/Risky/Dire from `army_power_for` vs `enemy_power(tier,elite)` (rough power estimate, not the combat sim; the `mode` arg is vestigial). Shown in the node detail and the autobattler campaign header.

**Elite modifiers:** every `elite_battle` (and the boss) rolls a deterministic `GameManager.elite_modifier(tier)` (`ELITE_MODIFIERS`: frenzied/armored/swift/vengeful) buffing the enemy host. Applied to enemy units in `autobattler._start_campaign_fight`, factored into `enemy_power`, and shown in the node detail / prebattle popup / autobattler header.

### GameManager (autoload singleton) — `src/game_manager.gd`

The **only** place persistent cross-scene state lives. Scene scripts read/write it, then call `get_tree().change_scene_to_file(...)`. Never store run-state in individual scene scripts.

- `UNIT_TYPES` — canonical stat blocks. Always use exact lowercase keys: `"soldier"`, `"archer"`, `"scout"`.
- `player_roster`, `map_data` (2D `[tier][index]` array of node dicts), `current_tier`, `last_chosen_index`.
- `pending_battle_tier` / `pending_battle_elite` — set by `level_select` right before switching to `autobattler.tscn`.
- `reset()` runs at start of each new game and regenerates the map.

### Map (`level_select`) — walkable overworld

The same tier/node/connection graph (below) is presented as **one continuous horizontal world**: the hero avatar walks left→right (`x = MARGIN_X + tier*TIER_DX`, `y` = lane within the tier), steering into forks with ↑↓ and holding →/D to travel an edge. A camera (`_cam_x`) follows the avatar. A small `Nav` state machine (`AT_NODE`/`TRAVELING`) lives in `level_select`: `_anchor_to_current` sets the avatar on the current node + computes `_targets` from `get_reachable_indices`; `_begin_travel`→`_update_travel`→`_arrive` walks an edge (collecting seeded gold/Valor pickups, ~25% roadside encounter = `random_event` or a dialogue/persuasion recruit); arrival calls `_trigger_node` (the old `_on_node_pressed` body) which fires the node handler. Scene-changing nodes (battle/duel) set `_leaving`; popup nodes set `_awaiting_resolve` (re-anchored in `_process` when the popup closes). All rendering is in `_draw` (placeholder shapes + the hero sprite), including a bottom-left **minimap** (`_draw_minimap`) — the whole graph scaled down with visited/current/reachable/selected markers + a camera-viewport box, restoring route planning the side-scroll camera loses. See `docs/superpowers/specs/2026-06-01-walkable-overworld-design.md`.

Graph data: 12–15 tiers (randomized per run, `MAP_TIERS_RANGE`). Tier 0 = 2–3 **recruit** (`gain_unit`) start nodes — every tier-0 node is a recruit so a run never opens going into battle alone (`_starting_node_types`); middle tiers = 2–5 nodes; final tier = single boss (`elite_battle`). Connections wired per adjacent tier pair (proportional mapping + occasional branch); every target guaranteed an incoming edge. Reachable nodes come from the last visited node's `connections`; before any node is visited every tier-0 node is selectable. Node types: `battle`, `elite_battle`, `gain_unit`, `shop`, `heal`.

### Auto-battler (`src/autobattler/`)

`autobattler.gd` builds both armies from rosters and auto-resolves the fight with no player input during combat — strength comes from the army built across the run. It uses `rtbattle/rt_unit.gd` (the only surviving file in `src/rtbattle/`) for per-unit combat behaviour and loads `assets/units/*.png` for sprites. Enemy scaling: HP mult = `1.0 + tier*0.2 + (0.25 if elite)`; roster seeded from tier+elite (deterministic). Win/loss reporting goes through `_conclude_campaign`.

**How combat actually works (audited 2026-06-02):**
- **Phase machine** `enum Phase { SHOP, FIGHT, RESULT, REWARD, GAME_OVER }`. **Quick Auto Battle** (standalone from the title) runs the full **Super-Auto-Pets-style** loop: SHOP → FIGHT → RESULT → REWARD → SHOP, ending at GAME_OVER (`wins >= MAX_WINS` / `hearts <= 0`). **Campaign** battles set `_campaign` and **skip SHOP**, jumping straight to FIGHT; **duels** likewise (`_start_duel_fight`).
- **SHOP team-building** (quick-battle only): buy (`BUY_COST` gold) into a `TEAM_SIZE = 5` hotbar, **merge** a duplicate to level up (`MAX_LEVEL = 3`), **reorder** (slot 0 deploys at the front), **sell**, **freeze** the shop, **roll** (`ROLL_COST`). Gold is `GOLD_PER_ROUND`. None of this gold economy runs in campaign — the campaign uses `player_roster` as-is, in roster order.
- **FIGHT is a real-time field melee, NOT a turn-based front-vs-front queue.** All units spawn on `FIELD_RECT`, move toward AI-assigned targets (`_auto_target` on `AI_RETARGET_PERIOD`), and attack on `attack_cooldown` when in range. A unit is a **Total-War-style regiment**: `max_hp = soldier_count * hp_per_soldier`, and **damage scales by the alive-soldier ratio** (`damage_per_attack * alive/total`); sprites cull as HP drops. The hero (`is_hero`) is a single sprite holding the whole regiment's HP.
- **Hero injection:** the hero is NOT a selectable lineup slot — `_deploy_lineup` always spawns it at the **back** (`_build_hero_card`) *in addition* to the chosen troops, so picking N troops fields N+1 units. PREP lets the player **order** the troops (front-to-back, `_on_prep_reorder`); the hero is the general behind a forward defensive wedge (`_player_deploy_positions`) and so fights last. It carries a `null` roster entry (never persisted) and applies its leader aura via `_apply_hero_aura`.
- **Hero death ends the run:** `_check_fight_end` forces a campaign loss the instant the tracked `_hero_unit` dies even if troops survive (enemy archers reach the backline). A duel is 1v1, so losing one (`_conclude_duel(false)`) is also a hero death → `clear_run()`.
- **The villain (`GameManager.VILLAIN`, "Vex"):** a recurring enemy that joins *every* campaign battle at the back of the enemy line (`_villain_unit`). In normal battles it's untargetable (`_untargetable`) and **teleports away with a taunt** the moment it becomes the frontmost enemy (`_check_villain_escape` → `_villain_do_escape` → `RTUnit.escape()`); periodic lurk-taunts via `_villain_lurk_taunt`. On the **final tier** (`_villain_boss`) it doesn't escape — it's the real boss with a 4× HP pool.
- **No troop permadeath (won battles):** `_conclude_campaign` keeps every pool entry (deployed alive/fallen + benched) and `set_roster`s them — winning never costs a troop (you recruit one at a time, so attrition made runs impossible). A battle **loss** still ends the run (`clear_run()`); the **pit** (roster cap) is the only thing that retires a unit.
- **Roster cap + pit (`GameManager.ROSTER_CAP = 8`):** when the roster is full and you'd recruit another (`_gain_recruit` in level_select; shop buy is blocked instead), a **Trial by Combat** picker (`_show_pit_picker`) makes the recruit duel one chosen unit 1v1 in the arena (`pending_pit` → autobattler `_start_pit_fight`/`_conclude_pit`, mirrors the duel). On return `GameManager.resolve_pit` gives the survivor the slot, **+1 level and the loser's ✦ upgrades**; the loser is gone, so the roster stays at the cap. "Turn them away" declines.

### Planned redesign (design-stage, not yet built)

`docs/superpowers/specs/2026-06-02-*.md` hold five brainstormed specs for a large overhaul: **D** SAP-style campaign combat (promote the existing shop/lineup loop into the campaign; single-pet HP/Attack units, prep phase), **A** a permanent per-hero CK3-style XP skill tree (deletes fight/buff + Valor; hero = a permanent lineup unit; Command = leader auras), **B** a run-local Card deck, **C** point-and-click overworld, **E** touch/mobile input. **These describe intended future state — the code above is current reality.** Reconcile against the code before implementing (much of "SAP combat" already exists).

## Conventions

- **All UI is built in code.** No UI nodes in `.tscn` files — create every `Label`/`Button`/`ColorRect`/`StyleBoxFlat` programmatically in `_build_ui()`/`_ready()`. Inline `StyleBoxFlat` applied via `add_theme_stylebox_override`; see `_circle_style()` (level_select) and `_btn_style()` (title).
- Naming: `_build_*` constructs UI, `_refresh_*` updates existing UI, `_try_*` validates player input before acting, `_on_*` are signal callbacks.
