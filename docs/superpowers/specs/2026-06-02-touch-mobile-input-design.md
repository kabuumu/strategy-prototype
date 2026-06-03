# Touch & Mobile Input — Design

**Date:** 2026-06-02
**Status:** Draft for review
**Author:** Richard Melvin (with Claude)
**Cross-cutting** — threads through Spec C (overworld), Spec D (PREP/AFTERMATH + combat UI), and Spec A (charselect tree). Independent of game logic.

## Goal

Make the game **fully playable by touch** on a tablet/phone in **landscape**, using **native touch events** (`InputEventScreenTouch` / `InputEventScreenDrag`) including **multi-touch gestures** (pinch-zoom, two-finger pan). The viewport is 1280×720 with `canvas_items` stretch, which already scales to any screen — so this is an **input + tap-target** layer, **not** a responsive/portrait redesign.

## Decisions (locked)

| Topic | Decision |
|---|---|
| Mobile scope | **Touch-playable, landscape only.** No portrait, no responsive re-layout. The stretch viewport handles scaling. |
| Input approach | **Full native touch.** Handle `ScreenTouch`/`ScreenDrag` explicitly on every interactive surface; **disable** `emulate_mouse_from_touch` so touch and mouse paths don't double-fire. Mouse handlers (desktop) remain in parallel. |
| Gestures | **Tap**, **one-finger drag** (pan/scroll/card-drag), **two-finger pinch-zoom** and **two-finger pan** on the overworld — all phase 1. |
| Tap targets | All interactive elements sized **≥ 48 px** (finger-friendly); spacing audited on the tree, prep, and node UIs. |

## 1. Shared touch layer

A small reusable helper (a `TouchInput` utility or per-scene handlers following the project's code-built convention) that interprets raw events into intents:
- **Tap** = a `ScreenTouch` press+release with the finger moving < `TAP_SLOP` (≈ 12 px) and < `TAP_TIME` (≈ 300 ms) → a "click" at that position.
- **Drag** = one finger past `TAP_SLOP` → continuous drag deltas.
- **Pinch** = two fingers; track per-`index` positions; zoom factor = `current_distance / start_distance`; midpoint = pan focus.
- **Two-finger pan** = two fingers moving together (low pinch delta) → camera pan.

Track active touches in a `{index: position}` dict (Godot gives each finger an `index`); ignore a 3rd+ finger. Mouse events feed the **same intent layer** so desktop and touch share downstream logic.

## 2. Per-surface behaviour

**Overworld (Spec C):**
- **Tap a node** → travel toward it (reuses C's `_try_click_travel` / `_next_hop_toward`).
- **One-finger drag** → camera pan (replaces/augments C's mouse drag-pan; same `_panning`/`_cam_user` authority).
- **Two-finger pinch** → **camera zoom** — *new*: the overworld gains a `_cam_zoom` (clamped, e.g. 0.6–1.4) applied in `_w2s`/`_draw`; midpoint anchors the zoom. Two-finger drag pans.
- **Tap a minimap node** → travel (reuses C's minimap hit-test). The minimap region must reject the pinch/pan gesture ownership cleanly (gesture started on the minimap = minimap interaction).
- C's `CLICK_SLOP` becomes touch-aware (use `TAP_SLOP` for touch, the tighter mouse value for mouse).

**PREP / AFTERMATH + combat UI (Spec D):**
- **Tap** a card to select; **drag** a card onto a lineup Troop / hero / Trap slot to play it (`ScreenDrag` with a drag-ghost).
- **Drag** Troops to **reorder the lineup** / move between lineup and bench.
- Confirm / phase buttons are ≥ 48 px.

**Charselect tree (Spec A):**
- **Tap** a node to buy/rank it; **tap** "Buy level" / "Respec".
- **One-finger drag / flick** to scroll the 4-section tree if it overflows the screen (momentum optional, phase 2).
- Node hit-targets ≥ 48 px (the CK3 diamonds are drawn in code — size accordingly).

**General UI:** all `Button`s already accept touch via tap; just ensure sizing/spacing.

## 3. Project settings

- `display/window/handheld/orientation = landscape`.
- `input_devices/pointing/emulate_mouse_from_touch = false` (we handle native touch).
- `input_devices/pointing/emulate_touch_from_mouse = false`.
- Confirm the web export shell allows touch + viewport meta (the CI's COOP/COEP shell — ensure `<meta name="viewport">` is mobile-friendly, no user-scalable zoom fighting our pinch).

## 4. Integration seams

- **New:** shared touch-intent helper (utility script or mixin), used by `level_select.gd`, `autobattler.gd`, `charselect.gd`.
- `src/level_select/level_select.gd` — add `ScreenTouch`/`ScreenDrag` branches in `_unhandled_input`; `_cam_zoom` + pinch in `_update_camera`/`_w2s`/`_draw`/`_draw_minimap`; gesture ownership (map vs minimap vs HUD).
- `src/autobattler/autobattler.gd` — touch drag-and-drop in the PREP/AFTERMATH card UI + lineup reorder (Spec D).
- `src/charselect/charselect.gd` — tap-to-buy + drag-scroll on the tree (Spec A).
- `project.godot` — the §3 settings.
- **Tap-target audit** across all three UIs (≥ 48 px).

## 5. Phasing

- **Phase 1:** native tap + one-finger drag (pan/scroll/card-drag) + two-finger pinch-zoom & pan on the overworld; tap targets ≥ 48 px; project settings; parity with mouse on every surface.
- **Phase 2:** momentum/inertial scrolling, long-press tooltips, haptic-style affordances, polish.

## 6. Testing

- Web export opened on a touchscreen (or browser device-emulation): tap a node to travel; pinch to zoom the overworld; drag a card onto a Troop in PREP; reorder the lineup; tap tree nodes to spend points; all buttons reachable with a finger. Desktop mouse still works unchanged (no double-fire with emulate disabled).

## Resolved (was open)

Scope = **touch-playable landscape** (no portrait/responsive); approach = **full native touch** incl. **pinch-zoom from phase 1**; `emulate_mouse_from_touch` **off**.
