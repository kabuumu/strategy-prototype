# Combat Redesign — Super Auto Pets-style Lineup Battler

**Date:** 2026-06-02
**Status:** Draft for review
**Author:** Richard Melvin (with Claude)
**Foundational** — Specs A (hero tree) and B (card deck) build on this. Spec C (overworld) is independent.

## Goal

Replace the current real-time simultaneous-melee auto-battler with a **Super Auto Pets-style lineup battler**: each side fields an **ordered lineup**; the **front units fight 1v1** until one faints and the next steps up; this repeats until a team is empty. Combat is preceded by a **prep phase** (arrange the lineup + play/set Cards). The **hero is a permanent unit in your lineup**; Troops are throwaway. This removes the half-built **fight/buff** mechanic and the **Valor** economy, and retires the standalone **Quick Auto Battle** mode.

## Pillars (locked decisions)

| Topic | Decision |
|---|---|
| Unit model | A **Troop is a single combatant** with **HP** and **Attack** (derived from today's stats). The ~9-soldier block + alive-ratio damage scaling is **removed**; sprites may still show a squad cosmetically. |
| Combat | **Real-time front-vs-front gauntlet** — fronts advance, trade attacks on their cooldowns; at 0 HP a unit **faints**; the next in line steps up. A team loses when its whole lineup has fainted. |
| Lineup | **Capped lineup** (default **5 slots**) chosen + ordered from the roster in prep; the rest sit on a **bench**. The hero is **benchable** (see Hero row). |
| Prep phase | A first-class **PREP phase** in the autobattler before FIGHT: arrange order, play Equip/Spell, set Traps, preview the enemy. Hosts Spec B's card play. **Aftermath** is a post-FIGHT phase. |
| Hero | A **permanent lineup unit** (HP/Attack from the **Might** tree; **Command** nodes grant **leader auras** at battle start). It is **benchable**: if the hero is in the lineup it fights and its auras apply at **100%**; if **benched**, it does **not** fight and its auras apply at **`hero_aura_benched_factor()`** — **50%** by default, or **100%** if Spec A's *Steadfast* (Thrifty) node is owned (frees a slot for a 5th Troop at the cost of half the support + no hero combat). The hero **never permadies** — fainting only ends its participation in that one battle. |
| Throwaway units | A Troop that **faints permadies** (removed from `player_roster` for the run). **Survivors auto-heal to full** before the next battle, and benched Troops persist untouched — so attrition is *losing units*, never carried-over chip damage. |
| Removed | fight/buff mode + `hero_battle_mode`/`pending_hero_buff`, the **Valor** economy, the **Quick Auto Battle** standalone mode, rt_unit's simultaneous-melee + alive-ratio model. |

## Prerequisites (shared)

- **Troop rename** (with Specs A/B): roster-unit "card" → **Troop** (`_card_stats`→`_troop_stats`). Lands as its own PR first.
- **`run_seed`**: add `run_seed: int` set once in `reset()` (from `randomize()`), persisted in the run save, regenerated on `reset()`/`clear_run()`. Seeds the enemy lineup build and Spec B's deck draws. (Forces a `SAVE_VERSION` bump — coordinated with A/B.)

## 1. Unit (Troop) model

A Troop in combat is `{hp, attack, attack_cooldown, abilities[]}`:
- **HP** = today's `soldier_count * hp_per_soldier` (the existing max-HP figure — kept as a single pool, no per-soldier attrition).
- **Attack** = today's `damage_per_attack`.
- **attack_cooldown** = today's value (drives swing cadence).
- Level/upgrades scale HP/Attack via the existing `_troop_stats` curve.
- **No** alive-ratio scaling, no `soldier_count` combat math. `is_ranged` (range) becomes a positioning/targeting flag only if kept; default melee front-vs-front for v1.
- **abilities**: none innate in v1 — behaviour comes from **Cards** (Spec B) and **hero auras** (Command). Existing **army synergies** still apply as lineup-wide stat bonuses.

## 2. Combat resolution (real-time, reusing rt_unit animation)

- Both lineups are queues; the **front** of each advances to a clash point and trades attacks on their `attack_cooldown` (reuse `rt_unit`'s approach/attack animation; restrict engagement to the two fronts).
- Damage is **flat** (`attacker.attack` per swing); HP depletes; at **0 HP** the unit **faints** (animation + remove from the queue).
- The next Troop in that lineup **steps up**; the surviving opponent keeps its remaining HP.
- Repeat until one lineup is empty → the other **wins**. Simultaneous mutual faint → both removed.
- **Speed**: reuse the existing `_speed_scale` so battles stay fast.

## 3. Lineup & bench

- **Lineup cap** = 5 slots (tunable). The hero may take a slot or be benched (§6); a benched hero frees that slot for a 5th Troop.
- **Bench** = roster Troops not in the lineup; they don't fight and can't faint.
- **Selection/order** is set in PREP, **sticky** across battles (editable each prep). If the non-hero roster is ≤ remaining slots, all fight.
- After a battle: **fainted lineup Troops permadie** (removed from `player_roster`); **surviving lineup Troops auto-heal to full** for the next battle; bench persists untouched. Persist via `set_roster`. The hero is never in `player_roster` (it's meta) — it returns at full regardless.

## 4. PREP phase (hosts Spec B)

A new phase in `autobattler.gd` after `_start_campaign_fight` builds both armies, before FIGHT:
- Show your roster (lineup slots + bench) and the **enemy lineup preview**.
- **Arrange**: assign up to 5 Troops (incl. hero) to ordered slots; bench the rest.
- **Cards** (Spec B): play Equip on a slotted Troop, cast a Spell, set Traps. Respect deck caps (hero Tactics helpers).
- Confirm → FIGHT. **Aftermath** phase after FIGHT (play Aftermath Cards on survivors) → `_conclude_campaign`.

## 5. Combat events / triggers

The gauntlet emits SAP-style events that **Cards (Traps)** and **hero Command auras** hook:
- `combat_start` — once, before the first clash (Command auras + start Spells apply here).
- `on_faint` (= `ally_death`) — when any Troop faints.
- `on_hurt` (= `troop_below_50`) — when a Troop crosses a HP threshold.
These map 1:1 onto Spec B's v1 trigger set. Evaluated in a **dedicated post-step pass** (not inside the faint handler) to avoid mid-iteration mutation; death events are **queued during a step and drained** after (see Spec B §6).

## 6. Hero in combat

- **In the lineup:** occupies a slot; HP/Attack/cooldown from **Might** nodes (Spec A `hero_hp_mult`/`hero_damage_mult`/`hero_attack_speed_mult` now read as the hero unit's **base** stats, not a fight-card multiplier). **Command leader auras** apply to the whole lineup at `combat_start` at **100%** (e.g. aegis = +HP to all, march = +Attack to all, warchest = heal-over-time / shield). The hero's **signature** (Spec A §4) upgrades its own aura.
- **Benched:** the hero does **not** fight (no Might contribution) and its Command auras apply at `aura_value * hero_aura_benched_factor()` — **0.5** by default, or **1.0** if Spec A's **Steadfast** (Thrifty keystone, Spec A §3a/§7) is owned. This is the deliberate tradeoff for fielding a 5th Troop instead.
- The hero **cannot permadie**: if it faints in the lineup, it's out for the rest of *that* battle but returns next battle at full (permanent meta). Auras granted at `combat_start` persist for the battle even if the hero later faints.

## 7. Enemy lineup

Built from the existing seeded enemy roster (`get_battle_enemy_roster`/tier), now as a **capped, ordered lineup** seeded by `run_seed` + tier + elite. Enemy scaling unchanged (`hp_mult = 1.0 + tier*0.2 + 0.25*elite`) applied to enemy Troop HP. **Elite modifiers** (frenzied/armored/swift/vengeful) still apply to the enemy lineup.

## 8. Interaction with existing systems

- **Army synergies**: recomputed for the **lineup** (the 5 that fight) and applied as flat stat bonuses at `combat_start`.
- **Relics / curses**: keep `rt_player_*_mult` as global multipliers layered on top of base + Equip stats.
- **battle_odds / army_power_for**: reworked to estimate from the **lineup's** total `HP × Attack` (+ hero) vs the enemy lineup; or explicitly left as a rough/known-imprecise readout for phase 1 (flagged).
- **Duels** (sway recruiting): a duel is now a **1-Troop-each SAP battle** (hero vs the single recruit). Deck cards do **not** apply in duels (Spec B); the Guile `duel` aptitude bonus still buffs the hero. Resolution still sets `duel_outcome`.

## 9. Removals & migration

- Delete `hero_battle_mode`, `pending_hero_buff`, `_apply_hero_buff`, the prebattle **Fight/Buff** popup, and `battle_mode` use (vestigial schema key may stay).
- Delete the **Valor** economy: `valor`, `add_valor`/`spend_valor`, `hero_buff_cost`, +Valor pickups/rewards, and all UI references. (Spec A's Command nodes are now always-on auras, no cost.)
- Delete the **Quick Auto Battle** title entry + its standalone autobattle path.
- Rewrite `rt_unit.gd` combat: remove simultaneous-melee + alive-ratio; implement front-vs-front HP/Attack duels.
- `SAVE_VERSION` bump (coordinated with A/B); in-flight runs discarded with a one-line "previous run could not be resumed" title notice.

## 10. Integration seams

- `src/autobattler/autobattler.gd` — phase machine gains **PREP** and **AFTERMATH**; `_start_campaign_fight` builds capped lineups + bench; combat loop drives the front-vs-front gauntlet; `_conclude_campaign` permadies fainted lineup Troops, persists survivors+bench. Duel path → 1v1 SAP.
- `src/rtbattle/rt_unit.gd` — single-Troop HP/Attack combatant; front-vs-front engagement; faint; event emission (`combat_start`/`on_faint`/`on_hurt`).
- `src/game_manager.gd` — `run_seed`; remove Valor + fight/buff state; lineup/bench selection persistence; enemy lineup build; `army_power`/`battle_odds` rework; Troop rename.
- `src/level_select/level_select.gd` — remove the Fight/Buff prebattle popup + Valor UI; the node still sets pending battle + switches scene.
- `src/title/` — remove the Quick Auto Battle entry.

## 11. Phasing

- **Phase 1:** single-Troop model, front-vs-front gauntlet, capped lineup + bench, PREP/AFTERMATH phases, `combat_start`/`on_faint`/`on_hurt` events, Command auras (aegis/march/warchest), removals (fight/buff, Valor, QAB), duel-as-1v1. Hooks for Spec A (hero unit stats) + Spec B (cards in prep).
- **Phase 2:** combat polish/animation, ranged/positioning nuance, innate Troop abilities, battle_odds precision, richer enemy AI ordering.

## 12. Tuning knobs

Lineup cap (5), per-tier enemy scaling, attack cadence/`_speed_scale`, whether the hero is force-included or benchable, permadeath-on-faint vs heal-between-battles, aura magnitudes. Centralised in constants for data-only balancing.

## 13. Open for review

1. Lineup cap **5 incl. hero** — right number? Hero force-included, or benchable?
2. **Permadeath on faint** for lineup Troops (vs heal between battles) — confirm the throwaway intent.
3. battle_odds: rework now, or ship phase-1 as known-imprecise?
