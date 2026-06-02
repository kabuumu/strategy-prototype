# Hero Front Formation Design

**Date:** 2026-06-02  
**Status:** Approved

## Overview

In the auto-battler campaign fight setup, the player units are placed in a horizontal line formation. The position depth is calculated using the unit's index in the spawned cards array, where index 0 is closest to the enemy (the front of the formation) and subsequent indices are placed further back.

Currently, the hero unit is appended to the end of the arrays, placing them at the very back of the formation. This design specifies moving the hero unit to the very front of the formation (index 0) to lead the charge. The hero's base stats will be left as-is per design request.

## Details

### 1. [autobattler.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/autobattler/autobattler.gd) Modifications

We will adjust `_start_campaign_fight()` to prepend the hero card rather than appending it.

- Before adding the campaign roster entries to `p_cards` and `p_entries`, check if the hero fights:
  - If yes, append the hero's card representation to `p_cards` and `null` to `p_entries` first.
  - Then loop through and append the `player_roster` entries.
- This ensures the hero is at index 0 of `p_cards` and `p_entries`, receiving the front-most position coordinate `x = 470.0`.

## Verification Plan

We will perform a manual validation:
1. Start a new campaign.
2. Select a hero and enter a battle in **Fight** mode.
3. Verify that:
   - The hero is rendered at the front of the line (closest to the center line/enemy units).
   - The other player squad units are lined up behind the hero.
   - The hero participates in combat correctly and takes damage first.
   - When the fight is won, the write-back of survivors continues to function correctly (and the hero is not persisted/added to the player roster).
4. Run `tools/smoke_test.sh` to ensure there are no parser/compilation errors.
