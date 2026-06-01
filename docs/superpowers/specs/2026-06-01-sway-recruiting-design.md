# Sway Recruiting — Design (Phase 2 of 3)

Date: 2026-06-01
Status: approved, implementing

## Context

Phase 2 of the hero-led campaign (see
`2026-06-01-hero-foundation-design.md`). `gain_unit` map nodes become a
"meet & sway" recruitment scene: the player faces 2–3 candidate recruits, each
with its own **sway type**, and must win them over. The hero's `sway_aptitudes`
(already stored in `GameManager.HEROES`) make the matching sway type easier.

Approved decisions:
- **Duel** sway resolves as a real 1v1 auto-battle (scene change).
- A recruit node offers a **choice of 2–3 candidates**; approaching one commits
  the node.
- Hero aptitude makes the matching type **cheaper / better odds** (not a
  guaranteed success).

## Candidate model

`GameManager.recruit_candidates(tier, index) -> Array[Dictionary]`, deterministic
(seeded by `tier * 100 + index`). 2–3 entries, distinct unit types drawn from
`recruitable_types()`. Each:

```gdscript
{ "type": String,            # recruitable unit type
  "sway": "dialogue"|"persuasion"|"duel",
  "correct": int }           # dialogue only: index 0..2 of the right response
```

`sway` and `correct` are seeded so they're stable across popup rebuilds.

## Resolvers

Approaching a candidate runs its resolver. Win → `add_unit(type)` + toast; fail →
"declines" toast. The node is consumed either way (matches every other node:
`visit_node` already advanced the tier on entry).

### Dialogue (in-popup)
Replace the popup body with a short prompt + 3 response buttons (flavor labels
from a small pool in `level_select`). Exactly one (`candidate.correct`) succeeds.
If `hero_sway_aptitude("dialogue") > 0`, mark the correct option (★ / highlight)
— a strong hint, not auto-resolve. Pick correct → join, else → decline.

### Persuasion (in-popup)
Gold cost = `recruit_persuasion_cost(type, tier)`. If
`hero_sway_aptitude("persuasion") > 0`, apply a 40% discount (round). Show
"Pay N gold (you have G)"; if affordable, Pay → `spend_gold(cost)` + join; else
the Pay button is disabled and only "Walk away" (decline) remains.

`recruit_persuasion_cost(type, tier)`:
```gdscript
var u := UNIT_TYPES[type]
var power := int(u["max_hp"]) + int(u["damage"]) * 2
return int(round(power * 0.18)) + tier * 4    # ~23–40 +tier*4, below SHOP_UNIT_COST(60)
```

### Duel (scene change → autobattler)
Approaching a duel candidate:
`pending_duel = true; duel_recruit_type = type; duel_outcome = -1` then change
scene to `autobattler.tscn`. The autobattler runs a 1v1: the hero (team 0) vs the
recruit unit (team 1). If `hero_sway_aptitude("duel") > 0`, buff the hero +25%
HP/damage. On resolution set `duel_outcome` (1 win / 0 loss) and show a result
with **Continue** → back to `level_select`. `level_select._ready` consumes a
pending `duel_outcome`: win → `add_unit(duel_recruit_type)` + toast, loss →
decline toast; then reset the duel handshake.

If the run has no hero (defensive — campaigns always do), the hero spawns from a
default archetype (`soldier`) so the duel still resolves.

## GameManager additions

State (cleared in `reset()`, NOT persisted — duels resolve within one map visit):
```gdscript
var pending_duel: bool = false
var duel_recruit_type: String = ""
var duel_outcome: int = -1          # -1 none, 0 loss, 1 win
```
Functions:
- `recruit_candidates(tier, index) -> Array[Dictionary]`
- `recruit_persuasion_cost(type, tier) -> int`
- `hero_sway_aptitude(sway_type: String) -> int` — `hero_data().sway_aptitudes`
  lookup, 0 when no hero.

## Autobattler additions (`autobattler.gd`)

- `_ready()`: check `GameManager.pending_duel` BEFORE `pending_autobattle`; if set
  → consume the flag, `_campaign` stays false, call `_start_duel_fight()`.
- `_start_duel_fight()`: spawn one hero card (team 0, from `hero_data` or default
  `soldier`, buffed if duel aptitude) and one recruit card (team 1, the
  `duel_recruit_type` mapped via `CAMPAIGN_CARD_MAP`). Phase = FIGHT.
- `_check_fight_end()`: when `pending`/`_duel` is active, route to
  `_conclude_duel(p_alive and not e_alive)` instead of the shop/campaign paths.
  (Add a `_duel: bool` member set in `_start_duel_fight`.)
- `_conclude_duel(win)`: `GameManager.duel_outcome = 1 if win else 0`; set
  `_result_text`; phase RESULT; the RESULT UI shows a duel message + a
  **Continue** button → `level_select.tscn`. No roster/gold/valor changes.

## level_select additions

- Replace `_show_unit_select_popup` / `_on_unit_chosen` with the candidate +
  resolver flow (`_show_recruit_popup`, `_approach_candidate`, the three
  resolvers, `_recruit_succeed` / `_recruit_decline`).
- `_ready()`: near the top, before the save block, if `GameManager.duel_outcome
  != -1` apply it (add unit on win, toast either way) and reset the handshake.

## Out of scope (Phase 3)
Walkable overworld, side-scroll path segments, pickups, path random encounters
(some of which will reuse these sway resolvers).

## Testing
- `tools/smoke_test.sh` boots clean.
- Headless harness: drive each resolver — dialogue (correct + wrong), persuasion
  (afford + can't), duel (both outcomes) — asserting the roster grows only on
  success and the duel handshake round-trips.

## Files
- Changed: `src/game_manager.gd`, `src/level_select/level_select.gd`,
  `src/autobattler/autobattler.gd`, `CLAUDE.md`,
  `.github/copilot-instructions.md`.
- New: this spec.
