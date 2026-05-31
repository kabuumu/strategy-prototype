extends Node2D

# ---------------------------------------------------------------------------
# Grid constants
# ---------------------------------------------------------------------------
const GRID_COLS: int = 10
const GRID_ROWS: int = 8
const TILE_SIZE: int = 70
const GRID_OFFSET: Vector2 = Vector2(40.0, 55.0)
const PANEL_X: float = 760.0

# ---------------------------------------------------------------------------
# Objectives
# ---------------------------------------------------------------------------
# Three objectives spread across the map — left, centre, right
const OBJECTIVE_CELLS: Array[Vector2i] = [
	Vector2i(2, 2),
	Vector2i(5, 4),
	Vector2i(7, 5),
]
# Bonus awarded when captured: "heal" or "reinforce"
const OBJECTIVE_TYPES: Array[String] = ["heal", "reinforce", "heal"]
const HEAL_AMOUNT: int = 30

# ---------------------------------------------------------------------------
# Turn state machine
# ---------------------------------------------------------------------------
enum Phase {
	PLAYER_SELECT_UNIT,
	PLAYER_SELECT_MOVE,
	PLAYER_SELECT_ATTACK,
	AI_ACTING,
	BATTLE_WON,
	BATTLE_LOST
}

var phase: Phase = Phase.PLAYER_SELECT_UNIT
var selected_unit: Unit = null
var move_cells:   Array[Vector2i] = []
var attack_cells: Array[Vector2i] = []

# ---------------------------------------------------------------------------
# Units
# ---------------------------------------------------------------------------
var player_units: Array[Unit] = []
var enemy_units:  Array[Unit] = []
var _grid_node:   Node2D

# ---------------------------------------------------------------------------
# Objective runtime state
# Each dict: { grid_pos, owner (-1 neutral / 0 player / 1 enemy), type }
# ---------------------------------------------------------------------------
var objectives: Array[Dictionary] = []

# ---------------------------------------------------------------------------
# Terrain — mountain cells block all movement through and onto them
# ---------------------------------------------------------------------------
var mountains: Array[Vector2i] = []

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
var _phase_label:      Label
var _unit_info_label:  Label
var _instruct_label:   Label
var _obj_status_label: Label
var _skip_btn:         Button
var _end_btn:          Button

# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_ui()
	_init_objectives()
	_generate_terrain()
	_spawn_units()
	_update_ui()

# ---------------------------------------------------------------------------
# Objective initialisation
# ---------------------------------------------------------------------------
func _init_objectives() -> void:
	objectives.clear()
	for i in range(OBJECTIVE_CELLS.size()):
		objectives.append({
			"grid_pos": OBJECTIVE_CELLS[i],
			"owner":    -1,
			"type":     OBJECTIVE_TYPES[i],
		})

# ---------------------------------------------------------------------------
# Terrain generation — deterministic per battle tier/elite flag
# Mountains are placed in cols 2–7 (clear of spawn edges) in clusters.
# ---------------------------------------------------------------------------
func _generate_terrain() -> void:
	mountains.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.pending_battle_tier * 127 + (73 if GameManager.pending_battle_elite else 31)

	# Cells that must stay passable (objectives + initial unit rows)
	var reserved: Array[Vector2i] = []
	for obj: Dictionary in objectives:
		reserved.append(obj["grid_pos"])

	var cluster_count := rng.randi_range(3, 5)
	for _c in range(cluster_count):
		var seed_cell := Vector2i(rng.randi_range(2, 7), rng.randi_range(0, GRID_ROWS - 1))
		if seed_cell not in reserved and seed_cell not in mountains:
			mountains.append(seed_cell)

		# Grow each cluster 1–3 cells by attaching to existing mountain edges
		var growth := rng.randi_range(1, 3)
		for _g in range(growth):
			var candidates: Array = []
			for mc: Vector2i in mountains:
				for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var adj := mc + dir
					if _valid_cell(adj) and adj.x >= 2 and adj.x <= 7 \
							and adj not in mountains and adj not in reserved:
						candidates.append(adj)
			if not candidates.is_empty():
				mountains.append(candidates[rng.randi() % candidates.size()])

# ---------------------------------------------------------------------------
# Custom drawing — grid tiles + objective highlights
# ---------------------------------------------------------------------------
func _draw() -> void:
	# Background — drawn here so it sits beneath the grid and objectives
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.07, 0.08, 0.07))

	# Grid tiles
	for x in range(GRID_COLS):
		for y in range(GRID_ROWS):
			var cell := Vector2i(x, y)
			var rect := Rect2(
				GRID_OFFSET + Vector2(x * TILE_SIZE, y * TILE_SIZE),
				Vector2(TILE_SIZE - 1.0, TILE_SIZE - 1.0)
			)
			var color: Color
			if cell in attack_cells:
				color = Color(0.65, 0.16, 0.16, 0.82)
			elif cell in move_cells:
				color = Color(0.16, 0.36, 0.65, 0.80)
			elif (x + y) % 2 == 0:
				color = Color(0.15, 0.21, 0.14)
			else:
				color = Color(0.10, 0.14, 0.09)
			draw_rect(rect, color)
			draw_rect(rect, Color(0.45, 0.54, 0.40, 0.85), false, 1.5)

	# Mountain tiles — drawn over the grid, block all movement
	for m: Vector2i in mountains:
		var bx: float = GRID_OFFSET.x + m.x * TILE_SIZE
		var by: float = GRID_OFFSET.y + m.y * TILE_SIZE
		draw_rect(Rect2(Vector2(bx, by), Vector2(TILE_SIZE - 1.0, TILE_SIZE - 1.0)),
				Color(0.18, 0.16, 0.14))
		# Mountain body — double-peaked silhouette
		draw_polygon(
			PackedVector2Array([
				Vector2(bx + 3,  by + 64),
				Vector2(bx + 22, by + 20),
				Vector2(bx + 38, by + 36),
				Vector2(bx + 50, by + 12),
				Vector2(bx + 66, by + 64),
			]),
			PackedColorArray([Color(0.50, 0.46, 0.40)]))
		# Snow caps
		draw_polygon(
			PackedVector2Array([
				Vector2(bx + 17, by + 32), Vector2(bx + 22, by + 20), Vector2(bx + 27, by + 32)
			]),
			PackedColorArray([Color(0.88, 0.88, 0.93)]))
		draw_polygon(
			PackedVector2Array([
				Vector2(bx + 44, by + 24), Vector2(bx + 50, by + 12), Vector2(bx + 56, by + 24)
			]),
			PackedColorArray([Color(0.88, 0.88, 0.93)]))

	# Objectives drawn on top of the tiles (only while uncaptured)
	for obj: Dictionary in objectives:
		if int(obj["owner"]) != -1:
			continue
		var gx: int = obj["grid_pos"].x
		var gy: int = obj["grid_pos"].y
		var pad := 6.0
		var obj_rect := Rect2(
			GRID_OFFSET + Vector2(gx * TILE_SIZE + pad, gy * TILE_SIZE + pad),
			Vector2(TILE_SIZE - pad * 2.0 - 1.0, TILE_SIZE - pad * 2.0 - 1.0)
		)
		var fill: Color
		match int(obj["owner"]):
			0:  fill = Color(0.20, 0.45, 0.90, 0.70)   # player blue
			1:  fill = Color(0.88, 0.20, 0.20, 0.70)   # enemy red
			_:  fill = Color(0.82, 0.75, 0.18, 0.70)   # neutral gold
		draw_rect(obj_rect, fill)
		draw_rect(obj_rect, Color(1.0, 1.0, 1.0, 0.75), false, 2.0)

		# Small icon letter in corner: H = heal, R = reinforce
		var icon: String = "H" if obj["type"] == "heal" else "R"
		draw_string(ThemeDB.fallback_font, GRID_OFFSET + Vector2(
			gx * TILE_SIZE + pad + 2.0,
			gy * TILE_SIZE + TILE_SIZE - pad - 2.0
		), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))

# ---------------------------------------------------------------------------
# Build UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_grid_node          = Node2D.new()
	_grid_node.position = GRID_OFFSET
	add_child(_grid_node)

	var panel_bg := ColorRect.new()
	panel_bg.color    = Color(0.10, 0.10, 0.15)
	panel_bg.position = Vector2(PANEL_X, 0.0)
	panel_bg.size     = Vector2(1280.0 - PANEL_X, 720.0)
	add_child(panel_bg)

	_phase_label          = _make_label(22, Color(0.95, 0.90, 0.50))
	_phase_label.position = Vector2(PANEL_X + 20.0, 22.0)
	add_child(_phase_label)

	_unit_info_label               = _make_label(14, Color(0.80, 0.90, 0.80))
	_unit_info_label.position      = Vector2(PANEL_X + 20.0, 66.0)
	_unit_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_info_label.size          = Vector2(490.0, 160.0)
	add_child(_unit_info_label)

	_instruct_label               = _make_label(13, Color(0.62, 0.62, 0.62))
	_instruct_label.position      = Vector2(PANEL_X + 20.0, 238.0)
	_instruct_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruct_label.size          = Vector2(480.0, 110.0)
	add_child(_instruct_label)

	# Objective status
	var obj_header := _make_label(12, Color(0.55, 0.55, 0.60))
	obj_header.text     = "Objectives  (H = Heal +%dHP · R = Reinforce Scout)" % HEAL_AMOUNT
	obj_header.position = Vector2(PANEL_X + 20.0, 358.0)
	add_child(obj_header)

	_obj_status_label               = _make_label(13, Color(0.78, 0.82, 0.78))
	_obj_status_label.position      = Vector2(PANEL_X + 20.0, 374.0)
	_obj_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_status_label.size          = Vector2(480.0, 38.0)
	add_child(_obj_status_label)

	_build_unit_legend()

	_skip_btn = _make_button("Skip Attack", Vector2(PANEL_X + 20.0, 560.0), Vector2(220.0, 50.0))
	_skip_btn.pressed.connect(_on_skip_pressed)
	add_child(_skip_btn)

	_end_btn = _make_button("End Turn", Vector2(PANEL_X + 258.0, 560.0), Vector2(220.0, 50.0))
	_end_btn.pressed.connect(_on_end_turn)
	add_child(_end_btn)

func _build_unit_legend() -> void:
	var header := _make_label(12, Color(0.50, 0.50, 0.55))
	header.text     = "Unit types:"
	header.position = Vector2(PANEL_X + 20.0, 424.0)
	add_child(header)
	var y := 442.0
	for utype: String in GameManager.UNIT_TYPES.keys():
		var udata: Dictionary = GameManager.UNIT_TYPES[utype]
		var dot := ColorRect.new()
		dot.color    = udata["color"]
		dot.size     = Vector2(12.0, 12.0)
		dot.position = Vector2(PANEL_X + 20.0, y + 2.0)
		add_child(dot)
		var ll := _make_label(12, Color(0.70, 0.70, 0.70))
		ll.text = "%s  HP:%d  Mv:%d  Rng:%d  Dmg:%d" % [
			udata["name"], udata["max_hp"],
			udata["move_range"], udata["attack_range"], udata["damage"]
		]
		ll.position = Vector2(PANEL_X + 36.0, y)
		add_child(ll)
		y += 19.0

func _make_label(font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = color
	return lbl

func _make_button(txt: String, pos: Vector2, sz: Vector2) -> Button:
	var btn := Button.new()
	btn.text     = txt
	btn.position = pos
	btn.size     = sz
	btn.add_theme_font_size_override("font_size", 16)
	return btn

# ---------------------------------------------------------------------------
# Spawn units
# ---------------------------------------------------------------------------
func _spawn_units() -> void:
	var roster := GameManager.player_roster
	var p_rows := _distribute_rows(roster.size())
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var u := _create_unit(entry["type"], 0, Vector2i(0, p_rows[i]))
		# Carry persisted HP forward (clamped to current max)
		u.hp = clampi(int(entry["hp"]), 1, u.max_hp)
		u._refresh_hp_bar()
		player_units.append(u)

	var tier    := GameManager.pending_battle_tier
	var elite   := GameManager.pending_battle_elite
	var hp_mult := GameManager.get_hp_multiplier(tier, elite)
	var e_list  := GameManager.get_battle_enemy_roster(tier, elite)
	var e_rows  := _distribute_rows(e_list.size())
	for i in range(e_list.size()):
		var u := _create_unit(e_list[i], 1, Vector2i(GRID_COLS - 1, e_rows[i]))
		u.max_hp = int(u.max_hp * hp_mult)
		u.hp     = u.max_hp
		u._refresh_hp_bar()
		enemy_units.append(u)

func _distribute_rows(count: int) -> Array[int]:
	var rows: Array[int] = []
	var step := float(GRID_ROWS) / float(count + 1)
	for i in range(count):
		rows.append(int(step * (i + 1)))
	return rows

func _create_unit(unit_type: String, team: int, pos: Vector2i) -> Unit:
	var scene: PackedScene = load("res://src/battle/unit.tscn")
	var u := scene.instantiate() as Unit
	_grid_node.add_child(u)
	u.setup(unit_type, team, pos)
	return u

# ---------------------------------------------------------------------------
# Update UI
# ---------------------------------------------------------------------------
func _update_ui() -> void:
	match phase:
		Phase.PLAYER_SELECT_UNIT:
			_phase_label.text    = "Your Turn"
			_instruct_label.text = "Click a unit to select it.\nStep on an objective (★) to capture it."
			_unit_info_label.text = ""
			_skip_btn.visible    = false
			_end_btn.visible     = true
			_end_btn.text        = "End Turn"
		Phase.PLAYER_SELECT_MOVE:
			_phase_label.text    = "Move Unit"
			_instruct_label.text = "Click a blue tile to move, or Skip Move to attack from here.\nRight-click to deselect."
			_skip_btn.visible    = true
			_skip_btn.text       = "Skip Move"
			_end_btn.visible     = true
			_end_btn.text        = "Forfeit Unit"
		Phase.PLAYER_SELECT_ATTACK:
			_phase_label.text    = "Attack"
			_instruct_label.text = "Click a red tile to attack.\nOr click Skip Attack."
			_skip_btn.visible    = true
			_skip_btn.text       = "Skip Attack"
			_end_btn.visible     = false
		Phase.AI_ACTING:
			_phase_label.text    = "Enemy Turn"
			_instruct_label.text = "Enemy is acting…"
			_unit_info_label.text = ""
			_skip_btn.visible    = false
			_end_btn.visible     = false
		Phase.BATTLE_WON, Phase.BATTLE_LOST:
			_skip_btn.visible = false
			_end_btn.visible  = false

	if selected_unit and phase in [Phase.PLAYER_SELECT_MOVE, Phase.PLAYER_SELECT_ATTACK]:
		var udata: Dictionary = GameManager.UNIT_TYPES[selected_unit.unit_type]
		_unit_info_label.text = "[%s]\nHP: %d / %d\nMove: %d  ·  Range: %d  ·  Dmg: %d" % [
			udata["name"], selected_unit.hp, selected_unit.max_hp,
			udata["move_range"], udata["attack_range"], udata["damage"]
		]

	_refresh_obj_status()
	queue_redraw()

func _refresh_obj_status() -> void:
	if not _obj_status_label:
		return
	var p := 0
	var e := 0
	var n := 0
	for obj: Dictionary in objectives:
		match int(obj["owner"]):
			0: p += 1
			1: e += 1
			_: n += 1
	_obj_status_label.text = "Yours: %d  ·  Enemy: %d  ·  Neutral: %d" % [p, e, n]

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if phase in [Phase.AI_ACTING, Phase.BATTLE_WON, Phase.BATTLE_LOST]:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var cell := _world_to_grid(event.position)
	if not _valid_cell(cell):
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:  _handle_left_click(cell)
		MOUSE_BUTTON_RIGHT: _handle_right_click()

func _world_to_grid(screen_pos: Vector2) -> Vector2i:
	var local := screen_pos - GRID_OFFSET
	return Vector2i(int(local.x / TILE_SIZE), int(local.y / TILE_SIZE))

func _valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_COLS and cell.y >= 0 and cell.y < GRID_ROWS

func _handle_left_click(cell: Vector2i) -> void:
	match phase:
		Phase.PLAYER_SELECT_UNIT:   _try_select_unit(cell)
		Phase.PLAYER_SELECT_MOVE:   _try_move_unit(cell)
		Phase.PLAYER_SELECT_ATTACK: _try_attack(cell)

func _handle_right_click() -> void:
	if phase == Phase.PLAYER_SELECT_MOVE:
		selected_unit = null
		move_cells.clear()
		attack_cells.clear()
		phase = Phase.PLAYER_SELECT_UNIT
		_update_ui()

# ---------------------------------------------------------------------------
# Player actions
# ---------------------------------------------------------------------------
func _try_select_unit(cell: Vector2i) -> void:
	# Auto-reset player round when all alive units have acted
	if not player_units.any(func(u: Unit) -> bool: return u.is_alive() and not u.has_acted):
		_reset_acted_flags(player_units)

	for u: Unit in player_units:
		if u.is_alive() and u.grid_pos == cell and not u.has_acted:
			selected_unit = u
			move_cells    = _get_move_cells(u)
			attack_cells.clear()
			phase = Phase.PLAYER_SELECT_MOVE
			_update_ui()
			return

func _try_move_unit(cell: Vector2i) -> void:
	if cell not in move_cells:
		return
	if cell != selected_unit.grid_pos:
		selected_unit.grid_pos = cell
		selected_unit.update_visual_position()
	move_cells.clear()
	# Check for objective capture after landing
	_check_capture(selected_unit)
	attack_cells = _get_attack_cells(selected_unit, enemy_units)
	phase = Phase.PLAYER_SELECT_ATTACK
	_update_ui()

func _try_attack(cell: Vector2i) -> void:
	for target: Unit in enemy_units:
		if target.is_alive() and target.grid_pos == cell and cell in attack_cells:
			_do_attack(selected_unit, target)
			_commit_player_unit_turn()
			return

func _do_attack(attacker: Unit, defender: Unit) -> void:
	_lunge(attacker, defender)
	defender.take_damage(attacker.get_damage())
	_shake_grid(2.5)
	if not defender.is_alive():
		_shake_grid(5.0)   # bigger jolt on a kill
		defender.modulate = Color(0.32, 0.32, 0.32, 0.50)

# Attacker hops toward the target and back
func _lunge(attacker: Unit, defender: Unit) -> void:
	var home := attacker.position
	var dir: Vector2 = (defender.position - attacker.position)
	if dir.length() > 0.0:
		dir = dir.normalized() * 11.0
	var tw := create_tween()
	tw.tween_property(attacker, "position", home + dir, 0.07).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(attacker, "position", home, 0.13).set_trans(Tween.TRANS_QUAD)

# Brief positional shake of the unit layer
func _shake_grid(amount: float) -> void:
	var tw := create_tween()
	for _i in range(4):
		tw.tween_property(_grid_node, "position",
			GRID_OFFSET + Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.03)
	tw.tween_property(_grid_node, "position", GRID_OFFSET, 0.04)

func _commit_player_unit_turn() -> void:
	selected_unit.has_acted = true
	selected_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
	selected_unit           = null
	move_cells.clear()
	attack_cells.clear()

	if _all_dead(enemy_units):
		_trigger_win()
		return

	_run_one_ai_unit()

func _on_skip_pressed() -> void:
	match phase:
		Phase.PLAYER_SELECT_MOVE:
			# Attack from current cell without moving
			move_cells.clear()
			attack_cells = _get_attack_cells(selected_unit, enemy_units)
			phase = Phase.PLAYER_SELECT_ATTACK
			_update_ui()
		Phase.PLAYER_SELECT_ATTACK:
			_commit_player_unit_turn()

func _on_end_turn() -> void:
	if selected_unit:
		selected_unit.has_acted = true
		selected_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
		selected_unit           = null
	move_cells.clear()
	attack_cells.clear()

	if _all_dead(enemy_units):
		_trigger_win()
		return

	_mark_all_acted(player_units)
	_run_all_remaining_ai_units()

# ---------------------------------------------------------------------------
# Objective capture
# ---------------------------------------------------------------------------
func _check_capture(unit: Unit) -> void:
	for obj: Dictionary in objectives:
		if obj["grid_pos"] != unit.grid_pos:
			continue
		if int(obj["owner"]) == unit.team:
			return  # Already owned — no bonus
		obj["owner"] = unit.team
		_apply_bonus(unit.team, obj["type"])
		var bonus_desc: String = "+%d HP to all allies" % HEAL_AMOUNT \
			if obj["type"] == "heal" else "Scout reinforcement!"
		var who: String = "You" if unit.team == 0 else "Enemy"
		_show_toast(
			"%s captured an objective! %s" % [who, bonus_desc],
			Color(0.25, 0.85, 0.45) if unit.team == 0 else Color(0.95, 0.40, 0.40)
		)
		return

func _apply_bonus(team: int, type: String) -> void:
	var allies := player_units if team == 0 else enemy_units
	match type:
		"heal":
			for u: Unit in allies:
				if u.is_alive():
					u.hp = mini(u.max_hp, u.hp + HEAL_AMOUNT)
					u._refresh_hp_bar()
		"reinforce":
			_spawn_reinforcement(team)

func _spawn_reinforcement(team: int) -> void:
	var occupied := _all_occupied_cells()
	var search_cols: Array[int]
	if team == 0:
		search_cols = [0, 1]
	else:
		search_cols = [GRID_COLS - 1, GRID_COLS - 2]

	for col: int in search_cols:
		for row in range(GRID_ROWS):
			var pos := Vector2i(col, row)
			if pos not in occupied:
				var u := _create_unit("scout", team, pos)
				if team == 0:
					player_units.append(u)
				else:
					enemy_units.append(u)
				return
	_show_toast("No room for reinforcement!", Color(0.75, 0.75, 0.25))

# ---------------------------------------------------------------------------
# AI — one unit responds after each player unit action
# ---------------------------------------------------------------------------
func _run_one_ai_unit() -> void:
	phase = Phase.AI_ACTING
	_update_ui()
	_execute_one_ai_unit()

func _execute_one_ai_unit() -> void:
	await get_tree().create_timer(0.55).timeout

	# Auto-reset enemy round when all enemies have acted
	if not enemy_units.any(func(u: Unit) -> bool: return u.is_alive() and not u.has_acted):
		_reset_acted_flags(enemy_units)

	var ai_unit: Unit = null
	for u: Unit in enemy_units:
		if u.is_alive() and not u.has_acted:
			ai_unit = u
			break

	if ai_unit == null:
		_trigger_win()
		return

	_ai_act(ai_unit)
	ai_unit.has_acted = true
	ai_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
	queue_redraw()

	if _all_dead(player_units):
		_trigger_loss()
		return

	phase = Phase.PLAYER_SELECT_UNIT
	_update_ui()

# ---------------------------------------------------------------------------
# AI — all remaining enemy units act (after "End Turn")
# ---------------------------------------------------------------------------
func _run_all_remaining_ai_units() -> void:
	phase = Phase.AI_ACTING
	_update_ui()
	_execute_remaining_ai_units()

func _execute_remaining_ai_units() -> void:
	var unacted: Array[Unit] = []
	for u: Unit in enemy_units:
		if u.is_alive() and not u.has_acted:
			unacted.append(u)

	if unacted.is_empty():
		_reset_acted_flags(player_units)
		_reset_acted_flags(enemy_units)
		phase = Phase.PLAYER_SELECT_UNIT
		_update_ui()
		return

	await get_tree().create_timer(0.55).timeout

	var ai_unit: Unit = unacted[0]
	_ai_act(ai_unit)
	ai_unit.has_acted = true
	ai_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
	queue_redraw()

	if _all_dead(player_units):
		_trigger_loss()
		return

	_execute_remaining_ai_units()

# ---------------------------------------------------------------------------
# AI decision-making (objectives + combat)
# ---------------------------------------------------------------------------
func _ai_act(ai_unit: Unit) -> void:
	var combat_target  := _nearest_alive(ai_unit, player_units)
	var obj_cell       := _nearest_capturable_obj(ai_unit)
	var go_for_obj     := false

	if obj_cell != Vector2i(-1, -1):
		var obj_dist    := _manhattan(ai_unit.grid_pos, obj_cell)
		var enemy_dist  := 9999 if combat_target == null \
			else _manhattan(ai_unit.grid_pos, combat_target.grid_pos)
		# Prefer objectives when equal distance or closer; breaks ties toward objectives
		go_for_obj = obj_dist <= enemy_dist

	if go_for_obj:
		# Move toward objective
		var best := _best_move_to_cell(ai_unit, obj_cell)
		if best != ai_unit.grid_pos:
			ai_unit.grid_pos = best
			ai_unit.update_visual_position()
		_check_capture(ai_unit)
		# Still attack if a player unit happens to be in range
		if combat_target != null and \
				_manhattan(ai_unit.grid_pos, combat_target.grid_pos) <= ai_unit.get_attack_range():
			_do_attack(ai_unit, combat_target)
		return

	# No worthwhile objective — default combat behaviour
	if combat_target == null:
		return

	if _manhattan(ai_unit.grid_pos, combat_target.grid_pos) <= ai_unit.get_attack_range():
		_do_attack(ai_unit, combat_target)
		return

	var best := _best_move_toward(ai_unit, combat_target)
	if best != ai_unit.grid_pos:
		ai_unit.grid_pos = best
		ai_unit.update_visual_position()
	_check_capture(ai_unit)
	if _manhattan(ai_unit.grid_pos, combat_target.grid_pos) <= ai_unit.get_attack_range():
		_do_attack(ai_unit, combat_target)

# ---------------------------------------------------------------------------
# Pathfinding / range helpers
# ---------------------------------------------------------------------------
func _get_move_cells(unit: Unit) -> Array[Vector2i]:
	var occupied  := _occupied_cells_except(unit)
	var range_val := unit.get_move_range()

	# BFS so mountains genuinely block paths, not just destination cells
	var visited: Dictionary = {}
	var queue: Array  = [{"pos": unit.grid_pos, "steps": 0}]
	var result: Array[Vector2i] = []
	visited[unit.grid_pos] = true

	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var pos: Vector2i    = item["pos"]
		var steps: int       = item["steps"]

		if pos != unit.grid_pos and pos not in occupied:
			result.append(pos)

		if steps >= range_val:
			continue

		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := pos + dir
			if _valid_cell(next) and next not in visited and next not in mountains:
				visited[next] = true
				queue.append({"pos": next, "steps": steps + 1})

	return result

func _get_attack_cells(attacker: Unit, targets: Array[Unit]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var range_val := attacker.get_attack_range()
	for t: Unit in targets:
		if t.is_alive() and _manhattan(attacker.grid_pos, t.grid_pos) <= range_val:
			cells.append(t.grid_pos)
	return cells

func _occupied_cells_except(excluded: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for u: Unit in player_units:
		if u.is_alive() and u != excluded:
			cells.append(u.grid_pos)
	for u: Unit in enemy_units:
		if u.is_alive():
			cells.append(u.grid_pos)
	return cells

func _all_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for u: Unit in player_units:
		if u.is_alive():
			cells.append(u.grid_pos)
	for u: Unit in enemy_units:
		if u.is_alive():
			cells.append(u.grid_pos)
	return cells

func _best_move_toward(unit: Unit, target: Unit) -> Vector2i:
	return _best_move_to_cell(unit, target.grid_pos)

func _best_move_to_cell(unit: Unit, target_cell: Vector2i) -> Vector2i:
	var best_pos  := unit.grid_pos
	var best_dist := _manhattan(unit.grid_pos, target_cell)
	for cell: Vector2i in _get_move_cells(unit):
		var d := _manhattan(cell, target_cell)
		if d < best_dist:
			best_dist = d
			best_pos  = cell
	return best_pos

func _nearest_alive(from: Unit, targets: Array[Unit]) -> Unit:
	var nearest: Unit = null
	var min_dist: int = 9999
	for t: Unit in targets:
		if t.is_alive():
			var d := _manhattan(from.grid_pos, t.grid_pos)
			if d < min_dist:
				min_dist = d
				nearest  = t
	return nearest

func _nearest_capturable_obj(ai_unit: Unit) -> Vector2i:
	var nearest := Vector2i(-1, -1)
	var min_dist := 9999
	for obj: Dictionary in objectives:
		if int(obj["owner"]) != ai_unit.team:
			var d := _manhattan(ai_unit.grid_pos, obj["grid_pos"])
			if d < min_dist:
				min_dist = d
				nearest  = obj["grid_pos"]
	return nearest

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# ---------------------------------------------------------------------------
# Round helpers
# ---------------------------------------------------------------------------
func _mark_all_acted(units: Array[Unit]) -> void:
	for u: Unit in units:
		if u.is_alive() and not u.has_acted:
			u.has_acted = true
			u.modulate  = Color(0.58, 0.58, 0.58, 1.0)

func _reset_acted_flags(units: Array[Unit]) -> void:
	for u: Unit in units:
		if u.is_alive():
			u.has_acted = false
			u.modulate  = Color(1.0, 1.0, 1.0, 1.0)

func _all_dead(units: Array[Unit]) -> bool:
	return units.all(func(u: Unit) -> bool: return not u.is_alive())

# ---------------------------------------------------------------------------
# Toast notifications
# ---------------------------------------------------------------------------
func _show_toast(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text     = text
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.modulate = color
	# Position above the grid centre so it doesn't clash with units
	lbl.position = Vector2(50.0, 18.0)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(lbl.queue_free)

# ---------------------------------------------------------------------------
# Win / Loss overlays
# ---------------------------------------------------------------------------
var _gold_reward: int = 0

func _trigger_win() -> void:
	phase = Phase.BATTLE_WON
	_persist_roster()
	_gold_reward = GameManager.battle_gold_reward(
		GameManager.pending_battle_tier, GameManager.pending_battle_elite)
	GameManager.add_gold(_gold_reward)
	_update_ui()
	_show_result_overlay(true)

# Survivors (incl. objective-spawned reinforcements) carry forward with their
# remaining HP; the fallen are dropped from the roster — permadeath.
func _persist_roster() -> void:
	var survivors: Array[Dictionary] = []
	for u: Unit in player_units:
		if u.is_alive():
			survivors.append({"type": u.unit_type, "hp": u.hp})
	GameManager.set_roster(survivors)

func _trigger_loss() -> void:
	phase = Phase.BATTLE_LOST
	_update_ui()
	_show_result_overlay(false)

func _show_result_overlay(won: bool) -> void:
	var panel := Panel.new()
	panel.position = Vector2(290.0, 190.0)
	panel.size     = Vector2(700.0, 340.0)

	var s := StyleBoxFlat.new()
	s.bg_color        = Color(0.07, 0.07, 0.12, 0.97)
	s.border_width_left   = 3
	s.border_width_right  = 3
	s.border_width_top    = 3
	s.border_width_bottom = 3
	s.border_color = Color(0.85, 0.75, 0.20) if won else Color(0.85, 0.20, 0.20)
	panel.add_theme_stylebox_override("panel", s)
	add_child(panel)

	var title := Label.new()
	title.text     = "Victory!" if won else "Defeat!"
	title.add_theme_font_size_override("font_size", 56)
	title.modulate  = Color(0.95, 0.85, 0.20) if won else Color(0.95, 0.30, 0.30)
	title.position  = Vector2(220.0, 45.0)
	panel.add_child(title)

	var sub := Label.new()
	if won:
		sub.text = "All enemies defeated.   +%d gold  (total %d)" % [_gold_reward, GameManager.gold]
	else:
		sub.text = "All your units were destroyed."
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate  = Color(0.72, 0.72, 0.72)
	sub.position  = Vector2(170.0, 130.0)
	panel.add_child(sub)

	var btn1 := Button.new()
	btn1.position = Vector2(90.0, 220.0)
	btn1.size     = Vector2(220.0, 60.0)
	btn1.add_theme_font_size_override("font_size", 18)
	if won:
		btn1.text = "Continue"
		btn1.pressed.connect(func() -> void:
			get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
		)
	else:
		btn1.text = "Try Again"
		btn1.pressed.connect(func() -> void:
			GameManager.reset()
			get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
		)
	panel.add_child(btn1)

	var btn2 := Button.new()
	btn2.text     = "Main Menu"
	btn2.position = Vector2(390.0, 220.0)
	btn2.size     = Vector2(220.0, 60.0)
	btn2.add_theme_font_size_override("font_size", 18)
	btn2.pressed.connect(func() -> void:
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	)
	panel.add_child(btn2)
