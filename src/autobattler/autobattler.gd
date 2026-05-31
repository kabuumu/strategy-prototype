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

enum Phase { SHOP, FIGHT, RESULT, GAME_OVER }

const PET_TYPES: Dictionary = {
	"soldier": {
		"name": "Infantry",
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

var team: Array = []       # Array[String]
var shop: Array = []       # Array[String]
var selected_shop: int = -1
var selected_slot: int = -1
var player_units: Array = []
var enemy_units: Array = []

var _ui_nodes: Array = []
var _ai_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _result_text: String = ""

func _ready() -> void:
	_rng.randomize()
	for _i in range(TEAM_SIZE):
		team.append("")
	_roll_shop(true)
	_rebuild_ui()

func _process(delta: float) -> void:
	if phase != Phase.FIGHT:
		return
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
	for i in range(TEAM_SIZE):
		var x := 170.0 + float(i) * 105.0
		draw_rect(Rect2(x, 535.0, 86.0, 86.0), Color(0.10, 0.12, 0.16), false, 2.0)
	for i in range(SHOP_SIZE):
		var x := 705.0 + float(i) * 130.0
		draw_rect(Rect2(x, 535.0, 112.0, 86.0), Color(0.14, 0.12, 0.16), false, 2.0)

func _rebuild_ui() -> void:
	for n: Node in _ui_nodes:
		_free_node(n)
	_ui_nodes.clear()

	_add_label("AUTO BATTLER", 28, UITheme.GOLD, Vector2(28.0, 14.0), Vector2(250.0, 36.0))
	_add_label("Round %d   Gold %d   Wins %d/%d   Hearts %d" % [round_no, gold, wins, MAX_WINS, hearts],
			17, UITheme.TEXT, Vector2(300.0, 20.0), Vector2(470.0, 26.0))
	_add_button("Menu", Vector2(1120.0, 16.0), Vector2(104.0, 38.0), UITheme.RED, _on_menu)

	if phase == Phase.SHOP:
		_add_label("TEAM", 15, UITheme.TEXT_MUTED, Vector2(170.0, 505.0), Vector2(260.0, 22.0))
		_add_label("SHOP", 15, UITheme.TEXT_MUTED, Vector2(705.0, 505.0), Vector2(260.0, 22.0))
		for i in range(TEAM_SIZE):
			_add_slot_button(i)
		for i in range(SHOP_SIZE):
			_add_shop_button(i)
		_add_button("Sell", Vector2(520.0, 640.0), Vector2(92.0, 42.0), Color(0.34, 0.25, 0.22), _on_sell)
		_add_button("Roll -1", Vector2(706.0, 640.0), Vector2(110.0, 42.0), Color(0.24, 0.30, 0.42), _on_roll)
		_add_button("Fight", Vector2(946.0, 640.0), Vector2(130.0, 42.0), UITheme.GREEN, _on_fight)
	elif phase == Phase.RESULT:
		_add_label(_result_text, 42, UITheme.GOLD, Vector2(360.0, 530.0), Vector2(560.0, 56.0))
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

func _add_button(text: String, pos: Vector2, size: Vector2, color: Color, cb: Callable) -> Button:
	var btn := UITheme.button(text, pos, size, color, cb, 15)
	add_child(btn)
	_ui_nodes.append(btn)
	return btn

func _add_slot_button(index: int) -> void:
	var text := "Empty"
	var color := Color(0.18, 0.22, 0.30)
	if team[index] != "":
		text = _pet_name(team[index])
		color = Color(0.20, 0.36, 0.46)
	if selected_slot == index:
		color = color.lightened(0.18)
	var btn := _add_button(text, Vector2(170.0 + float(index) * 105.0, 535.0),
			Vector2(86.0, 86.0), color, Callable(self, "_on_slot").bind(index))
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _add_shop_button(index: int) -> void:
	var pet_id: String = shop[index]
	var color := Color(0.28, 0.24, 0.34)
	if selected_shop == index:
		color = color.lightened(0.18)
	var btn := _add_button("%s\n%d gold" % [_pet_name(pet_id), BUY_COST],
			Vector2(705.0 + float(index) * 130.0, 535.0), Vector2(112.0, 86.0),
			color, Callable(self, "_on_shop").bind(index))
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _on_shop(index: int) -> void:
	selected_shop = index
	selected_slot = -1
	_rebuild_ui()

func _on_slot(index: int) -> void:
	if selected_shop >= 0 and team[index] == "" and gold >= BUY_COST:
		team[index] = String(shop[selected_shop])
		gold -= BUY_COST
		selected_shop = -1
		selected_slot = index
	elif team[index] != "":
		if selected_slot >= 0 and selected_slot != index and team[selected_slot] != "":
			var tmp: String = team[selected_slot]
			team[selected_slot] = team[index]
			team[index] = tmp
		selected_slot = index
		selected_shop = -1
	_rebuild_ui()

func _on_sell() -> void:
	if selected_slot < 0 or selected_slot >= TEAM_SIZE or team[selected_slot] == "":
		return
	team[selected_slot] = ""
	gold += SELL_REFUND
	selected_slot = -1
	_rebuild_ui()

func _on_roll() -> void:
	if gold < ROLL_COST:
		return
	gold -= ROLL_COST
	_roll_shop(false)
	selected_shop = -1
	_rebuild_ui()

func _on_fight() -> void:
	if not _has_team():
		return
	phase = Phase.FIGHT
	selected_shop = -1
	selected_slot = -1
	_clear_ui()
	_spawn_fight()

func _on_next_shop() -> void:
	_clear_units()
	round_no += 1
	gold = GOLD_PER_ROUND
	_roll_shop(false)
	phase = Phase.SHOP
	_rebuild_ui()

func _on_restart() -> void:
	get_tree().reload_current_scene()

func _on_menu() -> void:
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _roll_shop(_initial: bool) -> void:
	shop.clear()
	var keys := PET_TYPES.keys()
	for _i in range(SHOP_SIZE):
		shop.append(String(keys[_rng.randi_range(0, keys.size() - 1)]))

func _has_team() -> bool:
	for pet_id: String in team:
		if pet_id != "":
			return true
	return false

func _pet_name(pet_id: String) -> String:
	return String(PET_TYPES[pet_id].get("name", pet_id.capitalize()))

func _spawn_fight() -> void:
	_clear_units()
	var player_roster: Array = []
	for pet_id: String in team:
		if pet_id != "":
			player_roster.append(pet_id)
	var enemy_roster := _enemy_roster(player_roster.size())
	var py := _line_positions(player_roster.size())
	for i in range(player_roster.size()):
		var pos := Vector2(250.0 + float(i % 2) * 62.0, py[i])
		player_units.append(_spawn_unit(String(player_roster[i]), 0, pos, 1.0))
	var ey := _line_positions(enemy_roster.size())
	for i in range(enemy_roster.size()):
		var pos := Vector2(1020.0 - float(i % 2) * 62.0, ey[i])
		enemy_units.append(_spawn_unit(String(enemy_roster[i]), 1, pos, 1.0 + float(round_no - 1) * 0.08))

func _spawn_unit(pet_id: String, team_id: int, pos: Vector2, hp_mult: float) -> RTUnit:
	var u: RTUnit = RTUnit.new()
	add_child(u)
	var stats: Dictionary = PET_TYPES[pet_id].duplicate(true)
	u.setup(pet_id, team_id, pos, stats)
	u.max_hp = int(round(float(u.max_hp) * hp_mult))
	u.hp = u.max_hp
	u.died.connect(_on_unit_died)
	return u

func _enemy_roster(size_hint: int) -> Array:
	var count: int = clampi(size_hint + int(round_no / 3), 2, TEAM_SIZE)
	var keys := PET_TYPES.keys()
	var out: Array = []
	for _i in range(count):
		out.append(String(keys[_rng.randi_range(0, keys.size() - 1)]))
	return out

func _line_positions(count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var step: float = FIELD_RECT.size.y / float(count + 1)
	for i in range(count):
		out.append(FIELD_RECT.position.y + step * float(i + 1))
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
