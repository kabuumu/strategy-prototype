extends RefCounted
# Branch B only — exercises the front-vs-front controller + single-pet model
# without needing the full scene/visual loop. Validates that only the frontmost
# unit engages, the rest hold, and the next steps up when a front faints.

const RTUnit := preload("res://src/rtbattle/rt_unit.gd")
const AB := preload("res://src/autobattler/autobattler.gd")

func _unit(hp: int) -> RTUnit:
	var u := RTUnit.new()
	u.hp = hp
	u.max_hp = hp
	return u

func test_only_front_engages_rest_hold(t) -> void:
	var ab = AB.new()
	var f0 := _unit(50); var f1 := _unit(50)   # player line, f0 = front
	var e0 := _unit(50); var e1 := _unit(50)   # enemy line, e0 = front
	var team := [f0, f1]
	var foes := [e0, e1]
	ab._front_engage(team, foes)
	t.eq(f0.holding, false, "player front is engaged")
	t.eq(f0.order, RTUnit.Order.ATTACK, "front has an attack order")
	t.eq(f0.attack_target, e0, "front targets enemy front")
	t.eq(f1.holding, true, "player backline holds")
	ab.free()
	f0.free(); f1.free(); e0.free(); e1.free()

func test_next_steps_up_when_front_faints(t) -> void:
	var ab = AB.new()
	var f0 := _unit(50); var f1 := _unit(50)
	var e0 := _unit(50)
	var team := [f0, f1]
	var foes := [e0]
	ab._front_engage(team, foes)
	t.eq(f1.holding, true, "backline initially holds")
	# Front faints -> in real combat _on_unit_died erases it; simulate by hp=0 + removal.
	f0.hp = 0
	team.erase(f0)
	ab._front_engage(team, foes)
	t.eq(f1.holding, false, "next unit steps up to the front")
	t.eq(f1.attack_target, e0, "new front targets the enemy front")
	ab.free()
	f0.free(); f1.free(); e0.free()

func test_regiment_visual_and_flat_damage_flag(t) -> void:
	# Front-vs-front keeps a cosmetic 10-sprite squad (one culls per ~10% HP)
	# but flags flat damage so a wounded unit still hits full.
	var u := RTUnit.new()
	u.setup("soldier", 0, Vector2(100, 100), {
		"name": "Soldier", "sprite_key": "soldier",
		"soldier_count": 10, "hp_per_soldier": 12,
		"damage_per_attack": 20, "attack_cooldown": 1.0,
		"attack_range_px": 60.0, "move_speed_px": 60.0,
		"flat_damage": true,
	})
	t.eq(u.soldier_count, 10, "keeps a 10-sprite squad")
	t.eq(u.alive_soldier_count(), 10, "all 10 sprites alive at full HP")
	t.eq(u.max_hp, 120, "max_hp = 10 * hp_per_soldier")
	t.eq(u.flat_damage, true, "flat_damage flag set")
	u.free()

func test_held_unit_does_nothing_on_tick(t) -> void:
	var u := _unit(50)
	u.holding = true
	var fired: Dictionary = u.tick(0.1, [])
	t.eq(bool(fired.get("fired", false)), false, "held unit does not fire")
	u.free()
