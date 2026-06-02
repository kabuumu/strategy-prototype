extends RefCounted
# Spec A — hero skill tree, slice 1: XP banking + levels + skill points.
# Pure in-memory logic (no meta.cfg writes), so these don't touch real progression.

const GM := preload("res://src/game_manager.gd")

func _gm_with_hero(id: String) -> Node:
	var gm: Node = GM.new()
	gm.selected_hero = id   # has_hero() = selected_hero != "" and HEROES.has(id)
	return gm

func test_award_xp_banks_per_hero(t) -> void:
	var gm := _gm_with_hero("bard")
	gm.hero_award_xp(25)
	t.eq(gm.hero_banked_xp(), 25, "xp banked for selected hero")
	gm.hero_award_xp(5)
	t.eq(gm.hero_banked_xp(), 30, "xp accumulates")
	t.eq(gm.hero_banked_xp("knight_captain"), 0, "other hero's bank is independent")

func test_award_xp_no_hero_is_noop(t) -> void:
	var gm: Node = GM.new()
	gm.selected_hero = ""
	gm.hero_award_xp(10)
	t.eq(gm.hero_banked_xp(), 0, "no hero -> nothing banked")

func test_level_cost_escalates(t) -> void:
	var gm: Node = GM.new()
	t.eq(gm.hero_level_cost(1), 10, "1->2 costs 10")
	t.eq(gm.hero_level_cost(2), 20, "2->3 costs 20")
	t.eq(gm.hero_level_cost(5), 50, "5->6 costs 50")

func test_buy_level_spends_xp_and_grants_point(t) -> void:
	var gm := _gm_with_hero("bard")
	t.eq(gm.hero_meta_level(), 1, "starts at level 1")
	t.eq(gm.hero_unspent_points(), 0, "no points at level 1 (pure earn, no baseline)")
	gm.hero_award_xp(10)
	t.eq(gm.hero_buy_level(), true, "buys a level with enough xp")
	t.eq(gm.hero_meta_level(), 2, "now level 2")
	t.eq(gm.hero_banked_xp(), 0, "xp was spent")
	t.eq(gm.hero_unspent_points(), 1, "one skill point granted")

func test_buy_level_insufficient_xp(t) -> void:
	var gm := _gm_with_hero("bard")
	gm.hero_award_xp(5)   # 1->2 needs 10
	t.eq(gm.hero_buy_level(), false, "not enough xp -> no purchase")
	t.eq(gm.hero_meta_level(), 1, "still level 1")
	t.eq(gm.hero_banked_xp(), 5, "xp untouched")
