extends RefCounted
# Regression tests for GameManager logic. These pin CURRENT behaviour so the
# upcoming hero-tree / SAP / deck refactor can't silently break the contracts.
# Each test instantiates a fresh GameManager copy (autoloads aren't loaded under
# `--script`, so we drive our own instance).

const GM := preload("res://src/game_manager.gd")

func _fresh() -> Node:
	var gm: Node = GM.new()
	gm.reset()
	return gm

# --- determinism -----------------------------------------------------------

func test_elite_modifier_deterministic(t) -> void:
	var gm := GM.new()
	t.eq(gm.elite_modifier(3), gm.elite_modifier(3), "elite_modifier(3) stable across calls")
	t.has(gm.ELITE_MODIFIERS, gm.elite_modifier(5), "result is a known modifier id")

func test_recruit_candidates_deterministic_and_shaped(t) -> void:
	var gm := GM.new()
	var a: Array = gm.recruit_candidates(2, 1)
	var b: Array = gm.recruit_candidates(2, 1)
	t.eq(a, b, "recruit_candidates(2,1) deterministic")
	t.between(a.size(), 2, 3, "offers 2-3 candidates")
	if a.size() > 0:
		t.has(a[0], "type", "candidate has type")
		t.has(a[0], "sway", "candidate has sway")

# --- hero progression (current model; refactor must keep level-up working) --

func test_hero_levels_up_and_scales(t) -> void:
	var gm := _fresh()
	gm.select_hero("knight_captain")
	t.eq(gm.hero_level, 1, "hero starts level 1")
	t.approx(gm.hero_fight_mult(), 1.0, 0.0001, "level-1 fight mult is 1.0")
	for i in range(GM.HERO_XP_PER_LEVEL):
		gm.hero_gain_xp()
	t.eq(gm.hero_level, 2, "levels up after HERO_XP_PER_LEVEL wins")
	t.gt(gm.hero_fight_mult(), 1.0, "fight mult grows with level")

func test_hero_perk_helpers(t) -> void:
	var gm := _fresh()
	gm.select_hero("knight_captain")
	t.ok(not gm.has_perk("thrifty"), "no perk before granting")
	gm.grant_hero_perk("thrifty")
	t.ok(gm.has_perk("thrifty"), "thrifty granted")

# --- events / roster -------------------------------------------------------

func test_event_lose_unit_keeps_last(t) -> void:
	var gm := _fresh()
	while gm.player_roster.size() > 1:
		gm.player_roster.remove_at(0)
	gm.apply_event_choice({"effect": {"lose_unit": true}})
	t.eq(gm.player_roster.size(), 1, "lose_unit never drops the last troop")

func test_event_lose_unit_takes_weakest(t) -> void:
	var gm := _fresh()
	var before: int = gm.player_roster.size()
	gm.player_roster[1]["hp"] = 1   # make slot 1 the weakest
	gm.apply_event_choice({"effect": {"lose_unit": true}})
	t.eq(gm.player_roster.size(), before - 1, "lose_unit removes one troop")

func test_event_explore_resolves(t) -> void:
	var gm := _fresh()
	var before: int = gm.player_roster.size()
	var msg: String = gm.apply_event_choice({"effect": {"explore": true}})
	t.ne(msg, "", "explore returns a result message")
	t.ok(gm.player_roster.size() <= before, "explore never grows the roster")

func test_pit_resolve_keeps_cap_and_levels(t) -> void:
	var gm := _fresh()
	gm.player_roster[0]["type"] = "soldier"
	gm.player_roster[0]["upgrades"] = ["veteran"]
	var size_before: int = gm.player_roster.size()
	gm.resolve_pit(0, "archer", true)   # recruit wins
	t.eq(gm.player_roster.size(), size_before, "pit keeps the roster size (one in, one out)")
	t.eq(String(gm.player_roster[0]["type"]), "archer", "winner (recruit) takes the slot")
	t.eq(gm.unit_level(gm.player_roster[0]), 2, "survivor gains a level")
	t.ok((gm.player_roster[0]["upgrades"] as Array).has("veteran"), "survivor absorbs the loser's upgrades")

# --- map generation --------------------------------------------------------

func test_map_structure(t) -> void:
	var gm := _fresh()
	t.between(gm.map_data.size(), 12, 15, "12-15 tiers")
	t.between(gm.map_data[0].size(), 2, 3, "tier 0 has 2-3 starting nodes")
	for nd in gm.map_data[0]:
		t.eq(String(nd["type"]), "gain_unit", "every tier-0 node is a recruit (never open a fight alone)")
	var last: int = gm.map_data.size() - 1
	t.eq(gm.map_data[last].size(), 1, "final tier is a single boss")
	t.eq(String(gm.map_data[last][0]["type"]), "elite_battle", "boss node is elite_battle")

func test_node_balance_no_econ_clustering(t) -> void:
	# No two consecutive middle tiers should both contain a shop/heal (#12).
	var gm := _fresh()
	var prev_econ := false
	for tier in range(1, gm.map_data.size() - 1):
		var econ := false
		for nd in gm.map_data[tier]:
			var ty := String(nd["type"])
			if ty == "shop" or ty == "heal":
				econ = true
		t.ok(not (econ and prev_econ), "tier %d not back-to-back shop/rest" % tier)
		prev_econ = econ

# --- battle odds heuristic --------------------------------------------------

func test_battle_odds_label(t) -> void:
	var gm := _fresh()
	gm.select_hero("knight_captain")
	var label := String(gm.battle_odds(1, false, "fight"))
	t.ok(label in ["Favorable", "Even", "Risky", "Dire"], "odds is a known label, got '%s'" % label)

# --- save / load round-trip -------------------------------------------------

func test_save_load_roundtrip(t) -> void:
	var gm := _fresh()
	gm.select_hero("bard")
	gm.gold = 42
	gm.save_run()
	gm.gold = 0
	var loaded: bool = gm.load_run()
	t.ok(loaded, "load_run succeeds")
	t.eq(gm.gold, 42, "gold restored from save")
	t.eq(gm.selected_hero, "bard", "hero restored from save")
	gm.clear_run()

func test_run_seed_set_and_persisted(t) -> void:
	var gm := _fresh()
	t.ne(gm.run_seed, 0, "reset() assigns a run seed")
	var seed_before: int = gm.run_seed
	gm.select_hero("knight_captain")
	gm.save_run()
	gm.run_seed = 0
	gm.load_run()
	t.eq(gm.run_seed, seed_before, "run_seed restored from save")
	gm.clear_run()
