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
