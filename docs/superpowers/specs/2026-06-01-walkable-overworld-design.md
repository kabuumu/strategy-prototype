# Walkable Overworld — Design (Phase 3 of 3)

Date: 2026-06-01
Status: approved, implementing

## Context

Final phase of the hero-led campaign. The overworld stops being a click-to-jump
node graph and becomes **one continuous horizontal world**: the hero avatar
walks left→right across the run, steering into forks to choose the next node,
picking up gold/Valor and hitting the occasional encounter along the way.

Approved decisions:
- **One continuous horizontal world** (graph data reused, presentation rebuilt).
- **Steer into a fork** to choose the path.
- **Placeholder art** (shapes + the hero unit sprite).

The GameManager tier/node/connection graph, node types, reachability
(`get_reachable_indices`), and every node handler/popup are unchanged. Only
`level_select.gd`'s presentation + interaction layer is rewritten.

## Layout

Node world position (`_node_world_pos(tier, index)`):
`x = MARGIN_X + tier * TIER_DX` (tier 0 left, boss far right);
`y = center + (index - (count-1)/2) * LANE_GAP`. The run start (before any node
visited) is a virtual point just left of tier 0.

The world is wider than the play area (the HUD panel occupies the right ~330px,
so the play viewport is `PLAY_W` wide). A horizontal camera `_cam_x` follows the
avatar, clamped to the world bounds; everything in `_draw` is offset by `-_cam_x`.
Vertical camera is fixed (lane spread fits the band).

## Avatar + navigation state machine

`enum Nav { AT_NODE, TRAVELING }`. The avatar stands at its current node
(`_cur_tier`/`_cur_index`, from `current_tier-1`/`last_chosen_index`, or the
virtual start). `_targets` = reachable next nodes (`get_reachable_indices`),
`_sel` = selected target.

- **AT_NODE**: ↑/↓ (W/S) cycle `_sel` among `_targets` (highlights its path +
  shows the node preview in the HUD). Hold →/D to commit and start travelling to
  the selected target. No backward movement (no backtrack).
- **TRAVELING**: the avatar interpolates along the edge from the current node to
  the target at `WALK_SPEED`. Pickups on the edge are collected when crossed.
  Reaching the end → arrive: `_trigger_node(target)`.

Input: held →/D polled in `_process` to advance; ↑/↓ and Esc/I via
`_unhandled_input`. (Mouse not required.)

## Edge content (seeded per edge: `tier,index,target`)

Generated when travel begins, with a local RNG seeded from the edge so it's
stable:
- **Pickups**: 0–2 along the edge, each gold (+8–15) or Valor (+1). Collected by
  crossing; `add_gold`/`add_valor`; sfx + small toast.
- **Encounter**: ~25% chance. Opens a popup at the *start* of the edge (avatar
  waits at the from-node until it closes, then walks on — no mid-edge scene
  changes). Encounter is either a `random_event()` (reuses `_build_event_popup`)
  or a lone wandering recruit with sway restricted to **dialogue/persuasion**
  (in-popup resolvers only — never a duel, which would scene-change mid-travel).

## Arrival → node trigger

`_trigger_node(tier, index)` = the old `_on_node_pressed` body: `visit_node`
then the type `match` (battle/elite → prebattle popup or launch; gain_unit →
recruit popup; shop/heal/event/treasure). Scene-changing nodes (battle, and the
duel sway) leave to the autobattler; on return `_ready` re-anchors the avatar at
the new current node. Non-scene nodes open a popup or resolve instantly; once the
popup closes the avatar **re-anchors** to the arrived node and offers the next
fork (`_awaiting_resolve` flag checked in `_process`: when set and `_popup ==
null`, call `_anchor_to_current`).

## Rendering (`_draw`, placeholder art)

Right HUD panel backdrop (kept). World (offset by `-_cam_x`): a ground band,
connection paths as lines (selected target's path brighter), nodes as typed
colored circles with a short label (visited dimmed, reachable targets pulsing,
current node ringed), pickups as small coins, and the hero sprite
(`assets/units/<hero sprite_key>_player.png`, or `soldier` fallback) at the
avatar position.

## Kept / replaced

- **Kept:** HUD (`_build_hud`/`_refresh` label updates), all popups (recruit,
  shop, event, prebattle, reward, inventory, settings), victory, save/resume,
  duel-return handling, `_node_detail_text`, `_show_toast`.
- **Replaced:** layout constants + scroll vars; `_build_node_buttons`,
  `_add_node_button`, `_node_x`, `_tier_screen_y`, `_update_scroll_bounds`,
  `_center_on_tier`, `_scroll_by`, `_reposition_nodes`, the graph/scroll parts of
  `_draw`, the pulse-only `_process`, the scroll parts of `_unhandled_input`, and
  the node-button loop in `_refresh`. `_on_node_pressed` becomes `_trigger_node`
  (same body) called on arrival.

## GameManager

No new functions required — edge pickups/encounters are generated locally in
`level_select` with a seeded RNG, applied via existing `add_gold`/`add_valor`/
`recruit_candidates`/`random_event`. (Deviation from the brainstorm note that
mentioned `edge_pickups`/`edge_encounter` helpers — keeping it in the scene
avoids touching GameManager for pure presentation state.)

## Out of scope
Full platforming (jumps/hazards), parallax/tiled art, per-edge persistent pickup
state (not needed — no backtracking, so traversed edges are never revisited).

## Testing
- `tools/smoke_test.sh` boots clean.
- Headless harness: instance `level_select`, drive the nav state machine
  programmatically (select targets, begin travel, step `_process` to arrival,
  assert `visit_node` advanced and the right handler fired), and verify pickups
  apply gold/Valor and the camera clamps.

## Files
- Changed: `src/level_select/level_select.gd`, `CLAUDE.md`,
  `.github/copilot-instructions.md`.
- New: this spec.
