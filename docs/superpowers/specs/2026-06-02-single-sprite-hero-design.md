# Single-Sprite Hero Representation In-Battle Design

**Date:** 2026-06-02  
**Status:** Approved

## Overview

In the current auto-battler implementation, all units (including the hero in "fight" mode or during a recruitment duel) are represented as squads of multiple soldier sprites (e.g., 9 infantry sprites, 5 cavalry sprites) that shrink as they lose HP. 

This design specifies updating the hero in-battle representation to show **exactly one unit sprite** that is **slightly larger** so it is clearly identified as the hero. To preserve the tactical spatial spacing, combat balance, and blocking physics, the hero's collision radius and team floor disc footprint will remain equivalent to a full squad.

## Details

### 1. [autobattler.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/autobattler/autobattler.gd) Modifications

To ensure the battle system correctly identifies the hero across all fight paths:
- In `_start_duel_fight()`, when constructing `hero_card`, add `"hero": true` to the dictionary (both when the campaign has a hero and in the fallback case).
- In `_spawn_unit(card, team_id, pos, hp_mult, synergy_counts)`, pass the `"hero"` flag to the unit stats dictionary:
  ```gdscript
  stats["is_hero"] = card.get("hero", false)
  ```

### 2. [rt_unit.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/rtbattle/rt_unit.gd) Modifications

To adjust unit layout, scale, and count dynamically based on the hero flag:
- Add a new member variable: `var is_hero: bool = false` to track hero status on the unit.
- In `setup(type, p_team, world_pos, stats)`:
  - Retrieve `is_hero = bool(stats.get("is_hero", false))`.
  - Calculate `radius` using the archetype's base `soldier_count` from `stats` (e.g. 9 for soldier, 5 for scout, etc.) *before* adjusting the count. This preserves the standard blocking footprint and team disc scale.
  - If `is_hero` is true, override `soldier_count = 1`. This naturally makes `hp_per_soldier` equal to `max_hp`, preventing individual sprite culling during damage phase.
- In `_build_visuals(stats)`:
  - When spawning the soldier sprite, if `is_hero` is true, set the offset and position to `Vector2.ZERO` (center of the unit) and skip the jitter calculation.
  - Set the sprite's scale to `Vector2(1.3, 1.3)` if `is_hero` is true, making it larger than standard units (which scale at `0.9`).

## Verification Plan

We will perform a manual/smoke-test validation:
1. Boot the game and start a new campaign.
2. Select a hero and enter a battle, choosing the **Fight** mode for the hero.
3. Verify that:
   - The hero is rendered as a single, larger sprite in the player's team.
   - Normal units in the player's and enemy's team are still represented as normal squads.
   - Floor disc and health bars are sized correctly.
   - Attacking animation (lunge), taking damage (white flash, numbers, no culling), and death animation (rotation, fade-out, queue-free) function properly.
4. Attempt a recruitment duel and verify that the hero unit is represented as a single, larger sprite.
