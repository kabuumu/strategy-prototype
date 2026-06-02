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

# --- slice 2: the node tree (prereqs, ranks, gates, respec) ----------------

func _hero_with_points(id: String, points: int) -> Node:
	var gm := _gm_with_hero(id)
	for i in range(points):
		gm.hero_award_xp(gm.hero_level_cost(gm.hero_meta_level()))
		gm.hero_buy_level()
	return gm

func test_node_requires_point_and_prereq(t) -> void:
	var gm0 := _gm_with_hero("bard")
	t.eq(gm0.hero_can_buy_node("conditioning"), false, "no points -> cannot buy a root")
	var gm := _hero_with_points("bard", 1)
	t.eq(gm.hero_can_buy_node("conditioning"), true, "root buyable with a point")
	t.eq(gm.hero_can_buy_node("honed_blade"), false, "branch node blocked until its prereq is owned")
	t.eq(gm.hero_buy_node("conditioning"), true, "bought the root")
	t.eq(gm.hero_node_rank("conditioning"), 1, "rank 1")
	t.eq(gm.hero_unspent_points(), 0, "the point was spent")
	t.eq(gm.hero_can_buy_node("honed_blade"), false, "prereq now met but no points left")

func test_multi_rank_cap(t) -> void:
	var gm := _hero_with_points("bard", 4)
	t.eq(gm.hero_buy_node("conditioning"), true)
	t.eq(gm.hero_buy_node("conditioning"), true)
	t.eq(gm.hero_buy_node("conditioning"), true)
	t.eq(gm.hero_node_rank("conditioning"), 3, "reached max rank 3")
	t.eq(gm.hero_can_buy_node("conditioning"), false, "cannot exceed max rank")

func test_capstone_gate(t) -> void:
	var gm := _hero_with_points("bard", 4)
	gm.hero_buy_node("conditioning")
	gm.hero_buy_node("honed_blade")
	t.eq(gm.hero_can_buy_node("might_cap"), false, "capstone gated below 3 points in section")
	gm.hero_buy_node("warlord")
	t.eq(gm.hero_points_in_section("might"), 3, "3 points in might")
	t.eq(gm.hero_can_buy_node("might_cap"), true, "capstone unlocks once the gate is met")

func test_respec_drops_level_and_clears_nodes(t) -> void:
	var gm := _hero_with_points("bard", 2)   # level 3, 2 unspent points
	gm.hero_buy_node("conditioning")
	t.eq(gm.hero_meta_level(), 3, "level 3")
	t.eq(gm.hero_respec(), true, "respec succeeds")
	t.eq(gm.hero_meta_level(), 2, "level dropped by 1 (the respec cost)")
	t.eq(gm.hero_node_rank("conditioning"), 0, "all nodes cleared")
	t.eq(gm.hero_unspent_points(), 1, "one point lost permanently (2 -> 1)")

func test_respec_blocked_at_level_1(t) -> void:
	var gm := _gm_with_hero("bard")
	t.eq(gm.hero_respec(), false, "cannot respec below level 1")

# --- slice 3: node-derived stat outputs ------------------------------------

func test_tree_outputs_neutral_without_nodes(t) -> void:
	var gm := _gm_with_hero("bard")
	t.approx(gm.hero_hp_mult_tree(), 1.0, 0.0001, "no nodes -> 1.0 HP mult")
	t.approx(gm.hero_damage_mult_tree(), 1.0, 0.0001, "no nodes -> 1.0 damage mult")
	t.approx(gm.hero_aura_mult_tree(), 1.0, 0.0001, "no nodes -> 1.0 aura mult")
	t.eq(gm.hero_hand_cap(), 5, "base hand cap 5")
	t.eq(gm.hero_trap_slots(), 2, "base trap slots 2")
	t.eq(gm.hero_prep_budget(), 1, "base prep budget 1")
	t.approx(gm.hero_aura_benched_factor(), 0.5, 0.0001, "no Steadfast -> benched auras at 50%")

func test_might_nodes_scale_hp_and_damage(t) -> void:
	var gm := _hero_with_points("bard", 6)
	gm.hero_buy_node("conditioning"); gm.hero_buy_node("conditioning")
	t.approx(gm.hero_hp_mult_tree(), 1.24, 0.0001, "Conditioning x2 -> +24% HP")
	gm.hero_buy_node("honed_blade"); gm.hero_buy_node("honed_blade"); gm.hero_buy_node("honed_blade")
	gm.hero_buy_node("warlord")
	t.approx(gm.hero_damage_mult_tree(), 1.50, 0.0001, "Honed x3 + Warlord -> +50% damage")

func test_tactics_nodes_raise_deck_caps(t) -> void:
	var gm := _hero_with_points("bard", 2)
	gm.hero_buy_node("field_kit"); gm.hero_buy_node("field_kit")
	t.eq(gm.hero_hand_cap(), 7, "Field Kit x2 -> hand cap 7")

func test_steadfast_keeps_auras_when_benched(t) -> void:
	var gm := _hero_with_points("bard", 3)
	gm.hero_buy_node("drillmaster"); gm.hero_buy_node("quartermaster"); gm.hero_buy_node("thrifty")
	t.eq(gm.hero_has_node("thrifty"), true, "Steadfast owned")
	t.approx(gm.hero_aura_benched_factor(), 1.0, 0.0001, "Steadfast -> full auras when benched")
