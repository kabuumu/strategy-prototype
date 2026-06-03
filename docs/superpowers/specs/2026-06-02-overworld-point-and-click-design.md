# Overworld Point-and-Click Movement — Design

**Date:** 2026-06-02
**Status:** Draft for review
**Author:** Richard Melvin (with Claude)
**Independent** of Spec A (hero tree) and Spec B (card deck). Touches only `src/level_select/level_select.gd`.

## Goal

Add **mouse point-and-click** navigation to the walkable overworld, alongside the existing keyboard nav. Click a node to walk there; the minimap becomes interactive; click-drag pans the camera to scout ahead. No change to the map graph, node handlers, or game state — this is an **input/camera layer** over the current `Nav` state machine.

## Decisions (locked)

| Topic | Decision |
|---|---|
| Hop model | **Multi-hop targeting, stop at each interrupting node.** Click any forward node → the avatar auto-walks toward it, auto-picking forks along the path, and **stops at the first node that needs input** (every battle/shop/event/heal node does). Re-click to continue. |
| Persistence | **Session-local only.** The travel intent lives in `level_select`; it is **not** stored in `GameManager` and does **not** survive a battle's scene round-trip. After a scene-changing node, the player clicks again. (No new save state.) |
| Minimap | **Interactive:** click a reachable node on the minimap to travel; click/drag the minimap (or main map) to **pan the camera**. |
| Keyboard | **Additive** — ↑↓ steer, hold →/D travel all still work unchanged. |
| Feedback | Hover any node → show its node-detail + a highlight ring. Reachable nodes keep their pulse. |

## How it relates to today's Nav

The current model (CLAUDE.md): avatar walks left→right; `_targets` = reachable next nodes (`get_reachable_indices`); `_select_target(±1)` cycles `_sel`; holding →/D calls `_begin_travel()` → `_update_travel()` → `_arrive()` → `_trigger_node()`. Interrupting nodes set `_leaving` (scene change) or `_awaiting_resolve` (popup). Coordinates: a node's screen position is `_w2s(_node_world_pos(tier, index))`, radius `NODE_R`; the camera is `_cam_x` via `_update_camera`.

Point-and-click reuses **all** of this. It only adds: mouse hit-testing → choosing `_sel` and calling `_begin_travel()`, a multi-hop "head toward D" loop, and a manual camera-pan mode.

## 1. Behaviour model

1. **Click a forward node D** (any node in a later tier with a path from the current node). If D is the immediate fork, it's a one-edge walk; if further, it's a multi-hop intent.
2. Set session var `_auto_dest = {tier, index}` (D).
3. Each time the avatar is `AT_NODE` and not blocked, compute the **next hop toward D** (§3), set `_sel` to it, and `_begin_travel()`.
4. On `_arrive()` the node triggers as today. If it sets `_leaving`/`_awaiting_resolve` (an **interrupting** node), the walk halts there and **`_auto_dest` is cleared** — the player resolves it, then clicks again to continue. If a node ever does *not* interrupt (e.g. a future passive node), the loop auto-advances to the next hop.
5. Reaching D, clicking the current node, or pressing a cancel key (Esc/C) clears `_auto_dest`.

In today's map every node interrupts, so in practice each click advances one node toward D and stops — the multi-hop value is **"click roughly where you want to go and it auto-picks the fork toward it,"** without needing to target the exact adjacent node.

> **Touch:** native touch (tap = travel, one-finger drag = pan, two-finger pinch = the new `_cam_zoom`, two-finger pan) is added per **Spec E (`2026-06-02-touch-mobile-input-design.md`)**, feeding the same intent layer as the mouse rules below. `emulate_mouse_from_touch` is off; touch and mouse share the downstream `_try_click_travel`/pan/zoom logic.

## 2. Input handling (`_unhandled_input` + helpers)

**Single click-vs-pan rule** (resolves the press/motion/release ambiguity):
- **On left press:** if `_input_blocked()`, ignore. Else record the press position; set `_panning = false` and a `_press_active = true` flag. No travel yet.
- **On motion while `_press_active`:** once cumulative movement exceeds `CLICK_SLOP` px, set `_panning = true` and pan for the rest of the gesture (§4). (Panning begins *mid-gesture*; there is no separate release-distance test.)
- **On left release:** if `_press_active` and `_panning` was **never** entered → it's a **click** at the release position (hit-test below). Otherwise it was a pan — no click. Clear `_press_active`.
- **`InputEventMouseMotion` with no button held:** update `_hover` = nearest node within `CLICK_PAD` of the cursor (highlight + detail).
- Clicks act only when `_nav == AT_NODE`; clicks during `TRAVELING` are ignored (v1).

**Hit tolerance:** one named constant `CLICK_PAD := NODE_R + 4`, reused for **both** hover and click hit-tests (no separate literals).

**Hit-testing (main map):** for a click at `m`, a node `(tier,i)` is hit if `m.distance_to(_w2s(_node_world_pos(tier,i))) <= CLICK_PAD`. Accept only **forward-reachable** hits (a path exists current→hit, §3); a click on a visited/behind/unreachable node is a no-op (or just recenters).

## 3. Pathfinding (session-local, no state)

The map is a layered DAG (tier `t` connects only to `t+1`). `_next_hop_toward(D) -> Dictionary` finds the **next hop** toward `D = (dt, di)`:
- **BFS seed:** normally the single current node `(ct, ci)`. When `_at_start` (the virtual start node has no `map_data` entry), seed the frontier with **all tier-0 reachable indices** from `get_reachable_indices()`; a clicked tier-0 node is then its own first hop.
- BFS forward over `map_data[tier][i]["connections"]`; on reaching `D`, record the **first edge** taken on a shortest successful path. Ties broken by lowest index (deterministic).
- Returns that first-hop node `{tier,index}` (a `_targets`-style dict), or `{}` if no forward path exists (then the click is rejected).

**Applying the hop to `_sel`:** `_sel` is an int index into `_targets` (the rebuilt reachable-next list), **not** a node dict. After `_next_hop_toward` returns node `H`, the travel loop locates `H` within the freshly-rebuilt `_targets` (`_anchor_to_current` populates it) and sets `_sel` to that index, then calls `_begin_travel()`. If `H` is not present in `_targets` (shouldn't occur — it is by construction a reachable next node), abort and clear `_auto_dest`.

## 4. Camera pan & recenter

- **Single authority:** a `_panning: bool` flag is the *only* gate; `_cam_user: float` is merely the target x and is meaningful **only while `_panning`**. `_update_camera` tests `if _panning:` → lerp toward `clampf(_cam_user, 0, world_w - PLAY_W)`; else it follows the avatar as today. (No `NAN`/`is_nan` sentinel.)
- While dragging, `_cam_user` is set from the **horizontal** drag delta (main map) or the minimap cursor-x; the **vertical** component is ignored (the camera is horizontal-only — `_cam_x`).
- **Recenter** (`_panning = false`, resume avatar-follow) fires on: travel beginning, **`_arrive()`** (the moment a node is reached — independent of any popup closing later), or a recenter key (Space) / double-click on empty space.
- Minimap drag maps cursor-x within the minimap's inner rect back to `_cam_user` (inverse of the viewport-indicator math at L511–514).

## 5. Minimap interactivity (`_draw_minimap` already renders it)

- **Click a minimap node:** inverse of `mm(tier,idx)` (L497–501) — hit-test the click against each minimap node position (`radius ~5`). If the node is forward-reachable, set `_auto_dest` and travel toward it (same path as a main-map click). If not reachable, pan the camera to centre that tier.
- **Drag on minimap:** pan (as §4).
- The minimap's camera-viewport box already shows where you are; it now doubles as a route planner.

## 6. Visual feedback (`_draw`)

- Highlight `_hover` node with a ring (distinct from the reachable pulse and the `_sel` white ring).
- When `_auto_dest` is set and multi-hop, optionally draw a faint line/marker on the path toward it (reusing the lit-edge style at L418).
- Show the hovered node's detail via the existing `_update_node_detail` path (so hover, not just selection, previews a node).

## 7. Integration seams (all in `level_select.gd`)

- `_unhandled_input` — add mouse button/motion branches (keep the key branch).
- New: `_node_at_screen(pos) -> Dictionary`, `_minimap_node_at(pos) -> Dictionary`, `_next_hop_toward(dest) -> Dictionary`, `_try_click_travel(dest)`, pan helpers.
- `_process` — drive the multi-hop loop: when `AT_NODE`, not blocked, and `_auto_dest` set, begin the next hop (mirrors the held-→ check at L373–375).
- `_anchor_to_current` — if `_auto_dest` reached, clear it; else it stays for the next leg (within the same scene session).
- `_update_camera` — honour `_cam_user` when panning.
- `_draw` / `_draw_minimap` — `_hover` ring, optional path marker; minimap stays as-is for rendering.
- State vars: `_auto_dest`, `_hover`, `_cam_user` (float, valid only when panning), `_panning` (bool), `_press_active` + press position for the click/drag rule. Constants: `CLICK_PAD`, `CLICK_SLOP`.

## 8. Edge cases

- Click while a popup/menu is open: blocked — the dim `ColorRect` overlays already swallow clicks (`MOUSE_FILTER_STOP`), and `_input_blocked()` guards the rest.
- Click during travel: ignored in v1 (avatar finishes the current edge).
- Click the current/visited node: no-op or recenter.
- `_at_start` (virtual start node): clicks pick among the tier-0 targets exactly like the keyboard path.
- Auto-dest cleared on any scene change (it's session-local) — returning from a battle starts fresh.

## 9. Scope boundary

In scope: mouse input, hit-testing, multi-hop next-hop pathing, camera pan/recenter, minimap clicks, hover detail — **all within `level_select.gd`**. Out of scope: any `GameManager` change, cross-scene travel persistence, changing node handlers or the graph, touching the autobattler.

## 10. Testing

`tools/smoke_test.sh` boots. Manual: click an adjacent node → walk + trigger; click a node two tiers ahead → avatar heads that way, auto-picking the fork, stops at the next node; resolve, click again → continues. Click a reachable minimap node → travels. Drag the map/minimap → camera pans; travel/recenter snaps back. Keyboard nav still works. Open a popup → map clicks do nothing.

## Resolved (was open)

Hop model **multi-hop, stop at interrupting nodes**; **session-local** (no GameManager/save state); minimap **clickable + drag-to-pan**; keyboard **kept**.
