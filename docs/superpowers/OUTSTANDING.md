# Outstanding work — hero evolution / SAP / deck / overworld

## ⟶ NEXT SESSION: brainstorm first

- **Recruitment mechanics need rework.** Current: `gain_unit` nodes offer 2–3
  candidates resolved by a sway minigame (dialogue / persuasion / duel). It
  feels thin and needs a richer design — brainstorm (superpowers:brainstorming)
  at the **start of the next session** before touching code. Consider: how the
  pool of available allies is presented/chosen, how recruiting ties into the new
  lineup/bench idea (#10 below), pacing of when allies appear, and cost/risk
  tradeoffs. Tie it to the user's note: "we need to recruit units at the first
  few node levels … a pool of available allies to choose from and add to my
  hotbar."

## Playtest feedback — queued (not yet done)

- **#10 PREP redesign (big, gameplay):** don't auto-deploy the whole roster —
  give a **pool of allies** to pick a **lineup/hotbar** from (cap ~5, hero
  included), and change card play to **draw 3, play 1** (onto the field or a
  troop). Restructure `autobattler.gd::_start_campaign_fight` + the PREP phase.
  Overlaps the unimplemented SAP lineup/bench (gap #2 below) and the recruitment
  rework above.
- **Text wrapping on charselect** — reported; may already be resolved by removing
  the old in-card tree overlay. Verify visually next session.

### Playtest feedback — DONE this session
click-travel auto-walk · removed prebattle popup · skill tree = in-game CK3
screen (T) with level collapsed into points · deck view/prune screen (C) ·
choose-hero from main menu + background preview · 2–3 starting nodes (fight +
recruit) · balanced node generation (no shop/rest clustering) · map node icons.


Status snapshot for the work landed from the five `2026-06-02-*` specs. The core
of every spec is implemented and playable (front-vs-front combat + sprite army,
permanent per-hero CK3 skill tree with the full earn→spend→fight loop, Card deck
with prep/traps/reward draft, point-and-click + touch overworld; fight/buff +
Valor fully removed). This file tracks what is **not yet done**.

## Significant gaps (real features, not just polish)

1. **Per-hero capstone effects are inert.** The capstone/signature nodes
   (`might_cap`, `guile_cap`, `tactics_cap`, `command_sig`) are **buyable** in
   the tree and gated correctly, but their special mechanics are **not wired**:
   - ▣ Might/Guile/Tactics capstones (Bastion = −dmg taken, Last Stand = revive,
     Banner of War = adjacency aura, Living Legend = free recruit, Hold the Line
     = free trap, Encore = replay, Black Market = +2 cards, etc. — Spec A §4)
     currently do nothing when owned.
   - ◆ Command **signature** (upgrade the hero's own leader aura, e.g. Aegis
     +15%→+25%) is not applied in `_apply_hero_aura`.
   - Tactics-capstone deck effects are not read by the deck.
   These need per-capstone implementation in `rt_unit`/`autobattler`/deck. This
   is the biggest remaining piece of Spec A.

2. **SAP lineup cap + bench (Spec D) not implemented.** Campaign fights the
   **whole roster** in roster order; there is no 5-slot lineup selection, no
   bench, and the **hero is always fielded** (no benchable hero, so the
   `hero_aura_benched_factor` / Steadfast 50%-aura path is unused). Lineup
   ordering UI for campaign (reuse the shop reorder pattern) is also not built.

3. **Trap effect verbs are partial.** `stun` (Snare) and `revive` (Reinforce)
   are phase-2 stubs; only damage/heal/team-buff trap effects resolve.

## Deferred polish (low value / high cost — deliberately skipped)

4. **Pinch-zoom / native multi-touch overworld** — needs an overworld render-layer
   rewrite (`_w2s` + every `_draw` size). The minimap already gives overview and
   tap + one-finger drag-pan already work on touch via `emulate_mouse_from_touch`.
5. **Multi-hop overworld pathing** — every node interrupts (battle/shop/event), so
   a far click collapses to single-hop in practice (the spec noted this).
6. **Dedicated interactive AFTERMATH phase** — Aftermath cards already auto-resolve
   on survivors; a separate chooser phase is marginal.
7. **Single-target Spell/Trap** — Spell hits the front enemy, traps target by kind;
   no manual target picking (Equip is single-target).

## Balance / tuning (all placeholder, centralised for easy change)

8. XP award curve (`hero_award_battle_xp`), level cost (`hero_level_cost`), node
   per-rank increments + aura magnitudes, deck dials (hand cap / trap slots /
   prep budget), CARD_POOL contents + rarity weights. None playtested.

## Cleanup

9. Legacy hero progression kept only for the odds heuristic
   (`hero_fight_mult`, `hero_fight_bonus_level`, `hero_fight_power`, `HERO_PERKS`,
   `hero_gain_xp`, the `pending_hero_perk` flow + the dead `_show_hero_perk_popup`
   in `level_select`). Can be removed once `army_power_for`/`hero_fight_power`
   read the tree instead.
10. `tests/test_game_manager.gd::test_hero_levels_up_and_scales` still exercises
    the legacy `hero_gain_xp`/`hero_fight_mult` path (kept as a regression anchor;
    remove with the legacy code).

## Tests

Headless suite (`tools/run_tests.sh`) covers GameManager logic + the deck/effect/
combat-controller layers (39 checks). UI flows (tree screen, PREP/result popups,
overworld click/drag) are smoke-tested for boot only (`tools/smoke_test.sh`) —
not interaction-tested, since the harness can't drive autoload-backed scenes.
