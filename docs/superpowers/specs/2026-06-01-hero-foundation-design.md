# Hero Foundation — Design (Phase 1 of 3)

Date: 2026-06-01
Status: approved, implementing

## Context

The game is now an auto-battler-only strategy roguelite (`src/autobattler/`). We
are adding a player **hero**: chosen at the start of a run, walks the overworld,
and participates in each battle. This is **Phase 1** of a three-phase vision:

1. **Hero foundation** (this doc) — hero data, character-select screen,
   GameManager hero state + Valor, per-battle Fight/Buff toggle.
2. **Recruitment rework** — `sway_type` on recruits, dialogue/persuasion/duel
   resolvers, hero aptitudes feed in.
3. **Walkable overworld** — avatar movement, side-scroll path segments, pickups
   + random encounters, no-backtrack.

Build order 1 → 2 → 3 (hero is the dependency for the other two).

## Phase 1 scope

### Flow

`Title → New Campaign → Character Select → Overworld (level_select)`.
Character Select picks a hero, stores it, calls `GameManager.reset()`, then goes
to `level_select`. Standalone "Quick Auto Battle" stays hero-less (unchanged).

### Hero data model (GameManager)

New `HEROES: Dictionary` keyed by hero id. Each entry:

- `name: String`
- `blurb: String` — one-line flavor for the select screen
- `sprite_key: String` — an existing `assets/units/<key>_player.png` key used as
  placeholder art (real hero pixel art is a later task)
- `fight_archetype: String` — one of the autobattler archetypes
  (`soldier`/`archer`/`scout`/`healer`) the hero spawns as in Fight mode
- `fight_level: int` — card level when fighting (1–3), governs the stat bump
- `buff: {id, name, desc, ...}` — the team buff applied in Buff mode
- `sway_aptitudes: {dialogue:int, persuasion:int, duel:int}` — stored now,
  **consumed in Phase 2**
- `start_bonus: {gold:int, units:Array[String]}` — applied on run start

Launch set (3):

| id | name | fight | buff | aces sway | start bonus |
|----|------|-------|------|-----------|-------------|
| `knight_captain` | Knight-Captain | soldier L3 (tanky) | `aegis`: team +15% max HP | duel | — |
| `bard` | Bard | scout L1 (weak) | `march`: team +15% damage | dialogue | +1 recruit (scout) |
| `merchant_prince` | Merchant-Prince | healer L2 (mid) | `warchest`: heal team 25% | persuasion | +6 gold |

### GameManager state (new)

```gdscript
var selected_hero: String = ""          # "" = no hero (standalone)
var valor: int = 0
var hero_battle_mode: String = "fight"   # "fight" | "buff"
var pending_hero_buff: String = ""       # buff id when mode == "buff"
```

New helpers:
- `select_hero(id)` — sets `selected_hero`, applies `start_bonus` (call AFTER the
  roster is reset).
- `add_valor(n)` / `spend_valor(n) -> bool`.
- `hero_data() -> Dictionary` — `HEROES.get(selected_hero, {})`.
- `has_hero() -> bool`.

Persistence: add `selected_hero`, `valor` to `save_run`/`load_run`. Bump
`SAVE_VERSION` to 3 (old saves discarded — acceptable). `reset()` clears
`selected_hero`/`valor`/`hero_battle_mode`/`pending_hero_buff`; the title's
`_start_new_game` no longer sets hero (Character Select does, after reset).

Valor economy: start 0; **+2 per battle win, +1 extra on elite**, awarded in
`autobattler._conclude_campaign` on a win via `GameManager.add_valor`. Buffs cost
Valor (see buff table; ~3–5). Path pickups arrive in Phase 3.

### Character Select scene (`src/charselect/charselect.gd` + `.tscn`)

Code-built UI per project convention (no UI nodes in `.tscn`). 3 hero cards
(portrait via `assets/units/<sprite_key>_player.png`, name, blurb, fight/buff/
sway summary) + Confirm. On confirm: `GameManager.reset()` →
`GameManager.battle_mode = "auto"` → `GameManager.select_hero(id)` →
change scene to `level_select.tscn`.

`title.gd`: New Campaign button now routes to `charselect.tscn` instead of
calling `_start_new_game("auto")` directly. (Quick Auto Battle unchanged.)

### Pre-battle toggle (`level_select.gd`)

When a `battle`/`elite_battle` node is entered, if `GameManager.has_hero()` show
a popup before launching the fight:
- **Fight** — `hero_battle_mode = "fight"`, launch.
- **Buff** — show the hero's buff + its Valor cost; if affordable, on confirm
  `hero_battle_mode = "buff"`, `pending_hero_buff = <buff id>`,
  `GameManager.spend_valor(cost)`, launch. Disabled if Valor too low.

HUD: add a hero name + Valor readout to the level_select HUD (next to gold).

If `not has_hero()` (shouldn't happen in campaign, but defensive), skip the popup
and launch directly with `hero_battle_mode = "fight"` and no hero spawn.

### Autobattler hooks (`autobattler.gd`)

In `_start_campaign_fight()`, after building `p_cards`/`p_entries` and BEFORE
spawning:
- If `GameManager.has_hero()` and `hero_battle_mode == "fight"`: append a hero
  card built from hero data (`id = fight_archetype`, `level = fight_level`, plus a
  `hero = true` marker) to `p_cards`, and a sentinel entry to `p_entries` so the
  zip stays aligned. The hero's `_unit_state` carries `hero = true` so survivor
  write-back can **skip** it (hero is never added to / removed from the roster).

After spawning player units:
- If `hero_battle_mode == "buff"`: apply the chosen buff across `player_units`
  (`aegis` → `max_hp *= 1.15; hp = max_hp`; `march` → `damage_per_attack *= 1.15`;
  `warchest` → `hp = min(max_hp, hp + 0.25*max_hp)`).

Hero death rule: in Fight mode the hero unit may fall during the fight (affects
that fight only). It is **never** persisted as a roster unit, so it is always
available next battle. Win/loss is unchanged (still "all player units down =
loss"); the hero counts as a player unit for that check.

In `_conclude_campaign(win)` on a win: `GameManager.add_valor(2 + (1 if elite))`.

### Sprites

Phase 1 uses existing unit sprites as hero placeholders (`sprite_key` →
`assets/units/<key>_player.png`). No new art. Real hero pixel art is tracked as a
follow-up, not part of this phase.

## Out of scope (later phases)
- Walkable overworld / side-scroll segments / pickups (Phase 3).
- Sway mechanics — `sway_aptitudes` is stored but unused until Phase 2.
- New hero-specific sprite art.

## Testing
- `tools/smoke_test.sh` boots clean (title, level_select, autobattler, plus
  charselect added to the scene list).
- Manual: New Campaign → pick each hero → first battle → Fight and Buff paths
  both resolve and return to the map; Valor increments on win; save/resume keeps
  hero + Valor.

## Files
- New: `src/charselect/charselect.gd`, `src/charselect/charselect.tscn`,
  `docs/superpowers/specs/2026-06-01-hero-foundation-design.md`.
- Changed: `src/game_manager.gd`, `src/title/title.gd`,
  `src/level_select/level_select.gd`, `src/autobattler/autobattler.gd`,
  `tools/smoke_test.sh`, `CLAUDE.md` (+ `.github/copilot-instructions.md`).
