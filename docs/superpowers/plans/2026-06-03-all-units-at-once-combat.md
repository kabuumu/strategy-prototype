# All-units-at-once combat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the front-vs-front 1v1 gauntlet with the original all-at-once field melee — every unit fights simultaneously, the hero waits in reserve, the villain flees when its host collapses, alive-ratio damage, 1× default speed.

**Architecture:** Surgical edits to `src/autobattler/autobattler.gd` (engagement controller, spawn-holding roles, hero reserve, villain-flee rework, speed) plus a one-method extraction in `src/rtbattle/rt_unit.gd` for testable damage. A new headless test file replaces the old front-vs-front test. Docs synced across the four assistant instruction files.

**Tech Stack:** Godot 4.4, GDScript. Dependency-free test harness (`tests/framework.gd` + `tests/run_tests.gd`).

**Spec:** `docs/superpowers/specs/2026-06-03-all-units-at-once-combat-design.md`

---

## File structure

- `src/autobattler/autobattler.gd` — engagement (`_auto_target`, new `_assign_targets`, delete `_front_engage`), spawn-holding roles, `_only_hero_left`, `_untargetable` hero clause, villain flee (`_villain_should_flee`, `_enemy_army_start_hp`, `VILLAIN_FLEE_HP_FRAC`), `_speed_scale` defaults, deploy/PREP comments.
- `src/rtbattle/rt_unit.gd` — extract `regiment_damage()` (flat-or-ratio), called by `tick()`.
- `tests/test_combat_all_at_once.gd` — NEW. Replaces `tests/test_combat_front_vs_front.gd` (DELETED).
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md` — combat-section doc sync.

---

### Task 1: All-at-once engagement + hero reserve

**Files:**
- Modify: `src/autobattler/autobattler.gd` (`_auto_target`/`_front_engage` ~1739-1768; `_untargetable` ~242-243; `_spawn_unit` holding line ~1696)
- Delete: `tests/test_combat_front_vs_front.gd`
- Create: `tests/test_combat_all_at_once.gd`

- [ ] **Step 1: Delete the obsolete front-vs-front test**

The `_front_engage` controller it exercises is being removed.

```bash
rm tests/test_combat_front_vs_front.gd tests/test_combat_front_vs_front.gd.uid
```

- [ ] **Step 2: Write the new failing test file**

Create `tests/test_combat_all_at_once.gd`:

```gdscript
extends RefCounted
# All-at-once field melee: every un-held unit fights simultaneously, the hero
# waits in reserve (held + untargetable) until it's the last player unit, and a
# wounded regiment hits weaker. Exercised without the full scene/visual loop.

const RTUnit := preload("res://src/rtbattle/rt_unit.gd")
const AB := preload("res://src/autobattler/autobattler.gd")

func _unit(hp: int) -> RTUnit:
	var u := RTUnit.new()
	u.hp = hp
	u.max_hp = hp
	return u

func test_all_units_engage_at_once(t) -> void:
	var ab = AB.new()
	var f0 := _unit(50); f0.position = Vector2(100, 100)
	var f1 := _unit(50); f1.position = Vector2(120, 200)
	var e0 := _unit(50); e0.position = Vector2(400, 100)
	var e1 := _unit(50); e1.position = Vector2(420, 200)
	ab.player_units = [f0, f1]
	ab.enemy_units = [e0, e1]
	ab._assign_targets(ab.player_units, ab.enemy_units)
	t.eq(f0.order, RTUnit.Order.ATTACK, "f0 engages")
	t.eq(f1.order, RTUnit.Order.ATTACK, "f1 engages too (not held)")
	t.ok(f0.attack_target != null, "f0 has a target")
	t.ok(f1.attack_target != null, "f1 has a target")
	ab.free()
	f0.free(); f1.free(); e0.free(); e1.free()

func test_held_unit_skipped_by_assign(t) -> void:
	var ab = AB.new()
	var h := _unit(50); h.holding = true; h.position = Vector2(100, 100)
	var e := _unit(50); e.position = Vector2(400, 100)
	ab._assign_targets([h], [e])
	t.eq(h.order, RTUnit.Order.IDLE, "held unit gets no attack order")
	ab.free(); h.free(); e.free()

func test_only_hero_left_predicate(t) -> void:
	var ab = AB.new()
	var troop := _unit(50); var hero := _unit(80)
	ab.player_units = [troop, hero]
	ab._hero_unit = hero
	t.eq(ab._only_hero_left(), false, "troop alive -> hero not last")
	troop.hp = 0
	t.eq(ab._only_hero_left(), true, "troop dead -> hero is last")
	ab.free(); troop.free(); hero.free()

func test_hero_released_when_last_player_unit(t) -> void:
	var ab = AB.new()
	var troop := _unit(50); var hero := _unit(80)
	ab.player_units = [troop, hero]
	ab._hero_unit = hero
	hero.holding = true
	ab._auto_target(1.0)
	t.eq(hero.holding, true, "hero holds while a troop is alive")
	troop.hp = 0
	ab._auto_target(1.0)
	t.eq(hero.holding, false, "hero released as the last player unit")
	ab.free(); troop.free(); hero.free()

func test_reserve_hero_untargetable_until_released(t) -> void:
	var ab = AB.new()
	var hero := _unit(80)
	ab._hero_unit = hero
	ab._villain_boss = false
	hero.holding = true
	t.eq(ab._untargetable(hero), true, "reserve hero is untargetable")
	hero.holding = false
	t.eq(ab._untargetable(hero), false, "released hero is targetable")
	ab.free(); hero.free()

func test_held_unit_does_nothing_on_tick(t) -> void:
	var u := _unit(50); u.holding = true
	var fired: Dictionary = u.tick(0.1, [])
	t.eq(bool(fired.get("fired", false)), false, "held unit does not fire")
	u.free()
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `tools/run_tests.sh`
Expected: FAIL — `_assign_targets` and `_only_hero_left` don't exist yet (parse/lookup errors on the new methods).

- [ ] **Step 4: Replace the engagement controller**

In `src/autobattler/autobattler.gd`, replace the `_auto_target` / `_frontmost_alive` / `_front_engage` block (currently ~1739-1768):

```gdscript
func _auto_target(delta: float) -> void:
	_ai_timer -= delta
	if _ai_timer > 0.0:
		return
	_ai_timer = AI_RETARGET_PERIOD
	# Branch B — front-vs-front: only each team's frontmost-alive unit fights;
	# everyone else holds. When a front faints, the next in line steps up.
	_front_engage(player_units, enemy_units)
	_front_engage(enemy_units, player_units)

# Frontmost still-alive unit of a team. Live arrays are kept in formation order
# (index 0 = front) and compacted by _on_unit_died, so the first alive entry is
# the current front.
func _frontmost_alive(team: Array) -> RTUnit:
	for u: RTUnit in team:
		if is_instance_valid(u) and u.is_alive():
			return u
	return null

func _front_engage(team: Array, foes: Array) -> void:
	var front: RTUnit = _frontmost_alive(team)
	var foe_front: RTUnit = _frontmost_alive(foes)
	for u: RTUnit in team:
		if not (is_instance_valid(u) and u.is_alive()):
			continue
		if u == front and foe_front != null:
			u.holding = false
			u.order_attack(foe_front)
		else:
			u.holding = true
```

with:

```gdscript
func _auto_target(delta: float) -> void:
	_ai_timer -= delta
	if _ai_timer > 0.0:
		return
	_ai_timer = AI_RETARGET_PERIOD
	# All-at-once field melee: every un-held unit on both teams seeks the nearest
	# targetable enemy and fights simultaneously. Release the reserve hero the
	# moment it's the last player unit standing so the general fights its last stand.
	if _hero_unit != null and is_instance_valid(_hero_unit) and _hero_unit.holding and _only_hero_left():
		_hero_unit.holding = false
	_assign_targets(player_units, enemy_units)
	_assign_targets(enemy_units, player_units)

# Frontmost still-alive unit of a team (live arrays stay in formation order,
# index 0 = front, compacted by _on_unit_died). Used by the villain-flee check.
func _frontmost_alive(team: Array) -> RTUnit:
	for u: RTUnit in team:
		if is_instance_valid(u) and u.is_alive():
			return u
	return null

# True when no player unit other than the hero is still alive — the cue to release
# the reserve hero into the fight.
func _only_hero_left() -> bool:
	for u: RTUnit in player_units:
		if u == _hero_unit:
			continue
		if is_instance_valid(u) and u.is_alive():
			return false
	return true

# Assign every alive, un-held attacker to the nearest targetable enemy (archers
# favour the backline via _nearest_enemy). Held units — the reserve hero, the
# lurking villain — sit out and are skipped. An existing live attack order is kept
# rather than thrashing every retarget tick.
func _assign_targets(attackers: Array, defenders: Array) -> void:
	for u: RTUnit in attackers:
		if not (is_instance_valid(u) and u.is_alive()) or u.holding:
			continue
		if u.order == RTUnit.Order.ATTACK and u.attack_target != null and u.attack_target.is_alive():
			continue
		var nearest := _nearest_enemy(u, defenders)
		if nearest != null:
			u.order_attack(nearest)
```

- [ ] **Step 5: Extend `_untargetable` to shield the reserve hero**

Replace (~242-243):

```gdscript
func _untargetable(u: RTUnit) -> bool:
	return u.is_villain and not _villain_boss
```

with:

```gdscript
func _untargetable(u: RTUnit) -> bool:
	# The non-boss villain is unfightable. The reserve hero is shielded from enemy
	# targeting (esp. archers' backline-seeking) until it's released into the melee.
	if u.is_villain and not _villain_boss:
		return true
	return u == _hero_unit and u.holding
```

- [ ] **Step 6: Spawn troops/enemies un-held, hero + lurking villain held**

In `_spawn_unit`, replace the holding line (~1696):

```gdscript
	u.holding = true             # held until the front-vs-front controller engages the front
```

with:

```gdscript
	# All-at-once melee: troops + regular enemies engage immediately. The hero waits
	# in reserve (released when it's the last player unit); the non-boss villain
	# lurks (held + untargetable) until it flees. The boss villain fights normally.
	u.holding = bool(card.get("hero", false)) or (bool(card.get("villain", false)) and not _villain_boss)
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `tools/run_tests.sh`
Expected: PASS — all six `test_combat_all_at_once` methods green, rest of the suite still green.

- [ ] **Step 8: Commit**

```bash
git add src/autobattler/autobattler.gd tests/test_combat_all_at_once.gd tests/test_combat_front_vs_front.gd tests/test_combat_front_vs_front.gd.uid
git commit -m "feat(combat): all-units-at-once engagement + hero reserve

Replace the front-vs-front _front_engage controller with _assign_targets
so every un-held unit fights at once. Hold the hero in reserve (and make it
untargetable) until it's the last player unit, then release it. Non-boss
villain spawns held + lurking. Replaces the front-vs-front test."
```

---

### Task 2: Alive-ratio damage

**Files:**
- Modify: `src/rtbattle/rt_unit.gd` (extract `regiment_damage()`, ~299-304 and tick ~459-463)
- Modify: `src/autobattler/autobattler.gd` (`_spawn_unit` flat_damage ~1683-1694)
- Test: `tests/test_combat_all_at_once.gd` (append)

- [ ] **Step 1: Add the failing damage tests**

Append to `tests/test_combat_all_at_once.gd`:

```gdscript
func test_wounded_regiment_hits_weaker(t) -> void:
	var u := RTUnit.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(u)  # in-tree so cull tweens are legal
	u.setup("soldier", 0, Vector2(100, 100), {
		"name": "Soldier", "sprite_key": "soldier",
		"soldier_count": 10, "hp_per_soldier": 12,
		"damage_per_attack": 20, "attack_cooldown": 1.0,
		"attack_range_px": 60.0, "move_speed_px": 60.0,
		"flat_damage": false,
	})
	t.eq(u.regiment_damage(), 20, "full regiment hits full")
	u.take_damage(72)   # 120 -> 48 hp, ~4/10 soldiers alive
	t.ok(u.regiment_damage() < 20, "wounded regiment hits weaker")
	t.ok(u.regiment_damage() >= 1, "damage never drops below 1")
	u.free()

func test_flat_unit_always_hits_full(t) -> void:
	var u := RTUnit.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(u)
	u.setup("soldier", 0, Vector2(100, 100), {
		"name": "Hero", "sprite_key": "soldier", "is_hero": true,
		"soldier_count": 10, "hp_per_soldier": 12,
		"damage_per_attack": 20, "attack_cooldown": 1.0,
		"attack_range_px": 60.0, "move_speed_px": 60.0,
		"flat_damage": false,
	})
	t.eq(u.soldier_count, 1, "hero collapses to a single sprite")
	t.eq(u.regiment_damage(), 20, "hero hits full")
	u.take_damage(60)
	t.eq(u.regiment_damage(), 20, "single-sprite hero still hits full when wounded")
	u.free()
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/run_tests.sh`
Expected: FAIL — `regiment_damage` does not exist.

- [ ] **Step 3: Extract `regiment_damage()` in rt_unit.gd**

After `alive_soldier_count()` (~299-304), add:

```gdscript
# Damage one attack deals before the class-matchup multiplier. Flat units (hero,
# villain, anything flagged flat_damage) always hit full; a regiment scales by the
# fraction of its soldiers still alive, so a battered regiment hits weaker.
func regiment_damage() -> int:
	if flat_damage:
		return damage_per_attack
	return max(1, int(round(damage_per_attack * (float(alive_soldier_count()) / float(soldier_count)))))
```

- [ ] **Step 4: Use it in `tick()`**

Replace the inline scaling block in `tick()` (~456-463):

```gdscript
			# Field melee: damage scales with how many soldiers remain (a battered
			# regiment hits weaker). Front-vs-front (flat_damage): always full —
			# the soldier sprites are cosmetic, culled per ~10% HP for the visual.
			var scaled: int = damage_per_attack
			if not flat_damage:
				scaled = max(1, int(round(
					damage_per_attack * (float(alive_soldier_count()) / float(soldier_count))
				)))
```

with:

```gdscript
			# All-at-once melee: a battered regiment hits weaker (regiment_damage);
			# flat units (hero/villain, single-sprite) always hit full.
			var scaled: int = regiment_damage()
```

- [ ] **Step 5: Flip `flat_damage` off in `_spawn_unit`**

In `src/autobattler/autobattler.gd`, replace the comment+constant (~1683-1686):

```gdscript
	# Front-vs-front: a cosmetic squad of 10 sprites that cull one per ~10% HP
	# lost (keeps the little-army animation), but combat HP is a single pool and
	# the sprite count does NOT scale damage (see flat_damage below).
	stats["soldier_count"] = 10
```

with:

```gdscript
	# A cosmetic squad of 10 sprites that cull one per ~10% HP lost (the little-army
	# animation). Combat HP is a single pool; under the all-at-once melee, damage
	# scales with the surviving-soldier fraction (RTUnit.regiment_damage), so a
	# battered regiment hits weaker. Hero/villain are single-sprite (soldier_count
	# forced to 1 in RTUnit), so their ratio is always 1.0 — they keep hitting full.
	stats["soldier_count"] = 10
```

and replace (~1694):

```gdscript
	stats["flat_damage"] = true  # Branch B: front-vs-front — a wounded unit still hits full
```

with:

```gdscript
	stats["flat_damage"] = false  # all-at-once melee: wounded regiments hit weaker
```

- [ ] **Step 6: Run to verify it passes**

Run: `tools/run_tests.sh`
Expected: PASS — both new damage tests green, whole suite green.

- [ ] **Step 7: Commit**

```bash
git add src/rtbattle/rt_unit.gd src/autobattler/autobattler.gd tests/test_combat_all_at_once.gd
git commit -m "feat(combat): alive-ratio damage for regiments

Extract RTUnit.regiment_damage() and flip flat_damage off so a wounded
regiment hits weaker (the attrition feel). Hero/villain stay single-sprite
so their ratio is 1.0 and they keep hitting full."
```

---

### Task 3: Villain flees when its host collapses

**Files:**
- Modify: `src/autobattler/autobattler.gd` (`VILLAIN_FLEE_HP_FRAC` const near ~17; `_enemy_army_start_hp` var near ~182; `_check_villain_escape`/`_villain_should_flee` ~247-253; capture in `_start_campaign_fight` ~1179)
- Test: `tests/test_combat_all_at_once.gd` (append)

- [ ] **Step 1: Add the failing villain tests**

Append to `tests/test_combat_all_at_once.gd`:

```gdscript
func _villain_node() -> RTUnit:
	var v := _unit(200); v.is_villain = true
	return v

func test_villain_flees_as_last_enemy(t) -> void:
	var ab = AB.new()
	var v := _villain_node(); var e := _unit(50)
	ab.enemy_units = [e, v]
	ab._villain_unit = v
	ab._villain_boss = false
	ab._enemy_army_start_hp = 50
	t.eq(ab._villain_should_flee(), false, "host alive -> villain stays")
	e.hp = 0
	t.eq(ab._villain_should_flee(), true, "last enemy standing -> villain flees")
	ab.free(); v.free(); e.free()

func test_villain_flees_on_low_host_hp(t) -> void:
	var ab = AB.new()
	var v := _villain_node(); var e0 := _unit(100); var e1 := _unit(100)
	ab.enemy_units = [e0, e1, v]
	ab._villain_unit = v
	ab._villain_boss = false
	ab._enemy_army_start_hp = 200
	t.eq(ab._villain_should_flee(), false, "host healthy -> villain stays")
	e0.hp = 10; e1.hp = 30   # 40/200 = 0.20 < 0.25
	t.eq(ab._villain_should_flee(), true, "host routed -> villain flees")
	ab.free(); v.free(); e0.free(); e1.free()

func test_boss_villain_never_flees(t) -> void:
	var ab = AB.new()
	var v := _villain_node()
	ab.enemy_units = [v]
	ab._villain_unit = v
	ab._villain_boss = true
	ab._enemy_army_start_hp = 0
	t.eq(ab._villain_should_flee(), false, "boss villain holds even when alone")
	ab.free(); v.free()
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/run_tests.sh`
Expected: FAIL — `_villain_should_flee` and `_enemy_army_start_hp` don't exist.

- [ ] **Step 3: Add the const**

In `src/autobattler/autobattler.gd`, right after the `AI_RETARGET_PERIOD` const (~17), add:

```gdscript
const VILLAIN_FLEE_HP_FRAC := 0.25  # non-boss villain flees when its host drops below this HP fraction
```

- [ ] **Step 4: Add the tracking var**

Next to `var _villain_boss: bool = false` (~182), add:

```gdscript
var _enemy_army_start_hp: int = 0  # summed max_hp of the non-villain enemy host (villain flee check)
```

- [ ] **Step 5: Rewrite the escape check + add the predicate**

Replace `_check_villain_escape` (~245-253):

```gdscript
# The villain bails when it would be fought (it's the frontmost-alive enemy), but
# only in a normal battle; on the boss node it stands and fights.
func _check_villain_escape() -> void:
	if _villain_boss or _villain_unit == null:
		return
	if not (is_instance_valid(_villain_unit) and _villain_unit.is_alive()) or _villain_unit.is_escaping:
		return
	if _frontmost_alive(enemy_units) == _villain_unit:
		_villain_do_escape()
```

with:

```gdscript
# The villain bails when its side is collapsing (normal battles only); the boss
# villain stands and fights.
func _check_villain_escape() -> void:
	if _villain_unit == null or _villain_unit.is_escaping:
		return
	if not (is_instance_valid(_villain_unit) and _villain_unit.is_alive()):
		return
	if _villain_should_flee():
		_villain_do_escape()

# The non-boss villain flees when, whichever comes first, no non-villain enemy
# remains (it's the last one standing) OR the host's remaining HP has dropped below
# VILLAIN_FLEE_HP_FRAC of its starting total. The boss villain never flees.
func _villain_should_flee() -> bool:
	if _villain_boss or _villain_unit == null:
		return false
	var others_alive: int = 0
	var live_hp: int = 0
	for e: RTUnit in enemy_units:
		if e == _villain_unit or not (is_instance_valid(e) and e.is_alive()):
			continue
		others_alive += 1
		live_hp += e.hp
	if others_alive == 0:
		return true
	if _enemy_army_start_hp > 0 and float(live_hp) / float(_enemy_army_start_hp) < VILLAIN_FLEE_HP_FRAC:
		return true
	return false
```

- [ ] **Step 6: Capture the host's starting HP**

In `_start_campaign_fight`, immediately after the elite-modifier block and before the `# The recurring villain joins...` comment (~1180-1181), insert:

```gdscript
	# Starting HP of the (non-villain) enemy host — the villain flees once the host
	# is routed (see _villain_should_flee). The villain is appended below, so at this
	# point enemy_units holds the regular host only.
	_enemy_army_start_hp = 0
	for u: RTUnit in enemy_units:
		_enemy_army_start_hp += u.max_hp
```

- [ ] **Step 7: Run to verify it passes**

Run: `tools/run_tests.sh`
Expected: PASS — three new villain tests green, suite green.

- [ ] **Step 8: Commit**

```bash
git add src/autobattler/autobattler.gd tests/test_combat_all_at_once.gd
git commit -m "feat(combat): villain flees when its host collapses

Replace the frontmost-enemy escape trigger (meaningless under all-at-once)
with _villain_should_flee: bolt when no non-villain enemy remains OR the host
HP drops below VILLAIN_FLEE_HP_FRAC (0.25). Boss villain never flees."
```

---

### Task 4: Sim speed back to 1×

**Files:**
- Modify: `src/autobattler/autobattler.gd` (`_speed_scale` default ~120; quick-battle epilogue ~1130; `_enter_fight_phase` ~2010-2017)
- Test: `tests/test_combat_all_at_once.gd` (append)

- [ ] **Step 1: Add the failing default-speed test**

Append to `tests/test_combat_all_at_once.gd`:

```gdscript
func test_default_speed_is_1x(t) -> void:
	var ab = AB.new()
	t.approx(ab._speed_scale, 1.0, 0.001, "fights default to 1x speed")
	ab.free()
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/run_tests.sh`
Expected: FAIL — `_speed_scale` defaults to 2.0.

- [ ] **Step 3: Change the var default**

Replace (~120):

```gdscript
var _speed_scale: float = 2.0   # 2x by default — 1x standard felt too slow
```

with:

```gdscript
var _speed_scale: float = 1.0   # 1x default; all-at-once melee resolves fast enough (toggle to 2x in the HUD)
```

- [ ] **Step 4: Change the quick-battle fight epilogue**

Replace (~1127-1133):

```gdscript
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0
	_start_abilities_applied = false
	_speed_scale = 2.0

# ---------------------------------------------------------------------------
# Campaign single-fight (battle_mode "auto")
```

with:

```gdscript
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0
	_start_abilities_applied = false
	_speed_scale = 1.0

# ---------------------------------------------------------------------------
# Campaign single-fight (battle_mode "auto")
```

- [ ] **Step 5: Change the shared FIGHT-start epilogue**

Replace (~2010-2018):

```gdscript
# Shared FIGHT-start epilogue (campaign / duel / pit): start the fight at 2x.
func _enter_fight_phase() -> void:
	phase = Phase.FIGHT
	Music.play("battle")
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0
	_start_abilities_applied = false
	_speed_scale = 2.0
	_rebuild_ui()
```

with:

```gdscript
# Shared FIGHT-start epilogue (campaign / duel / pit): start the fight at 1x.
func _enter_fight_phase() -> void:
	phase = Phase.FIGHT
	Music.play("battle")
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0
	_start_abilities_applied = false
	_speed_scale = 1.0
	_rebuild_ui()
```

- [ ] **Step 6: Run to verify it passes**

Run: `tools/run_tests.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/autobattler/autobattler.gd tests/test_combat_all_at_once.gd
git commit -m "feat(combat): default fight speed back to 1x

All-at-once melee resolves fast enough without the 2x crutch. HUD 1x/2x
toggle unchanged."
```

---

### Task 5: Reframe PREP/deploy comments as spatial placement

**Files:**
- Modify: `src/autobattler/autobattler.gd` (`_deploy_lineup` ~1229-1231; `_player_deploy_positions` ~1260-1262)

No behaviour change — the wedge already produces spatial front/back; only the comments still describe the deleted array-order queue.

- [ ] **Step 1: Rewrite the `_deploy_lineup` header comment**

Replace (~1229-1231):

```gdscript
	# Chosen troops in player order (pool order), then the hero appended LAST so it
	# engages last (front-vs-front steps up by array order) — the general fights
	# only once its screen of troops has fallen.
```

with:

```gdscript
	# Chosen troops in player order (pool order) form the wedge front-to-back; the
	# hero is appended LAST and held in reserve (untargetable) until its troops fall,
	# then released — the general fights only once its screen of troops is gone.
```

- [ ] **Step 2: Rewrite the `_player_deploy_positions` header comment**

Replace (~1260-1262):

```gdscript
# Player team start positions: `troop_count` troops in a forward defensive wedge
# (front-of-order troop is the spearhead), then the hero centred well behind them.
# Returns one Vector2 per deployed unit, troops first then the hero (if any).
```

with:

```gdscript
# Player team start positions: `troop_count` troops in a forward defensive wedge
# (front-of-order troop is the spearhead, so PREP ordering = spatial placement —
# front troops make contact first and tank while ranged troops stay back), then the
# hero centred well behind them. One Vector2 per unit, troops first then the hero.
```

- [ ] **Step 3: Verify nothing broke**

Run: `tools/run_tests.sh`
Expected: PASS (comment-only change).

- [ ] **Step 4: Commit**

```bash
git add src/autobattler/autobattler.gd
git commit -m "docs(combat): reframe PREP ordering comments as spatial placement"
```

---

### Task 6: Sync the combat docs across all four instruction files

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md` (combat-section bullets, the same three sentences in each)

The combat description was stale (it already described all-at-once + alive-ratio); update it to current truth: hero held in reserve + untargetable, villain flees on host-collapse, 1× speed. The four files are kept in sync, so apply each edit to every file that contains the anchor phrase (grep first; whitespace must match).

- [ ] **Step 1: Update the FIGHT bullet**

In each file, find the bullet starting `- **FIGHT is a real-time field melee` and replace its final sentence:

Old:

```
The hero (`is_hero`) is a single sprite holding the whole regiment's HP.
```

New:

```
The hero (`is_hero`) is a single sprite holding the whole regiment's HP, **held in reserve and `_untargetable`** until it's the last player unit alive (`_only_hero_left`), then released. Fights default to **1× speed** (HUD 1×/2× toggle).
```

- [ ] **Step 2: Update the Hero injection bullet**

Replace:

```
the hero is the general behind a forward defensive wedge (`_player_deploy_positions`) and so fights last.
```

with:

```
the hero is the general held in reserve behind a forward defensive wedge (`_player_deploy_positions`), untargetable until its screen of troops falls, then released to fight last. PREP ordering is **spatial placement** — front-of-order troops make contact first and tank.
```

- [ ] **Step 3: Update the villain bullet**

Replace:

```
In normal battles it's untargetable (`_untargetable`) and **teleports away with a taunt** the moment it becomes the frontmost enemy (`_check_villain_escape` → `_villain_do_escape` → `RTUnit.escape()`); periodic lurk-taunts via `_villain_lurk_taunt`.
```

with:

```
In normal battles it lurks held + untargetable (`_untargetable`) and **teleports away with a taunt** the moment its host collapses — no non-villain enemy left OR host HP below `VILLAIN_FLEE_HP_FRAC` (`_check_villain_escape` → `_villain_should_flee` → `_villain_do_escape` → `RTUnit.escape()`); periodic lurk-taunts via `_villain_lurk_taunt`.
```

- [ ] **Step 4: Verify the four files are consistent**

Run: `grep -c "VILLAIN_FLEE_HP_FRAC" CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md`
Expected: `1` for every file that carries the combat section (some siblings may be abbreviated — only edit sections that exist; do not invent them).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md
git commit -m "docs: combat section reflects all-at-once melee + hero reserve + villain flee"
```

---

### Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the unit suite**

Run: `tools/run_tests.sh`
Expected: `N passed, 0 failed` — including every `test_combat_all_at_once` method.

- [ ] **Step 2: Run the smoke test**

Run: `tools/smoke_test.sh`
Expected: every scene boots with no script/parse errors (exit 0).

- [ ] **Step 3: Manual sanity check (if a display is available)**

Open the project in the Godot editor, start a Quick Auto Battle and a Campaign fight, and confirm:
- all troops engage at once (not a single-file duel line);
- wounded regiments visibly shrink and deal less;
- the hero hangs back and only joins once its troops have fallen;
- the villain taunts and teleports as the enemy host is routed;
- the fight runs at 1× by default.

- [ ] **Step 4: Confirm no stray `_front_engage` references remain**

Run: `grep -rn "_front_engage" src/ tests/`
Expected: no matches.

---

## Self-review

**Spec coverage:**
- §1 all-at-once engagement → Task 1 (`_assign_targets`, `_auto_target`, delete `_front_engage`). ✓
- §2 spawn holding roles → Task 1 Step 6. ✓
- §3 hero held until troops expended → Task 1 (`_only_hero_left` + release in `_auto_target`). ✓
- §4 hero untargetable while reserved → Task 1 Step 5. ✓
- §5 villain flee either-first + zero-guard → Task 3 (`_villain_should_flee`, `_enemy_army_start_hp`, const; guard `_enemy_army_start_hp > 0`). ✓
- §6 alive-ratio damage → Task 2 (`regiment_damage`, flat_damage off). ✓
- §7 speed 1× → Task 4 (three sites + comment). ✓
- §8 PREP spatial → Task 5 (comments; behaviour already correct). ✓
- §9 docs + tests → Task 6 (docs ×4) and tests throughout; new `test_combat_all_at_once.gd`. ✓
- Cleanup: `_front_engage` removed, verified Task 7 Step 4. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type/name consistency:** `_assign_targets`, `_only_hero_left`, `_untargetable`, `_villain_should_flee`, `_enemy_army_start_hp`, `VILLAIN_FLEE_HP_FRAC`, `regiment_damage` used consistently across tasks and tests. `_frontmost_alive` is **kept** — after deleting `_front_engage` (Task 1) and the old `_check_villain_escape` call (Task 3) it is still used by the card-targeting code at `autobattler.gd:1343/1377/1381`, so it must not be removed. Verified via `grep -rn "_frontmost_alive"`.
