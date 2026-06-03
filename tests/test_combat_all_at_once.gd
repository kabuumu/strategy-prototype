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
