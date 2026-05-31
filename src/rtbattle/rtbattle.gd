extends Node2D

# Real-time-with-pause skirmish mode. Standalone — does not touch the
# turn-based campaign state, the run/relic systems, or GameManager mutation.
# Designed to be reached from the title screen as a "Skirmish" button and to
# return there when finished.
#
# Controls:
#   - SPACE        : toggle pause
#   - Left-click   : select a friendly regiment (clears prior selection)
#   - Right-click  : issue an order with the selected regiment
#                       on empty ground → move there
#                       on an enemy regiment → attack it
#   - Esc          : return to title

const RTUnit := preload("res://src/rtbattle/rt_unit.gd")

# Per-unit-type definitions for the skirmish mode. Kept here (not in
# GameManager) so the campaign code and the skirmish mode evolve
# independently. Reuses the existing PNG sprites via `sprite_key`.
const REGIMENT_TYPES: Dictionary = {
	"soldier": {
		"name":              "Infantry",
		"sprite_key":        "soldier",
		"soldier_count":     12,
		"hp_per_soldier":    18,
		"damage_per_attack": 9,
		"attack_cooldown":   1.0,
		"attack_range_px":   55.0,
		"move_speed_px":     58.0,
	},
	"archer": {
		"name":              "Archers",
		"sprite_key":        "archer",
		"soldier_count":     8,
		"hp_per_soldier":    12,
		"damage_per_attack": 10,
		"attack_cooldown":   1.4,
		"attack_range_px":   220.0,
		"move_speed_px":     64.0,
	},
	"scout": {
		"name":              "Cavalry",
		"sprite_key":        "scout",
		"soldier_count":     7,
		"hp_per_soldier":    14,
		"damage_per_attack": 11,
		"attack_cooldown":   0.9,
		"attack_range_px":   55.0,
		"move_speed_px":     105.0,
	},
	"healer": {
		"name":              "Spearmen",
		"sprite_key":        "healer",
		"soldier_count":     10,
		"hp_per_soldier":    16,
		"damage_per_attack": 10,
		"attack_cooldown":   1.2,
		"attack_range_px":   75.0,
		"move_speed_px":     54.0,
	},
}

const FIELD_RECT: Rect2 = Rect2(40.0, 70.0, 1200.0, 580.0)

var player_units: Array = []   # Array[RTUnit]
var enemy_units:  Array = []
var selected_unit: RTUnit = null

var _paused: bool = true
var _ended: bool = false

# UI labels
var _status_label: Label
var _selection_label: Label
var _result_label: Label

func _ready() -> void:
	_build_field()
	_build_ui()
	_spawn_armies()
	_refresh_ui()

# ---------------------------------------------------------------------------
# Field + UI scaffolding
# ---------------------------------------------------------------------------
func _build_field() -> void:
	# Background — deep night-green field with a subtle frame so the player
	# can tell at a glance where the playable area is.
	var bg := ColorRect.new()
	bg.color    = Color(0.10, 0.16, 0.13)
	bg.position = Vector2.ZERO
	bg.size     = Vector2(1280.0, 720.0)
	add_child(bg)

	var field := ColorRect.new()
	field.color    = Color(0.16, 0.24, 0.18)
	field.position = FIELD_RECT.position
	field.size     = FIELD_RECT.size
	add_child(field)

func _build_ui() -> void:
	# Top status strip — pause indicator, hotkeys
	var top := ColorRect.new()
	top.color    = Color(0.07, 0.09, 0.13, 0.92)
	top.position = Vector2(0.0, 0.0)
	top.size     = Vector2(1280.0, 60.0)
	add_child(top)

	var title := Label.new()
	title.text = "SKIRMISH — Real-time tactics"
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(0.90, 0.85, 0.50)
	title.position = Vector2(20.0, 8.0)
	add_child(title)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.position = Vector2(20.0, 32.0)
	add_child(_status_label)

	var hint := Label.new()
	hint.text = "SPACE pause  ·  L-click select  ·  R-click move/attack  ·  Esc to menu"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.55, 0.55, 0.65)
	hint.position = Vector2(620.0, 22.0)
	add_child(hint)

	# Bottom strip — selection info
	var bot := ColorRect.new()
	bot.color    = Color(0.07, 0.09, 0.13, 0.92)
	bot.position = Vector2(0.0, 660.0)
	bot.size     = Vector2(1280.0, 60.0)
	add_child(bot)

	_selection_label = Label.new()
	_selection_label.add_theme_font_size_override("font_size", 15)
	_selection_label.modulate = Color(0.85, 0.90, 0.95)
	_selection_label.position = Vector2(20.0, 676.0)
	_selection_label.size     = Vector2(1240.0, 30.0)
	add_child(_selection_label)

	# Centred result banner (hidden until win/lose)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.position = Vector2(420.0, 320.0)
	_result_label.size     = Vector2(440.0, 80.0)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible  = false
	add_child(_result_label)

# ---------------------------------------------------------------------------
# Army setup — symmetrical mirror skirmish so the mode is self-contained.
# ---------------------------------------------------------------------------
func _spawn_armies() -> void:
	var player_line: Array = [
		{"type": "soldier", "y": 240.0},
		{"type": "archer",  "y": 360.0},
		{"type": "scout",   "y": 480.0},
		{"type": "healer",  "y": 300.0},
	]
	var enemy_line: Array = [
		{"type": "soldier", "y": 240.0},
		{"type": "archer",  "y": 360.0},
		{"type": "scout",   "y": 480.0},
		{"type": "healer",  "y": 420.0},
	]

	var px: float = 240.0
	for i in range(player_line.size()):
		var entry: Dictionary = player_line[i]
		var u := _spawn_regiment(entry["type"], 0, Vector2(px + (i % 2) * 60.0, entry["y"]))
		player_units.append(u)

	var ex: float = 1040.0
	for i in range(enemy_line.size()):
		var entry: Dictionary = enemy_line[i]
		var u := _spawn_regiment(entry["type"], 1, Vector2(ex - (i % 2) * 60.0, entry["y"]))
		enemy_units.append(u)

func _spawn_regiment(type: String, team: int, pos: Vector2) -> RTUnit:
	var u: RTUnit = RTUnit.new()
	add_child(u)
	var stats: Dictionary = REGIMENT_TYPES.get(type, REGIMENT_TYPES["soldier"])
	u.setup(type, team, pos, stats)
	u.died.connect(_on_unit_died)
	return u

# ---------------------------------------------------------------------------
# Simulation tick
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _ended:
		return
	if _paused:
		return
	# All units share a flat neighbour list for cheap collision/separation.
	var all_units: Array = []
	all_units.append_array(player_units)
	all_units.append_array(enemy_units)
	for u: RTUnit in all_units:
		if u.is_alive():
			u.tick(delta, all_units)
	# Keep units inside the playable rect
	for u: RTUnit in all_units:
		if not u.is_alive():
			continue
		u.position.x = clamp(u.position.x, FIELD_RECT.position.x + u.radius,
				FIELD_RECT.end.x - u.radius)
		u.position.y = clamp(u.position.y, FIELD_RECT.position.y + u.radius,
				FIELD_RECT.end.y - u.radius)
	_refresh_ui()
	_check_end_condition()

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_set_paused(not _paused)
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://src/title/title.tscn")
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(event.position)

func _handle_left_click(mouse: Vector2) -> void:
	if _ended:
		return
	# Find a friendly regiment under the cursor and select it.
	var picked: RTUnit = _pick_unit_at(mouse, player_units)
	if selected_unit != null:
		selected_unit.set_selected(false)
	selected_unit = picked
	if selected_unit != null:
		selected_unit.set_selected(true)
	_refresh_ui()

func _handle_right_click(mouse: Vector2) -> void:
	if _ended or selected_unit == null or not selected_unit.is_alive():
		return
	# If we clicked on an enemy, attack it; otherwise move to the click point.
	var enemy: RTUnit = _pick_unit_at(mouse, enemy_units)
	if enemy != null:
		selected_unit.order_attack(enemy)
	else:
		# Clamp target inside the field
		var target := Vector2(
			clamp(mouse.x, FIELD_RECT.position.x + 10.0, FIELD_RECT.end.x - 10.0),
			clamp(mouse.y, FIELD_RECT.position.y + 10.0, FIELD_RECT.end.y - 10.0)
		)
		selected_unit.order_move(target)
	_refresh_ui()

func _pick_unit_at(p: Vector2, pool: Array) -> RTUnit:
	var best: RTUnit = null
	var best_d: float = INF
	for u: RTUnit in pool:
		if not u.is_alive():
			continue
		var d: float = u.position.distance_to(p)
		if d <= u.radius and d < best_d:
			best   = u
			best_d = d
	return best

# ---------------------------------------------------------------------------
# UI state
# ---------------------------------------------------------------------------
func _set_paused(v: bool) -> void:
	_paused = v
	_refresh_ui()

func _refresh_ui() -> void:
	if _status_label != null:
		if _ended:
			_status_label.text = "Battle over"
			_status_label.modulate = Color(0.70, 0.70, 0.75)
		elif _paused:
			_status_label.text = "❚❚ PAUSED  (SPACE to resume)"
			_status_label.modulate = Color(1.0, 0.80, 0.35)
		else:
			_status_label.text = "▶ RUNNING  (SPACE to pause)"
			_status_label.modulate = Color(0.55, 0.95, 0.55)

	if _selection_label != null:
		if selected_unit != null and selected_unit.is_alive():
			var u := selected_unit
			var order_txt := "idle"
			match u.order:
				RTUnit.Order.MOVE:
					order_txt = "moving"
				RTUnit.Order.ATTACK:
					order_txt = "attacking"
			var range_txt: String = "ranged" if u.is_ranged else "melee"
			_selection_label.text = (
				"%s  ·  %s  ·  %d / %d HP  ·  %d / %d soldiers  ·  %s"
				% [u.unit_name, range_txt, u.hp, u.max_hp,
				   u.alive_soldier_count(), u.soldier_count, order_txt]
			)
		else:
			_selection_label.text = "No regiment selected — left-click one of your (blue) units, then right-click to give an order."

func _on_unit_died(u: RTUnit) -> void:
	if u == selected_unit:
		selected_unit = null
	# Drop dead units' visuals after a short delay so the death tween plays.
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(func():
		if is_instance_valid(u):
			u.queue_free()
	)
	# Drop them out of the active lists immediately so combat ignores them
	player_units.erase(u)
	enemy_units.erase(u)

func _check_end_condition() -> void:
	if _ended:
		return
	var p_alive: bool = false
	for u: RTUnit in player_units:
		if u.is_alive():
			p_alive = true
			break
	var e_alive: bool = false
	for u: RTUnit in enemy_units:
		if u.is_alive():
			e_alive = true
			break
	if p_alive and e_alive:
		return
	_ended  = true
	_paused = true
	if _result_label != null:
		if p_alive and not e_alive:
			_result_label.text = "VICTORY"
			_result_label.modulate = Color(0.55, 0.95, 0.55)
		elif e_alive and not p_alive:
			_result_label.text = "DEFEAT"
			_result_label.modulate = Color(0.95, 0.45, 0.45)
		else:
			_result_label.text = "DRAW"
			_result_label.modulate = Color(0.85, 0.85, 0.55)
		_result_label.visible = true
	_refresh_ui()
