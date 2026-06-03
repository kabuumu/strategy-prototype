# Card Deck-building — Design

**Date:** 2026-06-02
**Status:** Draft for review
**Author:** Richard Melvin (with Claude)
**Sibling specs:** Spec A (`2026-06-02-hero-skill-tree-design.md`) and **Spec D (`2026-06-02-sap-combat-redesign-design.md`) — the SAP combat this builds on.** This is Spec B.

## Goal

Give the run-local **units side** real depth as a **deck-building** layer. The hero carries a **deck of Cards**; each run draws a fresh hand, grows the deck from battle rewards, and the player **sets cards ahead of time** to buff units and to arm **traps** that auto-fire mid-combat. Cards are **one-use**. This is the throwaway counterpart to the permanent hero tree.

**Fit with Spec D (SAP lineup battler):**
- The deck's home is **Spec D's PREP phase** (arrange the lineup, then play Equip/Spell + set Traps). **Aftermath** is Spec D's post-FIGHT phase. There is **no** level_select prep popup.
- Traps fire on Spec D's combat **events** — `combat_start` / `on_faint` (=`ally_death`) / `on_hurt` (=`troop_below_50`) — a perfect fit for SAP.
- **Campaign-only.** The deck is hero-owned; Quick Auto Battle is deleted (Spec D), so there is no no-hero deck case. Every deck call is gated on `has_hero()`.
- **Equip targets** are lineup Troops **or the hero** (the hero is now a lineup unit; equipping it buffs it for that battle, then the Card is spent).
- **Duels are deck-free** (Spec D): a 1v1 hero-vs-recruit test — no prep, no cards, no traps, no card consumption.

## Prerequisite refactor — free the word "Card"

Today the codebase calls a **roster-unit stat block** a "card" (`autobattler.gd::_card_stats`, the battle-reward "upgrade-card"). Before this feature, rename that concept to **Troop** so "Card" means *only* a deck card:

- `_card_stats(card)` → `_troop_stats(troop)`; local `card`/`cards` vars over roster entries → `troop`/`troops`; related comments updated.
- Roster entry `{id, level, xp}` is documented as a **Troop** (a persistent army member; under Spec D it fights as a single-pet `rt_unit` with HP + Attack).
- The three layers become explicit: `UNIT_TYPES` (definitions) → **Troop** (roster member) → `rt_unit` (combat instance).

This is a mechanical, behaviour-preserving rename (its own small commit / first task), shared by Spec A.

## Unified reward: upgrade-cards *are* Cards

The existing battle-reward **"upgrade-card"** (buff/level a roster Troop) is **the same thing** as a deck Card — specifically an **Equip** Card. There is **no separate card reward stream**: winning a battle grants Card(s) into the deck, and "upgrade a Troop" is simply one Card category you can play. The current upgrade-card reward UI is absorbed into the deck reward flow.

## Pillars (locked decisions)

| Topic | Decision |
|---|---|
| Deck scope | **Run-local.** Drawn fresh and grown each run; gone at run end (run save, not meta). |
| Deck model | A **draw pile** (`card_deck`, unlimited) + a **hand** (`card_hand`, capped at `hero_hand_cap()`, base 5) + a **graveyard** (`card_graveyard`). |
| Starting hand | Each run, the deck is seeded from the pool (deterministic per run seed); the hand is **filled up to the cap** (base 5) by drawing from the deck. |
| Refill | At each battle's prep, the hand is **topped back up to the cap** from the draw pile. Unplayed Cards stay in hand. |
| Growth | On a win, the player **drafts 1 of 3 offered Cards** into the draw pile (preserves the old upgrade-card choice). Nothing is discarded; the hand cap limits hand size only, never total Cards held. |
| Lifecycle | **One-use** — a Card is spent when played or triggered; sent to a per-run "graveyard". |
| Activation model | **Yu-Gi-Oh set/trigger.** Cards are set *ahead of time*; "during" cards (Traps) **auto-activate** on a condition — no live input, so the auto-battler stays hands-off. |
| Timing windows | **Before** (Equip/Spell on Troops), **set→during** (Traps), **After** (Aftermath on survivors). |
| Coupling to hero | Hero-tree nodes grant deck perks (starting hand size, set-slots, retention, draw quality) — see §7. |

## 1. Deck lifecycle

- **Run start:** seed the draw pile from the pool (run seed), then draw up to the hand cap (base 5) into the hand.
- **Per battle prep:** top the hand back up to the cap from the draw pile, then the player plays/sets Cards from hand; played Cards leave the hand (→ graveyard). Unplayed Cards **stay in hand** and carry forward.
- **Rewards (draft):** on a win, offer **3 Cards** (tier-scaled rarity; elite/boss offer better); the player **picks 1** into the **draw pile** (the rest are not kept). This replaces the old upgrade-card pick. Drafted Cards reach the hand at the next prep refill. Nothing is discarded for being "over cap" — the cap limits hand size, the draw pile is unlimited.
- **One-use:** a played Equip/Spell, a triggered Trap, and a played Aftermath all go to the **graveyard** (out of the run).
- **Run end:** deck, hand, and graveyard are discarded.

## 2. Card categories

| Category | Window | Behaviour |
|---|---|---|
| **Equip / Spell** | Before (prep) | Played on a roster Troop (Equip = lasting stat buff for the fight — *this is the former "upgrade-card"*) or as an immediate effect (Spell = e.g. "deal 2 damage to an enemy now"). |
| **Trap** | Set ahead → fires During | Set face-down before the fight with a **trigger condition**; **auto-activates** when met in combat. No live input. |
| **Aftermath** | After | Played post-battle on a survivor (heal, promote, revive a fallen Troop). |

## 3. Card anatomy

```gdscript
# A Card definition (data, in a CARD_POOL constant).
{
  "id": "snare",
  "name": "Snare",
  "category": "trap",          # equip | spell | trap | aftermath
  "rarity": "common",
  "target": "battlefield",     # troop | hero | enemy | battlefield | survivor | fallen
                               #   ('hero' = the hero lineup unit — addressable for Equip though it isn't in player_roster)
  "trigger": "ally_death",     # traps only — v1: combat_start | ally_death | troop_below_50
  "trigger_value": 0,          # optional threshold for parameterised triggers (phase 2)
  "effect": {"kind": "stun", "value": 1.0},   # interpreted by the resolver
  "desc": "When an ally dies, stun the nearest enemy for 1s."
}
```

Effects reuse existing levers where possible (HP, damage, attack-cooldown, range→ranged, heal, level-up = the upgrade-card effect). New verbs (stun, revive, summon, on-condition procs) are the genuinely new combat code (see §6/§10).

## 4. Starter card pool (draft — tunable)

**Equip — persistent stat buffs attached to a Troop for the fight (incl. the old upgrade-cards):** *Battlefield Promotion* (Troop +1 level — the classic upgrade-card), *Inspire* (+1 effective level for the fight), *Whetstone* (+50% damage), *Iron Hide* (+50% HP), *Longbow* (Troop becomes ranged), *Swift Boots* (−25% attack cooldown).
**Spell — immediate one-shot effects resolved at fight start, targeting an enemy or the battlefield (never a persistent Troop attach):** *Firebolt* (damage one enemy), *Volley* (damage the frontmost enemy line).
**Trap:** *Snare* (ally dies → stun nearest enemy), *Second Wind* (Troop below 50% → heal it), *Caltrops* (combat start → damage the frontmost enemy), *Vengeance* (ally dies → nearby allies +damage).
**Aftermath:** *Field Medic* (heal a survivor to full), *Battlefield Medal* (a survivor +1 level). *Reinforce* (revive a fallen Troop) is **phase 2** — it needs the new revive verb + a fallen-Troop list (§10).

Rarity weights bias draws/rewards toward commons. **Equip stacking:** multiple Equips may target one Troop; numeric buffs stack **additively**; *Longbow* ("becomes ranged") sets the range flag and overrides melee range. Equip plays per fight are bounded by the prep budget (§5).

## 5. Hand & set-slot limits (tight baseline — the Tactics tree raises these)

Confirmed **tight/scarce** baseline so the Tactics tree investment matters:

- **Hand cap:** **5** Cards — limits **hand size only**. The draw pile is unlimited; the hand refills up to the cap each prep (§1). Nothing is discarded for being over cap.
- **Set-slots per battle:** **2** Traps at once.
- **Prep budget:** **1** play per fight, a **single shared pool** covering Equip *and* Spell combined (not 1 each). **Aftermath** plays draw from this same prep budget (so raising `hero_prep_budget()` raises Aftermath plays too — there is no separate Aftermath dial).
- The **Tactics** section of the hero tree (Spec A §3a) raises these via five helpers: `hero_hand_cap()` (Field Kit), `hero_trap_slots()` (Bandolier), `hero_prep_budget()` (Quick Draw), `hero_card_reward_bonus()` (Scout Ahead), `hero_start_hand()` (Reserves).

## 6. Combat & resolution integration

- **Equip** applied at Troop spawn: fold into `autobattler.gd::_spawn_unit` / `_troop_stats` as stat overrides on the target Troop.
- **Spell** (immediate) resolved at fight start before the sim runs.
- **Trap:** armed traps subscribe to **Spec D's combat events** (`combat_start` / `on_faint`=`ally_death` / `on_hurt`=`troop_below_50`). Evaluated in Spec D's **dedicated post-step pass** (not inside the faint handler): death events are queued during a step and drained after, each trap has a `fired` flag (so `troop_below_50` fires once), and on match the effect resolves via the existing damage/heal helpers and the Card moves to the graveyard. v1 effects use existing levers; new verbs (stun/summon/revive) are phase 2.
- **Aftermath** resolved on the post-battle survivors list before survivors are written back via `set_roster`.

## 7. Interface to the hero tree (Spec A coupling)

The deck is buffed by a dedicated **Tactics section** in the hero tree (Spec A §3a — the 4th section), so investing in the **permanent** hero strengthens the **throwaway** deck. Spec A owns the *hero-side* caps; Spec B reads them through helpers:

| Tactics node (Spec A) | Helper | Deck effect |
|---|---|---|
| Field Kit (root) | `hero_hand_cap()` | +1 hand cap |
| Bandolier (A1) | `hero_trap_slots()` | +1 Trap set-slot |
| Quick Draw (A2) | `hero_prep_budget()` | +1 prep play per fight |
| Scout Ahead (B1) | `hero_card_reward_bonus()` | +1 Card reward per win |
| Reserves (B2) | `hero_start_hand()` | +1 starting hand at run start |
| Tactics ▣ capstone (per-hero) | various | e.g. free Trap (*Hold the Line*), replay (*Encore*), +2 start Cards (*Black Market*), draw +2 (*Sleight of Hand*), Aftermath all survivors (*Consecrate*), Troop-bound Traps +HP (*Entrench*) |

The deck **applies** these caps; Spec A **provides** the helper values. No card definitions live in Spec A.

## 8. Persistence

Stored in the **run save** (`RUN_SAVE_PATH`, `"run"` section) alongside `roster`/`gold`:
```
card_deck      : Array   # remaining draw pile (ids)
card_hand      : Array   # cards in hand (ids)
card_graveyard : Array   # spent this run (ids) — for UI/history
```
Bump `SAVE_VERSION` **once, coordinated with Specs A & D** (all three touch the run save). Cleared by `reset()`/`clear_run()`. Deterministic: starting hand + reward draws keyed on **`run_seed`** (the shared prereq introduced by Spec D — `run_seed` combined with `battles_won` + draw-index), following the existing seeded-RNG precedent for recruits/elite mods.

## 9. UI (built in code, per conventions)

- **Reward draft (on win):** a 3-Card offer; the player picks 1 into the draw pile. This **replaces the old upgrade-card pick** popup (same "choose your reward" agency) — shown in the existing `_show_pending_rewards` slot in `level_select`.
- **Prep / set screen** = **Spec D's PREP phase** in the autobattler (after lineups build, before FIGHT): hand (refilled to cap) shown as cards; click to play an Equip on a lineup Troop **or the hero**, cast a Spell, or set a Trap into a slot. Respect the shared prep budget / set-slots.
- **Aftermath screen** = **Spec D's AFTERMATH phase** (after FIGHT, before `_conclude_campaign`): survivors listed; play Aftermath Cards (drawing from the same prep budget).
- **Deck/hand HUD:** small hand indicator + draw-pile + graveyard counts.

## 10. Phasing

- **Phase 1:** deck lifecycle (draw pile/hand/graveyard, refill, reward draft), hand & set-slots, **Equip/Spell/Aftermath** using **existing levers only** (HP, damage, attack-cooldown, range, heal, level-up — the upgrade-card path reused), and **Traps** whose triggers are `combat_start`/`ally_death`/`troop_below_50` and whose effects are existing levers (damage/heal/+damage — e.g. Caltrops, Second Wind, Vengeance). Prep + Aftermath + draft UI. Tactics-tree coupling.
- **Phase 2:** new effect **verbs** (`stun` → Snare, `summon`, `revive` → Reinforce, conditional auras) in `rt_unit`; parameterised triggers (`trigger_value`); drag-and-drop polish; deck-manipulation capstone effects. Reviving needs a fallen-Troop list (target `fallen`, built from the battle's casualties).

## 11. Integration seams

- **Prereq refactor:** `_card_stats`→`_troop_stats` and roster "card" naming → "Troop" across `game_manager.gd` / `autobattler.gd` (shared with Spec A).
- `src/game_manager.gd` — `card_deck/hand/graveyard` state, `CARD_POOL` constant, deck helpers (`draw_cards(n)`, `play_card`, `arm_trap`, reward grant), run-save load/store, `reset()` clearing, deterministic seeding. Deck-cap helpers read hero-tree node values (Spec A helpers).
- `src/autobattler/autobattler.gd` — apply Equip/Spell at army build (`_spawn_unit`/`_troop_stats`), Trap trigger checks in the combat update, Aftermath on survivors before `set_roster`.
- `src/rtbattle/rt_unit.gd` — trap trigger conditions + new effect verbs (phase 2).
- `src/autobattler/autobattler.gd` — **PREP** phase hosts prep/set UI; **AFTERMATH** phase hosts Aftermath play (Spec D phases).
- `src/level_select/level_select.gd` — only the **3-Card reward draft** in `_show_pending_rewards` (replacing the upgrade-card pick). Prep/set/aftermath are **not** here — they live in the autobattler (Spec D).
- (Reward) — battle-win Card grant alongside Spec A's XP grant in `register_battle_won` / `_conclude_campaign`.

## 12. Resolved (was open)

1. **Dials → tight baseline:** hand 5 / set-slots 2 / prep 1 (§5); the Tactics tree raises them.
2. **Starter pool (§4):** vibe confirmed for v1; expand later.
3. **Trap binding → per-Card `target` field:** cards may be Troop-bound or battlefield-global as their `target` declares.
4. **Deck perks → dedicated Tactics section** in Spec A (the 4th tree section), not Guile nodes.
