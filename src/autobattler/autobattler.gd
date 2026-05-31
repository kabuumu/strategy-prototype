extends Node2D

const UITheme := preload("res://src/ui/ui_theme.gd")
const RTUnit := preload("res://src/rtbattle/rt_unit.gd")

const FIELD_RECT: Rect2 = Rect2(40.0, 72.0, 1200.0, 410.0)
const TEAM_SIZE: int = 5
const SHOP_SIZE: int = 3
const BUY_COST: int = 3
const ROLL_COST: int = 1
const SELL_REFUND: int = 1
const GOLD_PER_ROUND: int = 10
const MAX_WINS: int = 5
const START_HEARTS: int = 3
const AI_RETARGET_PERIOD: float = 0.45
const XP_TO_LEVEL: int = 3
const MAX_LEVEL: int = 3
const FIGHT_INTRO_SECONDS: float = 0.75

enum Phase { SHOP, FIGHT, RESULT, GAME_OVER }

const UNIT_TYPES: Dictionary = {
	"soldier": {
		"name": "Infantry",
		"role": "Steady front line",
		"sprite_key": "soldier",
		"soldier_count": 9,
		"hp_per_soldier": 16,
		"damage_per_attack": 8,
		"attack_cooldown": 1.0,
		"attack_range_px": 58.0,
		"move_speed_px": 58.0,
	},
	"archer": {
		"name": "Archers",
		"role": "Long range damage",
		"sprite_key": "archer",
		"soldier_count": 6,
		"hp_per_soldier": 12,
		"damage_per_attack": 9,
		"attack_cooldown": 1.35,
		"attack_range_px": 210.0,
		"move_speed_px": 60.0,
	},
	"scout": {
		"name": "Cavalry",
		"role": "Fast flanker",
		"sprite_key": "scout",
		"soldier_count": 5,
		"hp_per_soldier": 14,
		"damage_per_attack": 10,
		"attack_cooldown": 0.9,
		"attack_range_px": 58.0,
		"move_speed_px": 96.0,
	},
	"healer": {
		"name": "Spearmen",
		"role": "Reach and bulk",
		"sprite_key": "healer",
		"soldier_count": 8,
		"hp_per_soldier": 15,
		"damage_per_attack": 9,
		"attack_cooldown": 1.1,
		"attack_range_px": 82.0,
		"move_speed_px": 54.0,
	},
}

var phase: int = Phase.SHOP
var round_no: int = 1
var wins: int = 0
var hearts: int = START_HEARTS
var gold: int = GOLD_PER_ROUND

var team: Array = []       # Array[Dictionary]
var shop: Array = []       # Array[Dictionary]
var selected_shop: int = -1
var selected_slot: int = -1
var player_units: Array = []
var enemy_units: Array = []

var _ui_nodes: Array = []
var _ai_timer: float = 0.0
var _fight_intro_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _result_text: String = ""
var _shop_message: String = "Buy units into your team. Duplicates merge for XP and stronger fights."
var _fight_label: Label

func _ready() -> void:
	_rng.randomize()
	for _i in range(TEAM_SIZE):
		team.append({})
	_roll_shop(true)
	_rebuild_ui()

func _process(delta: float) -> void:
	if phase != Phase.FIGHT:
		return
	if _fight_intro_timer > 0.0:
		_fight_intro_timer = max(0.0, _fight_intro_timer - delta)
		if _fight_label != null and is_instance_valid(_fight_label):
			_fight_label.text = "AUTO FIGHT starts in %.1fs" % _fight_intro_timer
		queue_redraw()
		return
	if _fight_label != null and is_instance_valid(_fight_label):
		_fight_label.text = "AUTO FIGHT"
	var all_units: Array = []
	all_units.append_array(player_units)
	all_units.append_array(enemy_units)
	_auto_target(delta)
	for u: RTUnit in all_units:
		if u.is_alive():
			u.tick(delta, all_units)
			u.position.x = clamp(u.position.x, FIELD_RECT.position.x + u.radius, FIELD_RECT.end.x - u.radius)
			u.position.y = clamp(u.position.y, FIELD_RECT.position.y + u.radius, FIELD_RECT.end.y - u.radius)
	_check_fight_end()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color(0.055, 0.065, 0.090))
	draw_rect(FIELD_RECT, Color(0.15, 0.20, 0.16))
	draw_line(Vector2(FIELD_RECT.get_center().x, FIELD_RECT.position.y),
			Vector2(FIELD_RECT.get_center().x, FIELD_RECT.end.y), Color(0.90, 0.85, 0.45, 0.22), 2.0)
	if phase == Phase.FIGHT and _fight_intro_timer > 0.0:
		draw_rect(FIELD_RECT, Color(0.02, 0.03, 0.04, 0.22))
	for i in range(TEAM_SIZE):
		var x := 170.0 + float(i) * 105.0
		var slot_color := Color(0.10, 0.12, 0.16)
		if selected_slot == i:
			slot_color = Color(0.26, 0.36, 0.30)
		draw_rect(Rect2(x, 535.0, 86.0, 86.0), slot_color, false, 2.0)
	for i in range(SHOP_SIZE):
		var x := 705.0 + float(i) * 130.0
		var shop_color := Color(0.14, 0.12, 0.16)
		if selected_shop == i:
			shop_color = Color(0.26, 0.22, 0.34)
		draw_rect(Rect2(x, 535.0, 112.0, 86.0), shop_color, false, 2.0)

func _rebuild_ui() -> void:
	for n: Node in _ui_nodes:
		_free_node(n)
	_ui_nodes.clear()

	_add_label("AUTO BATTLER", 28, UITheme.GOLD, Vector2(28.0, 14.0), Vector2(250.0, 36.0))
	_add_label("Round %d   Gold %d   Wins %d/%d   Hearts %d" % [round_no, gold, wins, MAX_WINS, hearts],
			17, UITheme.TEXT, Vector2(300.0, 20.0), Vector2(470.0, 26.0))
	_add_button("Menu", Vector2(1120.0, 16.0), Vector2(104.0, 38.0), UITheme.RED, _on_menu)

	if phase == Phase.SHOP:
		_add_label(_shop_message, 14, UITheme.TEXT_MUTED, Vector2(300.0, 46.0), Vector2(650.0, 22.0))
		_add_label("TEAM", 15, UITheme.TEXT_MUTED, Vector2(170.0, 505.0), Vector2(260.0, 22.0))
		_add_label("SHOP", 15, UITheme.TEXT_MUTED, Vector2(705.0, 505.0), Vector2(260.0, 22.0))
		_add_label("Slot 1 deploys at the front. Swap units to tune the formation.",
				13, UITheme.TEXT_MUTED, Vector2(170.0, 622.0), Vector2(450.0, 20.0))
		for i in range(TEAM_SIZE):
			_add_slot_button(i)
		for i in range(SHOP_SIZE):
			_add_shop_button(i)
		_add_button("Sell +1", Vector2(485.0, 640.0), Vector2(96.0, 42.0), Color(0.34, 0.25, 0.22), _on_sell)
		_add_button("Freeze", Vector2(602.0, 640.0), Vector2(96.0, 42.0), Color(0.22, 0.32, 0.42), _on_freeze)
		_add_button("Roll -1", Vector2(719.0, 640.0), Vector2(110.0, 42.0), Color(0.24, 0.30, 0.42), _on_roll)
		_add_button("Fight", Vector2(946.0, 640.0), Vector2(130.0, 42.0), UITheme.GREEN, _on_fight)
	elif phase == Phase.FIGHT:
		var fight_text := "AUTO FIGHT"
		if _fight_intro_timer > 0.0:
			fight_text = "AUTO FIGHT starts in %.1fs" % _fight_intro_timer
		_fight_label = _add_label(fight_text, 26, UITheme.GOLD, Vector2(500.0, 505.0), Vector2(300.0, 36.0))
		_add_label("Your team fights automatically. Order and levels decide the round.",
				15, UITheme.TEXT_MUTED, Vector2(405.0, 545.0), Vector2(520.0, 24.0))
	elif phase == Phase.RESULT:
		_add_label(_result_text, 42, UITheme.GOLD, Vector2(360.0, 530.0), Vector2(560.0, 56.0))
		_add_label("Your surviving roster returns to the shop. Spend the next round's gold.",
				15, UITheme.TEXT_MUTED, Vector2(380.0, 585.0), Vector2(560.0, 24.0))
		_add_button("Next Shop", Vector2(560.0, 610.0), Vector2(160.0, 46.0), UITheme.BLUE, _on_next_shop)
	elif phase == Phase.GAME_OVER:
		_add_label(_result_text, 42, UITheme.GOLD, Vector2(300.0, 530.0), Vector2(680.0, 56.0))
		_add_button("Restart", Vector2(500.0, 610.0), Vector2(130.0, 46.0), UITheme.GREEN, _on_restart)
		_add_button("Menu", Vector2(650.0, 610.0), Vector2(130.0, 46.0), UITheme.RED, _on_menu)

func _add_label(text: String, font_size: int, color: Color, pos: Vector2, size: Vector2) -> Label:
	var label := UITheme.label(text, font_size, color, pos, size)
	add_child(label)
	_ui_nodes.append(label)
	return label

func _add_button(text: String, pos: Vector2, size: Vector2, color: Color, cb: Callable, font_size: int = 15) -> Button:
	var btn := UITheme.button(text, pos, size, color, cb, font_size)
	add_child(btn)
	_ui_nodes.append(btn)
	return btn

func _add_slot_button(index: int) -> void:
	var text := "Empty"
	var color := Color(0.18, 0.22, 0.30)
	var card: Dictionary = team[index]
	if not _is_empty_card(card):
		text = _card_button_text(card, false)
		color = Color(0.20, 0.36, 0.46)
	if selected_slot == index:
		color = color.lightened(0.18)
	var btn := _add_button(text, Vector2(170.0 + float(index) * 105.0, 535.0),
			Vector2(86.0, 86.0), color, Callable(self, "_on_slot").bind(index), 12)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _add_shop_button(index: int) -> void:
	var card: Dictionary = shop[index]
	var color := Color(0.28, 0.24, 0.34)
	if bool(card.get("frozen", false)):
		color = Color(0.22, 0.34, 0.42)
	if selected_shop == index:
		color = color.lightened(0.18)
	var label := "%s\n%d gold" % [_card_button_text(card, true), BUY_COST]
	if bool(card.get("frozen", false)):
		label += "\nFrozen"
	var btn := _add_button(label,
			Vector2(705.0 + float(index) * 130.0, 535.0), Vector2(112.0, 86.0),
			color, Callable(self, "_on_shop").bind(index), 12)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _on_shop(index: int) -> void:
	selected_shop = -1 if selected_shop == index else index
	selected_slot = -1
	if selected_shop >= 0:
		var card: Dictionary = shop[selected_shop]
		_shop_message = "%s: %s" % [_unit_name(_card_id(card)), String(UNIT_TYPES[_card_id(card)].get("role", ""))]
	_rebuild_ui()

func _on_slot(index: int) -> void:
	var slot_card: Dictionary = team[index]
	if selected_shop >= 0:
		if gold < BUY_COST:
			_shop_message = "Not enough gold."
			_rebuild_ui()
			return
		var shop_card: Dictionary = shop[selected_shop]
		if _is_empty_card(slot_card):
			team[index] = _copy_card(shop_card)
			gold -= BUY_COST
			_after_shop_card_bought(selected_shop)
			selected_slot = index
			_shop_message = "Bought %s." % _unit_name(_card_id(shop_card))
		elif _card_id(slot_card) == _card_id(shop_card) and int(slot_card.get("level", 1)) < MAX_LEVEL:
			gold -= BUY_COST
			var leveled := _add_xp_to_slot(index, 1)
			_after_shop_card_bought(selected_shop)
			selected_slot = index
			_shop_message = "%s merged%s." % [
				_unit_name(_card_id(slot_card)),
				" and leveled up" if leveled else ""
			]
		else:
			_shop_message = "Pick an empty slot, or merge into the same unit."
		selected_shop = -1
	elif not _is_empty_card(slot_card):
		if selected_slot >= 0 and selected_slot != index and not _is_empty_card(team[selected_slot]):
			var tmp: Dictionary = team[selected_slot]
			team[selected_slot] = team[index]
			team[index] = tmp
			_shop_message = "Team order changed."
		selected_slot = index
		selected_shop = -1
		_shop_message = "%s selected. Click another unit to swap, or sell it." % _unit_name(_card_id(team[index]))
	elif selected_slot >= 0 and selected_slot != index and not _is_empty_card(team[selected_slot]):
		team[index] = team[selected_slot]
		team[selected_slot] = {}
		selected_slot = index
		_shop_message = "Moved unit to an empty slot."
	_rebuild_ui()

func _on_sell() -> void:
	if selected_slot < 0 or selected_slot >= TEAM_SIZE or _is_empty_card(team[selected_slot]):
		_shop_message = "Select a team unit to sell."
		_rebuild_ui()
		return
	var refund := SELL_REFUND + int(team[selected_slot].get("level", 1)) - 1
	_shop_message = "Sold %s for %d gold." % [_unit_name(_card_id(team[selected_slot])), refund]
	team[selected_slot] = {}
	gold += refund
	selected_slot = -1
	_rebuild_ui()

func _on_freeze() -> void:
	if selected_shop < 0 or selected_shop >= shop.size():
		_shop_message = "Select a shop unit to freeze."
		_rebuild_ui()
		return
	shop[selected_shop]["frozen"] = not bool(shop[selected_shop].get("frozen", false))
	_shop_message = "%s %s." % [
		_unit_name(_card_id(shop[selected_shop])),
		"frozen" if bool(shop[selected_shop].get("frozen", false)) else "unfrozen"
	]
	_rebuild_ui()

func _on_roll() -> void:
	if gold < ROLL_COST:
		_shop_message = "Not enough gold to roll."
		_rebuild_ui()
		return
	gold -= ROLL_COST
	_roll_shop(false)
	selected_shop = -1
	_shop_message = "Shop rolled. Frozen units stayed."
	_rebuild_ui()

func _on_fight() -> void:
	if not _has_team():
		_shop_message = "Buy at least one unit before fighting."
		_rebuild_ui()
		return
	phase = Phase.FIGHT
	selected_shop = -1
	selected_slot = -1
	_spawn_fight()
	_rebuild_ui()

func _on_next_shop() -> void:
	_clear_units()
	round_no += 1
	gold = GOLD_PER_ROUND
	_roll_shop(false)
	phase = Phase.SHOP
	_shop_message = "New shop. Build around your leveled units."
	_rebuild_ui()

func _on_restart() -> void:
	get_tree().reload_current_scene()

func _on_menu() -> void:
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _roll_shop(_initial: bool) -> void:
	var previous := shop.duplicate(true)
	shop.clear()
	for i in range(SHOP_SIZE):
		if not _initial and i < previous.size() and bool(previous[i].get("frozen", false)):
			shop.append(previous[i])
		else:
			shop.append(_make_shop_card(_random_unit_id()))

func _has_team() -> bool:
	for card: Dictionary in team:
		if not _is_empty_card(card):
			return true
	return false

func _unit_name(unit_id: String) -> String:
	return String(UNIT_TYPES[unit_id].get("name", unit_id.capitalize()))

func _random_unit_id() -> String:
	var keys := UNIT_TYPES.keys()
	return String(keys[_rng.randi_range(0, keys.size() - 1)])

func _make_shop_card(unit_id: String) -> Dictionary:
	return {"id": unit_id, "level": 1, "xp": 0, "frozen": false}

func _copy_card(card: Dictionary) -> Dictionary:
	return {
		"id": _card_id(card),
		"level": int(card.get("level", 1)),
		"xp": int(card.get("xp", 0)),
	}

func _is_empty_card(card: Dictionary) -> bool:
	return card.is_empty() or not card.has("id") or String(card.get("id", "")) == ""

func _card_id(card: Dictionary) -> String:
	return String(card.get("id", "soldier"))

func _card_button_text(card: Dictionary, compact: bool) -> String:
	if _is_empty_card(card):
		return "Empty"
	var unit_id := _card_id(card)
	var stats := _card_stats(card)
	var base := "%s\nLv %d  XP %d/%d" % [
		_unit_name(unit_id),
		int(card.get("level", 1)),
		int(card.get("xp", 0)),
		XP_TO_LEVEL
	]
	if compact:
		return "%s\n%d dmg / %d hp" % [base, stats["damage"], stats["hp"]]
	return "%s\n%d dmg\n%d hp" % [base, stats["damage"], stats["hp"]]

func _card_stats(card: Dictionary) -> Dictionary:
	var unit_id := _card_id(card)
	var stats: Dictionary = UNIT_TYPES[unit_id]
	var level := int(card.get("level", 1))
	var soldier_count := int(stats.get("soldier_count", 1))
	var hp_per_soldier := int(stats.get("hp_per_soldier", 1))
	var base_hp := soldier_count * hp_per_soldier
	var base_damage := int(stats.get("damage_per_attack", 1))
	return {
		"hp": base_hp + (level - 1) * 36,
		"damage": base_damage + (level - 1) * 4,
	}

func _after_shop_card_bought(index: int) -> void:
	shop[index] = _make_shop_card(_random_unit_id())

func _add_xp_to_slot(index: int, amount: int) -> bool:
	var card: Dictionary = team[index]
	if _is_empty_card(card):
		return false
	var level := int(card.get("level", 1))
	if level >= MAX_LEVEL:
		return false
	var xp := int(card.get("xp", 0)) + amount
	var leveled := false
	while xp >= XP_TO_LEVEL and level < MAX_LEVEL:
		xp -= XP_TO_LEVEL
		level += 1
		leveled = true
	if level >= MAX_LEVEL:
		xp = 0
	card["level"] = level
	card["xp"] = xp
	team[index] = card
	return leveled

func _spawn_fight() -> void:
	_clear_units()
	var player_roster: Array = []
	for card: Dictionary in team:
		if not _is_empty_card(card):
			player_roster.append(_copy_card(card))
	var enemy_roster := _enemy_roster(player_roster.size())
	var player_positions := _formation_positions(player_roster.size(), 0)
	for i in range(player_roster.size()):
		player_units.append(_spawn_unit(player_roster[i], 0, player_positions[i], 1.0))
	var enemy_positions := _formation_positions(enemy_roster.size(), 1)
	for i in range(enemy_roster.size()):
		enemy_units.append(_spawn_unit(enemy_roster[i], 1, enemy_positions[i], 1.0 + float(round_no - 1) * 0.06))
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0

func _spawn_unit(card: Dictionary, team_id: int, pos: Vector2, hp_mult: float) -> RTUnit:
	var u: RTUnit = RTUnit.new()
	add_child(u)
	var unit_id := _card_id(card)
	var stats: Dictionary = UNIT_TYPES[unit_id].duplicate(true)
	var card_stats := _card_stats(card)
	stats["damage_per_attack"] = card_stats["damage"]
	stats["hp_per_soldier"] = max(1, int(ceil(float(card_stats["hp"]) / float(stats.get("soldier_count", 1)))))
	u.setup(unit_id, team_id, pos, stats)
	u.max_hp = int(round(float(u.max_hp) * hp_mult))
	u.hp = u.max_hp
	u.unit_name = "%s Lv %d" % [_unit_name(unit_id), int(card.get("level", 1))]
	u.died.connect(_on_unit_died)
	return u

func _enemy_roster(size_hint: int) -> Array:
	var count: int = clampi(size_hint + int(round_no / 3), 2, TEAM_SIZE)
	var out: Array = []
	for _i in range(count):
		var level := 1 + int(round_no >= 4) + int(round_no >= 7)
		out.append({"id": _random_unit_id(), "level": clampi(level, 1, MAX_LEVEL), "xp": 0})
	return out

func _line_positions(count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var step: float = FIELD_RECT.size.y / float(count + 1)
	for i in range(count):
		out.append(FIELD_RECT.position.y + step * float(i + 1))
	return out

func _formation_positions(count: int, team_id: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var y_positions := _line_positions(count)
	for i in range(count):
		var depth := float(i) * 64.0
		var x := 470.0 - depth
		if team_id == 1:
			x = 810.0 + depth
		out.append(Vector2(x, y_positions[i]))
	return out

func _auto_target(delta: float) -> void:
	_ai_timer -= delta
	if _ai_timer > 0.0:
		return
	_ai_timer = AI_RETARGET_PERIOD
	_assign_targets(player_units, enemy_units)
	_assign_targets(enemy_units, player_units)

func _assign_targets(attackers: Array, defenders: Array) -> void:
	for u: RTUnit in attackers:
		if not u.is_alive():
			continue
		if u.order == RTUnit.Order.ATTACK and u.attack_target != null and u.attack_target.is_alive():
			continue
		var nearest := _nearest_enemy(u, defenders)
		if nearest != null:
			u.order_attack(nearest)

func _nearest_enemy(unit: RTUnit, defenders: Array) -> RTUnit:
	var best: RTUnit = null
	var best_d: float = INF
	for target: RTUnit in defenders:
		if not target.is_alive():
			continue
		var d := unit.position.distance_to(target.position)
		if d < best_d:
			best = target
			best_d = d
	return best

func _check_fight_end() -> void:
	var p_alive := _any_alive(player_units)
	var e_alive := _any_alive(enemy_units)
	if p_alive and e_alive:
		return
	if p_alive and not e_alive:
		wins += 1
		_result_text = "WIN"
	elif e_alive and not p_alive:
		hearts -= 1
		_result_text = "LOSS"
	else:
		_result_text = "DRAW"
	if wins >= MAX_WINS:
		phase = Phase.GAME_OVER
		_result_text = "RUN WON"
	elif hearts <= 0:
		phase = Phase.GAME_OVER
		_result_text = "RUN LOST"
	else:
		phase = Phase.RESULT
	_rebuild_ui()

func _any_alive(units: Array) -> bool:
	for u: RTUnit in units:
		if is_instance_valid(u) and u.is_alive():
			return true
	return false

func _on_unit_died(u: RTUnit) -> void:
	player_units.erase(u)
	enemy_units.erase(u)
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(func():
		_free_node(u)
	)

func _clear_ui() -> void:
	for n: Node in _ui_nodes:
		_free_node(n)
	_ui_nodes.clear()

func _clear_units() -> void:
	for u: RTUnit in player_units:
		_free_node(u)
	for u: RTUnit in enemy_units:
		_free_node(u)
	player_units.clear()
	enemy_units.clear()

func _free_node(node: Node) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()
