extends RefCounted
# Spec B — Card deck, slice 1: deck economy (seed/draw/play/reward) + persistence.

const GM := preload("res://src/game_manager.gd")

func _deck_hero(seed_val: int) -> Node:
	var gm: Node = GM.new()
	gm.selected_hero = "bard"
	gm.run_seed = seed_val
	gm.cards_init_run()
	return gm

func test_init_seeds_deck_and_draws_hand(t) -> void:
	var gm := _deck_hero(999)
	t.eq(gm.card_hand.size(), 5, "opening hand = base cap 5")
	t.eq(gm.card_deck.size() + gm.card_hand.size(), 8, "8 cards seeded in total")
	for id in gm.card_hand:
		t.eq(gm.card_def(id).is_empty(), false, "hand card '%s' is a known pool card" % id)

func test_init_deterministic(t) -> void:
	var a := _deck_hero(4242)
	var b := _deck_hero(4242)
	t.eq(a.card_hand, b.card_hand, "same run_seed -> same opening hand")
	t.eq(a.card_deck, b.card_deck, "same run_seed -> same draw pile")

func test_no_hero_means_empty_deck(t) -> void:
	var gm: Node = GM.new()
	gm.selected_hero = ""
	gm.cards_init_run()
	t.eq(gm.card_hand.size(), 0, "no hero -> no deck (campaign-only)")

func test_play_moves_card_to_graveyard(t) -> void:
	var gm := _deck_hero(7)
	var id := String(gm.card_hand[0])
	t.eq(gm.card_play(0), id, "play returns the front hand card id")
	t.eq(gm.card_hand.size(), 4, "hand shrinks by one")
	t.eq(gm.card_graveyard.has(id), true, "played card is in the graveyard")

func test_reward_draft_is_deterministic_and_addable(t) -> void:
	var gm := _deck_hero(55)
	var a: Array = gm.card_reward_choices(3)
	t.eq(a.size(), 3, "3-card reward offer")
	t.eq(a, gm.card_reward_choices(3), "reward offer stable for the same battles_won")
	var before: int = gm.card_deck.size()
	gm.card_take_reward(String(a[0]))
	t.eq(gm.card_deck.size(), before + 1, "drafted card added to the draw pile")

func test_deck_persists_through_save_load(t) -> void:
	var gm: Node = GM.new()
	gm.reset()
	gm.selected_hero = "bard"
	gm.run_seed = 321
	gm.cards_init_run()
	var hand_before: Array = gm.card_hand.duplicate()
	gm.save_run()
	gm.card_hand = []
	gm.card_deck = []
	gm.load_run()
	t.eq(gm.card_hand, hand_before, "hand restored from the run save")
	gm.clear_run()

func test_grant_battle_reward_grows_deck(t) -> void:
	var gm := _deck_hero(88)
	var before: int = gm.card_deck.size()
	var id: String = gm.card_grant_battle_reward()
	t.ne(id, "", "a reward card was granted on the win")
	t.eq(gm.card_deck.size(), before + 1, "deck grew by one")
