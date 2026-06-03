# Restore all-units-at-once combat

**Date:** 2026-06-03
**Status:** Design approved, ready for implementation plan
**Files touched:** `src/autobattler/autobattler.gd`, `CLAUDE.md` (+ `.github/copilot-instructions.md`, `AGENTS.md`, `GEMINI.md`), new `tests/test_*.gd`

## Problem

The live FIGHT phase runs a **front-vs-front gauntlet** (Branch B): every unit spawns
`holding = true`, and each AI tick `_auto_target` un-holds only each team's
frontmost-alive unit via `_front_engage`. Combat resolves as a string of isolated
1v1 duels, stepping up by array order as fronts die. Damage is flat
(`flat_damage = true`). To compensate for the slow single-file pace the sim runs at
`_speed_scale = 2.0` by default.

This replaced the **original all-at-once field melee** (Branch A), where
`_auto_target` called `_assign_targets` for both teams so every unit picked a target
and fought simultaneously, with alive-ratio damage scaling. The field-melee model was
branched as `combat/a-field-melee` (tip `9eaef6f`); front-vs-front was adopted in
merge `12acfdc`; commit `9c83bcc` then layered the deploy-wedge + PREP ordering +
hero-appended-last on top.

A collaborator wants the all-at-once melee back: remove the 1v1 gauntlet so all units
fight at once "like it was before."

Note: `CLAUDE.md:75` is **stale** — it already describes the live FIGHT as the
all-at-once field melee with alive-ratio damage. That documents the *replaced* Branch
A, not current code. This spec makes the code match that description again.

## Goals

- All deployed troops (both teams) fight simultaneously, targeting the nearest enemy.
- Alive-ratio damage (a wounded regiment hits softer) — the "Total War" attrition feel.
- The hero is held in reserve, untargetable, and only enters the melee once every
  troop ahead of it has fallen. Hero death still ends the run instantly.
- The villain (non-boss) flees when its side is collapsing.
- Sim speed back to 1× by default (all-at-once resolves fast enough without the 2× crutch).
- PREP front-to-back ordering keeps meaning, repurposed as **spatial placement**.

## Non-goals

- Keeping front-vs-front selectable behind a flag (delete it; no dead modes).
- Merging or rebasing the `combat/a-field-melee` branch (it predates the hero tree,
  pit, boss-villain, and relics — surgical edits to `main` instead).
- Re-tuning unit stat blocks or enemy scaling beyond what the model change forces.

## Approach

Surgical edits to current `main`, restoring the all-at-once engagement while keeping
every post-branch feature. Two files of logic plus docs and a regression test.

### 1. Engagement — all units fight at once

`autobattler.gd`, `_auto_target` / `_front_engage` region (~1739-1768).

- Re-add `_assign_targets(attackers, defenders)`: for each alive, **non-held**
  attacker whose current attack target is dead/missing, `order_attack(_nearest_enemy(unit, defenders))`.
  The live `_nearest_enemy` already skips `_untargetable` and dead units, and routes
  archers through `_backline_enemy` — keep it as-is.
- Rewrite `_auto_target` to call `_assign_targets(player_units, enemy_units)` and
  `_assign_targets(enemy_units, player_units)` instead of the two `_front_engage` calls.
- Delete `_front_engage`. Keep `_frontmost_alive` (used by villain escape and the
  hero-release check).

### 2. Spawn holding

`autobattler.gd`, `_spawn_unit` (~1696).

Replace the blanket `u.holding = true` with role-specific holding:

- Regular troops and regular enemies: `holding = false` — engage immediately.
- Hero (`is_hero`): `holding = true` — reserve.
- Villain, non-boss (`is_villain and not _villain_boss`): `holding = true` and it stays
  held (it lurks, never un-held, and escapes — see §5). Boss villain: `holding = false`,
  a normal combatant.

### 3. Hero held until troops expended

`autobattler.gd`, inside `_auto_target` (after target assignment).

- New helper `_only_hero_left() -> bool`: true when no alive player unit other than
  `_hero_unit` remains.
- When `_only_hero_left()` is true and `_hero_unit` is held, un-hold it so it joins the
  melee. A solo-hero run (zero troops) un-holds on the first tick.

### 4. Hero untargetable while reserved

`autobattler.gd`, `_untargetable` (~242).

The reserve hero is held (won't *act*) but is still a valid *target* — enemy archers'
`_backline_enemy` picks the rearmost player unit, which is the hero. Without this fix
the hero gets sniped in the backline from turn zero and the run is unwinnable.

- Extend `_untargetable(u)` to also return true when `u == _hero_unit and u.holding`.
- Once the hero un-holds (§3) it becomes targetable and fights its climax. The
  hero-death-ends-the-run check (`_check_fight_end`, ~1914) is unchanged.

### 5. Villain escape — either-first

`autobattler.gd`, `_check_villain_escape` (~247).

The old trigger (`_frontmost_alive(enemy_units) == _villain_unit`) has no meaning when
all units fight at once. Replace with: flee if **either**

- (a) no alive **non-villain** enemy remains (villain is the last enemy standing), **or**
- (b) the enemy army's remaining HP fraction drops below `VILLAIN_FLEE_HP_FRAC` (0.25),

whichever fires first. Boss villain never escapes (existing `_villain_boss` guard).

- Capture `_enemy_army_start_hp` = sum of non-villain enemy `max_hp` right after the
  enemy host spawns.
- Each `_check_villain_escape`, compute the live sum of non-villain enemy `hp` and
  compare the fraction.
- Guard `_enemy_army_start_hp <= 0` (villain-only host): skip the (b) fraction test and
  rely on (a), which fires immediately when no non-villain enemy exists.
- New const `VILLAIN_FLEE_HP_FRAC := 0.25`.

### 6. Damage → alive-ratio

`autobattler.gd`, `_spawn_unit` (~1694).

- Set `flat_damage = false` (or drop the line; default is false).
- The ratio path in `rt_unit.gd:460-463` then scales regiment damage by
  `alive_soldier_count / soldier_count`.
- Hero and villain need no special case: `rt_unit.gd:94-97` already forces their
  `soldier_count = 1`, so their ratio is always 1.0 — they keep hitting full.

### 7. Speed → 1×

`autobattler.gd` — `_speed_scale` defaults to `2.0` at the var declaration (~120) and is
re-set to `2.0` on fight entry (~1130) and reset (~2017).

- Make `1.0` the default everywhere those set 2.0 for a normal fight.
- Keep the 1×/2× toggle buttons (`_on_speed_1` / `_on_speed_2`, ~796-802) — the player
  can still speed up.
- Update the "2x by default — 1x standard felt too slow" comment.

### 8. PREP ordering → spatial placement

No structural change. `_player_deploy_positions` (~1263) already seats the front-of-order
troop at the wedge spearhead with flanks receding, and the hero centred well behind. Under
nearest-enemy AI the spearhead troops make contact first (tank), while archers
(range + `_backline_enemy`) hang back. The reorder UI keeps its job; only its *meaning*
shifts from "fight queue order" to "who stands at the front."

- Rewrite the now-wrong comments in `_deploy_lineup` (~1229-1231) and
  `_player_deploy_positions` (~1260-1262) that describe "engages last by array order" /
  "front-vs-front steps up."

### 9. Docs + tests

- Fix `CLAUDE.md` combat section (~75) to describe: all units fight at once via
  `_assign_targets`/nearest-enemy; alive-ratio damage; hero held in reserve and
  untargetable until its troops fall; villain flees on last-enemy-or-low-HP; 1× default
  speed. Mirror into `.github/copilot-instructions.md`, `AGENTS.md`, `GEMINI.md` per the
  keep-all-four-in-sync rule.
- New `tests/test_all_at_once_combat.gd` regression covering:
  - troops spawn un-held and acquire targets at fight start;
  - the hero stays held while any troop is alive and un-holds when it is the last
    player unit;
  - the reserve hero is `_untargetable` while held, targetable once released;
  - villain escape fires on last-enemy-standing and (separately) on enemy HP below the
    flee fraction;
  - a wounded regiment's scaled damage is below its full damage.

## Edge cases & risks

- **Hero exposure** — fully addressed by §3 + §4 (held *and* untargetable until last).
  This is the load-bearing change; without it all-at-once is unwinnable.
- **Villain in the melee** — non-boss villain stays held and `_untargetable`, so
  `_assign_targets` never assigns it a target and enemies of it (the player) never hit
  it. It only lurk-taunts then escapes, matching current flavor.
- **Damage symmetry** — `flat_damage = false` applies to both teams via the shared
  `_spawn_unit`; alive-ratio scaling is symmetric.
- **Field density** — peak ~13 regiments converging center-field on a 1200×410 field is
  a busier scrum than the current 1-pair clash. Acceptable; if readability suffers,
  separation spacing (`rt_unit.gd:444-448`) is the tuning knob — out of scope here.
- **Per-frame juice** — going from ~1 active pair to ~all pairs raises flash/lunge/Sfx
  tween churn. The 1× default (§7) halves the sim-step multiplier, offsetting it. No
  profiling data in-repo; spot-check a peak fight after the change.
- **Dead code** — `_front_engage` removed. Confirm no other callers remain.

## Verification

- `tools/run_tests.sh` — the new regression plus the existing suite pass.
- `tools/smoke_test.sh` — every scene still boots without script/parse errors.
- Manual: play a campaign fight and confirm all troops engage at once, the hero holds
  back then enters last, the villain flees as its army collapses, and 1× feels right.
