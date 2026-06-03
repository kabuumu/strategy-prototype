extends RefCounted
# Spec B — Card effect resolution applied to a unit (RTUnit.apply_effect).

const RTUnit := preload("res://src/rtbattle/rt_unit.gd")

func _unit() -> RTUnit:
	var u := RTUnit.new()
	u.max_hp = 100
	u.hp = 100
	u.damage_per_attack = 20
	u.attack_cooldown = 1.0
	u.attack_range_px = 60.0
	return u

func test_hp_pct(t) -> void:
	var u := _unit()
	u.apply_effect({"kind": "hp_pct", "value": 0.5})
	t.eq(u.max_hp, 150, "+50% max HP")
	t.eq(u.hp, 150, "topped up to the new max")
	u.free()

func test_damage_pct(t) -> void:
	var u := _unit()
	u.apply_effect({"kind": "damage_pct", "value": 0.5})
	t.eq(u.damage_per_attack, 30, "+50% damage")
	u.free()

func test_cooldown_pct(t) -> void:
	var u := _unit()
	u.apply_effect({"kind": "cooldown_pct", "value": -0.25})
	t.approx(u.attack_cooldown, 0.75, 0.0001, "-25% attack cooldown")
	u.free()

func test_ranged(t) -> void:
	var u := _unit()
	u.apply_effect({"kind": "ranged"})
	t.ge(u.attack_range_px, 200.0, "gains ranged reach")
	t.eq(u.is_ranged, true, "ranged flag set")
	u.free()

func test_heal(t) -> void:
	var u := _unit()
	u.hp = 40
	u.apply_effect({"kind": "heal_pct", "value": 0.3})
	t.eq(u.hp, 70, "heal 30% of max HP")
	u.apply_effect({"kind": "heal_full"})
	t.eq(u.hp, 100, "heal to full")
	u.free()
