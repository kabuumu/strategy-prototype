# AGENTS.md

Cross-tool agent guidance for this repository (Codex and any tool that reads `AGENTS.md`). The fullest version lives in **`CLAUDE.md`** — read it for complete architecture notes. Siblings: `.github/copilot-instructions.md`, `GEMINI.md`. **Keep all four in sync.**

**You may create or edit any file in this codebase** — no read-only area; make the changes the task needs.

## Project

Godot **4.4** auto-battler strategy roguelite in **GDScript**. Forward Plus, viewport 1280×720 (`canvas_items` stretch). Main scene `src/title/title.tscn`. Scene flow: `title → charselect → level_select ⇄ autobattler`. The only fight mode is the auto-battler; your roster auto-resolves each encounter.

## Commands / tests (headless, no addon)

```bash
godot --headless --import     # import assets after changing any of them
tools/smoke_test.sh           # boots every scene; fails on any script/parse error
tools/run_tests.sh            # GDScript unit suite under tests/
```
The unit suite is dependency-free: `tests/framework.gd` (assertions) + `tests/run_tests.gd` (a `SceneTree` runner, `godot --headless --script res://tests/run_tests.gd`, that discovers `tests/test_*.gd` and runs each `test_*` method, exiting non-zero on failure). Tests instantiate their own `GameManager` copy because autoloads aren't loaded under `--script`. **Add a `tests/test_*.gd` regression test when changing game logic.**

## How combat actually works (audited 2026-06-02 — common misconception)

`enum Phase { SHOP, PREP, FIGHT, RESULT, REWARD, GAME_OVER }`. **Quick Auto Battle** runs the full **Super-Auto-Pets-style** loop: SHOP team-building (buy / `merge`-to-level `MAX_LEVEL 3` / reorder / sell / freeze / roll over a `TEAM_SIZE = 5` gold hotbar) → FIGHT → RESULT → REWARD. **Campaign battles SKIP SHOP** and go to **PREP** (`_start_campaign_fight`: pick + order a troop lineup, then draw 3 / play 1); duels and the roster-cap pit jump straight to FIGHT. **FIGHT is a front-vs-front engagement** — only each side's frontmost-alive unit fights (others `holding`); when a front faints the next steps up. Units are **regiments** (`max_hp = soldier_count * hp_per_soldier`) using **flat damage**, scaled by a **class wheel** (Infantry > Spearmen > Cavalry > Archers > Infantry, 1.5x/0.7x). The **hero deploys at the BACK** (general behind the troop wedge) with a `null` roster entry; **its death ends the run**. **No troop permadeath on a win** — `_conclude_campaign` keeps the whole pool; a loss calls `clear_run`, and the **roster-cap pit** is the only thing that retires a unit.

## Key conventions

- **All UI is built in code** — no UI nodes in `.tscn`; create every `Label`/`Button`/`ColorRect`/`StyleBoxFlat` programmatically in `_build_ui()`/`_ready()`. Inline `StyleBoxFlat` via `add_theme_stylebox_override` (`_circle_style`, `_btn_style`).
- **All persistent cross-scene state lives on the `GameManager` autoload** (`src/game_manager.gd`). Never store run-state in scene scripts. Use exact lowercase `UNIT_TYPES` keys (`"soldier"`, `"archer"`, `"scout"`).
- Naming: `_build_*` constructs UI, `_refresh_*` updates UI, `_try_*` validates input, `_on_*` are signal callbacks.

## Planned redesign (design-stage, NOT built)

`docs/superpowers/specs/2026-06-02-*.md` hold five specs. The **skill tree**, **card deck**, **SAP/PREP front-vs-front combat** and **aura-based hero** are now built (fight/buff + Valor are gone); only the **point-and-click + touch/mobile overworld** remain design-stage. Reconcile against the code before implementing.
