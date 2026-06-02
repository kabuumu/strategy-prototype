# Hero Skill Tree & XP Evolution — Design

**Date:** 2026-06-02
**Status:** Draft for review
**Author:** Richard Melvin (with Claude)

## Goal

Make the **hero the persistent investment** across runs, while the **roster stays throwaway**. Replace the current auto-levelling hero (passive per-level scaling + a 5-perk random pick) with a **per-hero, permanent, CK3-lifestyle-style skill tree** funded by **XP that banks across runs** and is **spent between runs**.

A contributor flagged Hades as inspiration. Our spine already *is* Hades' Mirror of Night: a run-earned currency spent on a permanent meta tree, with in-run drafted power (Spec B's Card deck) playing the role of Boons. We keep the CK3 *tree* shape and borrow only Hades' **multi-rank nodes**; respec stays painful (CK3-style), not Hades-cheap.

**Built on Spec D (SAP combat).** The hero is now a **permanent unit in your Super Auto Pets-style lineup** (`2026-06-02-sap-combat-redesign-design.md`): **Might** = the hero unit's own combat stats, **Command** = **leader auras** it grants the lineup at battle start, **Guile** = recruiting/economy, **Tactics** = the deck. The old **fight/buff** mode and the **Valor** economy are **deleted** (Spec D), so Command auras are always-on (no cost) and there is no per-battle stance toggle — a heavy Might *and* a heavy Command build both pay off every battle.

## Design pillars (locked decisions)

| Topic | Decision |
|---|---|
| Reward streams | Every battle pays **XP → hero** (permanent) **and** Cards → Troops (in-run, Spec B). This feature builds the XP→hero half. |
| XP lifecycle | XP **banks across runs**, never lost; spent **between runs** on `charselect`; spending is optional (you may hoard). |
| Level ↔ points | Spend XP to buy **hero levels** (escalating cost); each level grants **+1 skill point**. Level is purely the point meter. |
| Tree ownership | **Per-hero.** Each hero owns its XP, level, and node allocation. All permanent. |
| Tree shape | **CK3 lifestyle**, **4 sections** (Might / Command / Guile / **Tactics**); each section = a **root that unlocks 2 branches**, branches chain down, converge at a **capstone**. |
| Node types | **Stat** nodes are **multi-rank** (Hades borrow). **Keystone** (the 5 existing perks), **signature**, and **capstone** nodes are single-purchase. |
| Capstones | **Bold in v1** — capstones implement their real mechanics (mitigation, revive, auras, deck effects) in the first cut, not deferred. |
| Passive scaling | **Removed.** All hero power comes from spent nodes — no free per-level stats. |
| Level cap | **Uncapped.** Escalating XP cost is the only brake; a fully-ranked tree is **44 points** (§3a). |
| Combat model | **Spec D (SAP lineup battler).** Hero = a permanent lineup unit (Might stats); Command = leader auras (always-on, 100% in lineup / 50% benched). **No fight/buff mode, no Valor.** |
| Combat levers | hero HP / Attack / attack-speed, **leader-aura** potency, sway aptitudes, +1 Troop-level (Veteran), gold/XP gain, **deck caps** (Tactics). New verbs (mitigation/revive/auras) arrive via capstones. No general armor/crit. Auras apply once at `combat_start` and last the battle (no duration lever). |
| Respec | **Costs a level**: each respec permanently drops the hero one level (−1 point forever), then reallocates remaining points. |
| Persistence | New **meta** save data `hero_meta` keyed per hero, alongside existing meta stats (`runs_won` etc.), **not** the run save. Survives `reset()`/`select_hero()`. |
| UI | Tree screen on **`charselect`** (pre-run, per selected hero), built in code per conventions. |

## Prerequisite refactor (shared with Spec B)

Before implementation, rename the roster-unit stat block — today called a "card" (`autobattler.gd::_card_stats`, the battle-reward "upgrade-card") — to **Troop**, freeing "Card" for Spec B's deck. `_card_stats`→`_troop_stats`; roster entry `{id,level,xp}` documented as a **Troop**. Mechanical, behaviour-preserving, done once (its own commit / first task).

## Scope boundary

**In scope:** the XP→hero tree (4 sections incl. Tactics), currency/levels/nodes, per-hero persistence, `charselect` UI, capstone mechanics, and migration of current hero progression.

**Adjacent (Spec B):** the Cards/Troops side is **Spec B — Card Deck-building** (`2026-06-02-tactics-card-deck-design.md`). The **Tactics section** here owns the *hero-side* deck perks (hand cap, set-slots, draw); Spec B consumes them via helpers (§7). Spec B defines the cards themselves.

**Out of scope:** general armor/crit unit stats. Cross-hero shared progression.

---

## 1. Reward streams

Battles report wins through `autobattler.gd::_conclude_campaign` → `GameManager.register_battle_won` — the single chokepoint that awards hero **XP** (and Spec B's Card grant). There are now just **two** economies — XP (permanent, hero) and Cards (run-local, deck); the old **Valor** currency is deleted with the fight/buff mode (Spec D §9).

## 2. XP economy (tunable starting points — confirmed "ballpark fine")

- **Earn:** per battle win, `hero_xp_award = 8 + 2 * tier`, ×1.5 elite, ×2 boss. Duel wins `+4` (duels grant none today). Added to the **selected hero's** `hero_meta` bank.
- **Level cost:** `level_cost(L)` is the XP to advance **from level L to L+1**, `= 10 * L` (so 1→2 costs 10, 2→3 costs 20, …). Starting at level 1, reaching level `N` costs `Σ_{L=1..N-1} 10L = 5·N·(N−1)` XP.
- **Point grant:** each level = **+1 unspent skill point**.
- **Level cap:** **uncapped**. A fully-ranked tree = **44 points** (Might 12 + Command 10 + Guile 11 + Tactics 11 — see §3a), so reaching it ≈ level 44, costing `5·44·43 ≈ 9,460` XP; escalating cost makes it a long arc.
- **Hoarding:** banked XP sits in `hero_meta[hero].xp`; spending is optional.

## 3. The tree — shared skeleton (4 sections)

Each **section** is a CK3 diamond:

```
            ● Root            (unlocks both branches)
           ╱      ╲
      ◻ A1          ◻ B1      (branch entries)
       │             │
      ◻/★ A2        ◻/★ B2    (branch depth)
           ╲      ╱
          ▣/◆ Capstone        (requires ≥3 points spent in this section)
```

**Gating:** root before any branch node; a branch node requires the one above it; a capstone requires **≥3 points in that section**. The Command **signature** (◆) occupies a capstone slot and uses the **same ≥3-points-in-section gate**. All four section roots are available from level 1.

**Node types:** **Stat (◻)** multi-rank (≤3 ranks, 1 point/rank). **Keystone (★)** single-purchase (the five existing perks). **Signature (◆)** single-purchase per-hero (upgrades the hero's own **leader aura**). **Capstone (▣)** single-purchase per-hero, section-gated, **real mechanic**.

### 3a. Shared nodes (identical for every hero)

| Section | Slot | Node | Type | Effect (per rank where multi) |
|---|---|---|---|---|
| **Might** | Root | Conditioning | stat ×3 | +8 hero max HP |
| Might | A1 | Honed Blade | stat ×3 | +6 hero damage |
| Might | A2 | **Warlord** ★ | keystone | +20% hero damage |
| Might | B1 | Quickstep | stat ×3 | −6% hero attack cooldown |
| Might | B2 | **Veteran** ★ | keystone | hero fights +1 Troop level |
| Might | Cap | *(per-hero ▣)* | capstone | §4 |
| **Command** | Root | Drillmaster | stat ×3 | +10% leader-aura potency |
| Command | A1 | Banneret | stat ×2 | +leader-aura potency (stacks with Drillmaster) |
| Command | A2 | **Inspiring** ★ | keystone | +50% leader-aura strength |
| Command | B1 | Quartermaster | stat ×2 | lineup starts each battle with +X temp HP (shield) |
| Command | B2 | **Thrifty** ★ (repurposed) | keystone | **Steadfast** — leader auras stay at 100% even when the hero is benched |
| Command | Cap | *(per-hero ◆)* | signature | upgrade own leader aura, §4 |
| **Guile** | Root | Charisma | stat ×2 | +1 to all sway aptitudes |
| Guile | A1 | Negotiator | stat ×2 | persuasion cost −20% |
| Guile | A2 | **Silver Tongue** ★ | keystone | +1 to all sway aptitudes |
| Guile | B1 | Duelist | stat ×2 | +15% hero power in duels |
| Guile | B2 | War Chest | stat ×3 | +2 gold & +3 XP per battle |
| Guile | Cap | *(per-hero ▣)* | capstone | §4 |
| **Tactics** | Root | Field Kit | stat ×2 | +1 Card hand cap |
| Tactics | A1 | Bandolier | stat ×2 | +1 Trap set-slot |
| Tactics | A2 | Quick Draw | stat ×2 | +1 prep play per fight |
| Tactics | B1 | Scout Ahead | stat ×2 | +1 Card reward per win |
| Tactics | B2 | Reserves | stat ×2 | +1 starting hand at run start |
| Tactics | Cap | *(per-hero ▣)* | capstone | §4 |

The five keystones map 1:1 onto today's `HERO_PERKS`. **Tactics** is an all-new section (no legacy perks); its **stat nodes** (Field Kit/Bandolier/Quick Draw/Scout Ahead/Reserves) are the sole source of the numeric deck-cap helpers in §7 — their effects are **self-contained here** (the *base* dial values they raise live in Spec B §5). The per-hero Tactics **capstones** (§4) are Spec-B combat/deck mechanics, **not** contributors to the cap helpers.

**Warlord re-split:** the legacy `warlord` perk was "+20% combat power" applied uniformly to HP **and** damage. It is re-split so HP scaling lives in *Conditioning* (3 ranks × +8 HP) and **Warlord becomes +20% hero damage only**. Net early-hero power is preserved because base hero HP is small relative to the Conditioning ranks; no further "tuning" is assumed by the design.

**Node-count accounting (44):** Might = Conditioning 3 + Honed 3 + Warlord 1 + Quickstep 3 + Veteran 1 + cap 1 = **12**; Command = Drillmaster 3 + Banneret 2 + Inspiring 1 + Quartermaster 2 + Thrifty 1 + signature 1 = **10**; Guile = Charisma 2 + Negotiator 2 + Silver Tongue 1 + Duelist 2 + War Chest 3 + cap 1 = **11**; Tactics = Field Kit 2 + Bandolier 2 + Quick Draw 2 + Scout Ahead 2 + Reserves 2 + cap 1 = **11**. Total **44**.

## 4. Per-hero data (signature + 3 capstones)

Each hero supplies: a **◆ signature** (Command capstone — upgrades its **leader aura**) and **three ▣ capstones** (Might, Guile, Tactics) with **real mechanics (v1)**. Everything else is shared. Aura families (applied to the whole lineup at `combat_start`): `aegis` = team **+HP**, `march` = team **+Attack**, `warchest` = team **heal-over-time**.

| Hero | Aura | ◆ Signature (Command) | ▣ Might | ▣ Guile | ▣ Tactics |
|---|---|---|---|---|---|
| Knight-Captain | aegis | Aegis Ascendant — Aegis +15%→+25% HP | **Bastion** — hero −25% damage taken | **Living Legend** — free recruit at run start | **Hold the Line** — first Trap each fight is free (no slot) |
| Bard | march | Crescendo — Marching Song +15%→+25% dmg | **Banner of War** — Troops adjacent to hero +10% dmg | **Pied Piper** — first recruit each run free | **Encore** — replay the last played Card once/run |
| Merchant-Prince | warchest | Golden Benefice — War Chest heal 25%→40% | **Bodyguard** — hero +40% HP | **Patron** — +50% gold per battle | **Black Market** — start each run with +2 Cards |
| Warden | aegis | Unbreakable Wall — Bulwark +15%→+30% HP | **Last Stand** — hero revives once/battle at 30% HP | **Provisioner** — start each run with +1 free Troop | **Entrench** — Troop-bound Traps also grant +HP |
| Trickster | march | Sleight — Feint +15%→+25% dmg | **Ambush** — hero +50% dmg on first attack | **Con Artist** — persuasion recruits always free | **Sleight of Hand** — draw +2 Cards at run start |
| Templar | warchest | Benediction Major — Benediction heal 25%→45% | **Zealot** — hero +30% dmg & attack speed | **Inquisitor** — +25% duel power & free duel re-fight | **Consecrate** — Aftermath Cards affect all survivors |

**Signature aura names** reuse each hero's existing `HEROES[id].buff.name`/`buff.desc` from `game_manager.gd` (the buff dict is repurposed as the hero's **leader aura** under Spec D) — the signature upgrades *that* aura's magnitude. Mapping (family → per-hero display name, from the current source): Knight-Captain `aegis`="Aegis" (+15%→+25% team HP); Warden `aegis`="Bulwark" (+15%→+30% team HP); Bard `march`="Marching Song" (+15%→+25% team Attack); Trickster `march`="Feint" (+15%→+25% team Attack); Merchant-Prince `warchest`="War Chest" (25%→40% heal); Templar `warchest`="Benediction" (25%→45% heal). The signature's display name (Aegis Ascendant, Crescendo, Sleight, etc.) is cosmetic; the *effect* is the aura-magnitude bump above.

Capstones implement their stated mechanic in v1 (the **bold-up-front** decision). New verbs (mitigation, revive, adjacency auras, conditional damage, free-trap, replay, multi-target) are built in `rt_unit`/autobattler/Spec B (§10).

## 5. Respec

A **Respec** action on `charselect`: refunds all spent points → unspent; permanently **drops the hero's level by 1** (the lost point is gone forever); player re-allocates the rest. Confirm dialog ("Respec costs a hero level — permanent"). Cannot drop below level 1. Intentionally punishing → respec is rare.

## 6. Data model & persistence

```gdscript
var hero_meta: Dictionary = {}   # { hero_id: {"xp":int,"level":int,"nodes":{node_id:rank}} }
```
`_hero_meta(id)` returns/initialises `{xp=0, level=1, nodes={}}`. Selected-hero accessors read `hero_meta[selected_hero]`.

**Persistence:** stored with the **meta/profile** persistence holding `runs_won`/`best_tier_reached`/`best_streak_ever` (cross-run), **not** `RUN_SAVE_PATH`. Must survive `reset()`/`select_hero()`.

**Tree definition data:** `HERO_TREE` (shared skeleton: section→slot→`{id,type,branch,prereq,max_rank,per_rank_effect,gate}`) + `HERO_SIGNATURE`/`HERO_CAPSTONES` from §4 (or folded into `HEROES` as a `tree` sub-dict).

## 7. Helper rewrites (API-stable where possible)

Rewrite helper **bodies** to read the selected hero's purchased nodes; keep names/return types.

| Helper | New source |
|---|---|
| `hero_hp_mult()` / `hero_damage_mult()` (replace `hero_fight_mult`) | the **hero unit's base** HP / Attack. HP: Conditioning. Attack: Honed Blade + Warlord + per-hero caps. |
| `hero_attack_speed_mult()` *(new)* | Quickstep (+ Zealot). |
| `hero_fight_bonus_level()` | Veteran (hero unit +1 Troop-level worth of stats). |
| `hero_aura_mult()` (was `hero_buff_mult`) | Drillmaster/Banneret + Inspiring + signature. Final aura = `base_aura * hero_aura_mult() * (1.0 in lineup / 0.5 benched, unless Steadfast)`. |
| `hero_aura_benched_factor()` *(new)* | `1.0` if **Steadfast** (Thrifty) owned, else `0.5` — the benched-aura multiplier. |
| `hero_team_shield()` *(new)* | Quartermaster (lineup start-of-battle temp HP). |
| `hero_sway_aptitude(type)` | base + Charisma/Silver Tongue/Negotiator/Duelist. |
| `hero_gold_xp_bonus()` *(new)* | War Chest. |
| **Deck caps (new, consumed by Spec B):** `hero_hand_cap()`, `hero_trap_slots()`, `hero_prep_budget()`, `hero_card_reward_bonus()`, `hero_start_hand()` | Tactics stat nodes (Field Kit/Bandolier/Quick Draw/Scout Ahead/Reserves). |

**Removed helpers:** `hero_buff_cost` and `hero_valor_per_win` (Valor deleted, Spec D). All new helpers **early-return their neutral value** (`1.0`/`0`/base) when `has_hero()` is false.

**Autobattler change:** the hero is built as a **lineup Troop** (Spec D §6) — `hero_hp_mult`/`hero_damage_mult`/`hero_attack_speed_mult` set its base HP/Attack/cooldown; Command auras apply at `combat_start` scaled by `hero_aura_mult()` and the lineup/bench factor; capstone mechanics hook in `rt_unit`.

## 8. UI — `charselect` tree screen

All UI built in code (`_build_*`/`_refresh_*`, inline `StyleBoxFlat`). Selecting a hero shows its tree: header (level, banked XP, unspent points, "Buy level (cost N XP)"), the **4 sections** as CK3 diamonds with node tooltips (effect/cost/rank), and a **Respec** button. Buy-level spends XP (+1 level, +1 point); clicking an unlocked node buys/ranks it (respecting prereqs/gates). Locked heroes (`HERO_UNLOCK`) show a greyed tree + unlock hint. "Start run" enters the existing `reset()`→`select_hero()` flow; the meta tree is **not** wiped by it.

## 9. Integration seams

- `src/game_manager.gd` — add `hero_meta`, `HERO_TREE`, per-hero signature/capstone data, accessors, `hero_buy_level()`, `hero_buy_node(id)`, `hero_respec()`, `hero_node_rank(id)`, gating predicates, deck-cap + aura helpers (§7). Rewrite the helper bodies. `register_battle_won` awards XP into `hero_meta`. `select_hero` (L288–302) stops zeroing `hero_level/xp/perks`; it no longer touches **Valor** or **battle mode** (both deleted, Spec D); still applies `start_bonus`. Meta save load/store gains `hero_meta` (+ a meta schema version, prune orphaned node-ids on load). `save_run`/`load_run` (L820–882) **drop** `hero_level/hero_xp/hero_perks/pending_hero_perk` (and Valor/`battle_mode` per Spec D) and (with Spec B) **add** `card_deck/card_hand/card_graveyard`; **bump `SAVE_VERSION` once** as a single coordinated change shared with Specs B & D.
- `src/charselect/charselect.gd` — the 4-section tree panel + buy/spend/respec handlers. **No starter allotment**: a fresh/newly-unlocked hero begins at `{xp:0, level:1, nodes:{}}` (pure earn — confirmed). Respec disabled at level 1.
- `src/autobattler/autobattler.gd` — build the hero as a lineup unit (§7, Spec D §6); Command auras at `combat_start`; capstone hooks.
- `src/rtbattle/rt_unit.gd` — capstone mechanics (mitigation/revive/auras); attack-speed already exists.
- `src/level_select/level_select.gd` — **remove** the perk-pick popup path (`_show_hero_perk_popup` + its chain in `_show_pending_rewards`). The **Fight/Buff prebattle popup and all Valor UI are removed** (Spec D), not kept.

## 10. Migration & removals

Delete/replace: `HERO_XP_PER_LEVEL`, `HERO_MAX_LEVEL` (→ uncapped), `hero_gain_xp` (→ bank XP), `random_hero_perk_choices`, `grant_hero_perk`, `_unowned_perks`, `pending_hero_perk`, the passive scaling terms, the `level_select` perk-pick UI. `HERO_PERKS` ids reused as keystone node ids.

## 11. Phasing

- **Phase 1 (full feature):** XP bank + levels + points; the 4-section CK3 tree (stat multi-rank + keystone + signature + **capstones with real mechanics**); respec; per-hero meta persistence; `charselect` UI; helper rewrites incl. deck-cap helpers for Spec B.
- **Phase 2 (polish):** balance passes, extra heroes/nodes, tree-screen visual flourish. (No core mechanic deferred — capstones are bold-up-front.)

## 12. Tuning knobs

XP curve, `level_cost`, per-rank increments, max ranks, capstone gate (≥3), respec severity, deck-cap base values (with Spec B §5). Centralised in `HERO_TREE` + economy functions → data-only balancing.

## 13. Testing

`tools/smoke_test.sh` boots every scene. Manual: earn XP across a run → `charselect` → buy levels/nodes (all 4 sections) → start a new run → hero spawns with node-derived stats, tree persisted. Verify respec drops a level; a locked hero shows a locked tree; a capstone mechanic fires in combat; old run saves discarded by the `SAVE_VERSION` bump.

## Resolved (was open)

Capstones **bold in v1**; level **uncapped**; deck perks get a dedicated **Tactics section** (not Guile); XP numbers **kept as ballpark**.
