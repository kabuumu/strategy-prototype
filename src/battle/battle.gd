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

# Status damage-over-time (applied at the start of the unit's side's round)
const POISON_DMG: int = 8
const BURN_DMG: int = 12
const DEATH_TINT := Color(0.32, 0.32, 0.32, 0.50)

# ---------------------------------------------------------------------------
# Turn state machine
# ---------------------------------------------------------------------------
enum Phase {
	PLAYER_SELECT_UNIT,
	PLAYER_SELECT_MOVE,
	PLAYER_SELECT_ATTACK,
	PLAYER_SELECT_ABILITY,
	AI_ACTING,
	BATTLE_WON,
	BATTLE_LOST
}

var phase: Phase = Phase.PLAYER_SELECT_UNIT
var selected_unit: Unit = null
var _selected_unit_origin: Vector2i = Vector2i.ZERO
var move_cells:    Array[Vector2i] = []
var attack_cells:  Array[Vector2i] = []
var ability_cells: Array[Vector2i] = []
const STUN_COLOR := Color(0.75, 0.55, 1.0)

# ---------------------------------------------------------------------------
# Units
# ---------------------------------------------------------------------------
var player_units: Array[Unit] = []
var enemy_units:  Array[Unit] = []
var _grid_node:   Node2D
var _hurt_overlay: ColorRect

# ---------------------------------------------------------------------------
# Objective runtime state
# Each dict: { grid_pos, owner (-1 neutral / 0 player / 1 enemy), type }
# ---------------------------------------------------------------------------
var objectives: Array[Dictionary] = []

# ---------------------------------------------------------------------------
# Terrain
#   mountains — block all movement
#   forests   — cover: occupant takes less damage
#   hills     — high ground: occupant deals more damage
#   lava      — burns the occupant each round (still walkable)
# ---------------------------------------------------------------------------
var mountains: Array[Vector2i] = []
var forests:   Array[Vector2i] = []
var hills:     Array[Vector2i] = []
var lava:      Array[Vector2i] = []
const FOREST_DEFENSE: float = 0.65   # damage multiplier to a defender in forest
const HILL_ATTACK:    float = 1.30   # damage multiplier from an attacker on a hill

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
var _phase_label:      Label
var _unit_info_label:  Label
var _instruct_label:   Label
var _obj_status_label: Label
var _log_label:        Label
var _skip_btn:         Button
var _ability_btn:      Button
var _ability_panel:    Control
var _ability_name_lbl: Label
var _ability_desc_lbl: Label
var _ability_icon_lbl: Label
var _ability_hint_lbl: Label
var _ability_bg:       ColorRect
var _end_btn:          Button

var _battle_log: Array[String] = []
const LOG_MAX_LINES: int = 5

# End-turn confirmation: when units are still ready and the player hits End
# Turn, the first press just arms the button. The next press within
# END_TURN_ARM_WINDOW seconds actually ends the turn.
var _end_turn_armed_at: float = -1.0
var _last_cycled_unit: Unit = null
const END_TURN_ARM_WINDOW: float = 3.0

# Hover state used by the in-grid damage preview
var _hover_cell: Vector2i = Vector2i(-1, -1)

# Threat overlay: per-cell count of alive enemies that could attack that cell
# from their current position. Recomputed whenever enemies move/die.
var _threat_cells: Dictionary = {}
# Player can toggle the overlay with the T key
var _show_threat: bool = true

# Speed control — F toggles between 1× and 2×. Implemented via
# Engine.time_scale so every tween and create_timer respects it.
var _fast_mode: bool = false
const FAST_MULT: float = 2.0
var _speed_badge: Label
var _relics_label: Label

# Battle stats — tracked per fight so the victory screen can show a
# proper scoreboard (turns, MVP, damage dealt/taken, kills).
var _round_count: int = 1
var _damage_dealt_by: Dictionary = {}   # unit instance_id → int total
var _kills_by:        Dictionary = {}   # unit instance_id → int kills
var _damage_taken_total: int = 0

# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_ui()
	_init_objectives()
	_generate_terrain()
	_spawn_units()
	_update_ui()
	# Boss-fight intro overlay
	if GameManager.is_final_battle(GameManager.pending_battle_tier,
			GameManager.pending_battle_elite):
		_show_boss_intro()

# Big "FINAL BATTLE" banner that fades after ~1.8s. Pure visual; doesn't
# block input — but the player can read it while planning their first move.
func _show_boss_intro() -> void:
	var banner := Label.new()
	banner.text = "⚔  FINAL BATTLE  ⚔"
	banner.add_theme_font_size_override("font_size", 48)
	banner.modulate = Color(1.0, 0.30, 0.25, 0.0)
	banner.position = Vector2(340.0, 280.0)
	banner.z_index  = 200
	add_child(banner)
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.35)
	tw.tween_interval(1.1)
	tw.tween_property(banner, "modulate:a", 0.0, 0.55)
	tw.tween_callback(banner.queue_free)

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

	# Scatter special terrain on free passable cells (cols 1–8, off spawn edges)
	forests.clear(); hills.clear(); lava.clear()
	var taken: Array[Vector2i] = reserved.duplicate()
	taken.append_array(mountains)
	var _place := func(target: Array[Vector2i], count: int) -> void:
		var tries := 0
		while target.size() < count and tries < 60:
			tries += 1
			var c := Vector2i(rng.randi_range(1, GRID_COLS - 2), rng.randi_range(0, GRID_ROWS - 1))
			if c not in taken:
				target.append(c)
				taken.append(c)
	_place.call(forests, 5)
	_place.call(hills, 4)
	_place.call(lava, 3)

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
			if cell in ability_cells:
				color = Color(0.52, 0.30, 0.78, 0.85)
			elif cell in attack_cells:
				color = Color(0.65, 0.16, 0.16, 0.82)
			elif cell in move_cells:
				color = Color(0.16, 0.36, 0.65, 0.80)
			elif (x + y) % 2 == 0:
				color = Color(0.15, 0.21, 0.14)
			else:
				color = Color(0.10, 0.14, 0.09)
			draw_rect(rect, color)
			draw_rect(rect, Color(0.45, 0.54, 0.40, 0.85), false, 1.5)

			# Enemy threat overlay — faint red tint on tiles within reach of
			# alive enemies. Stacks with multiple threats up to a cap so the
			# danger zone is unmistakable. Only shown during the player's
			# planning phases (not during attack-targeting / AI / end states).
			if _show_threat and phase in [Phase.PLAYER_SELECT_UNIT, Phase.PLAYER_SELECT_MOVE]:
				var n: int = int(_threat_cells.get(cell, 0))
				if n > 0:
					var a: float = min(0.10 + 0.10 * float(n - 1), 0.30)
					draw_rect(rect, Color(0.95, 0.18, 0.18, a))

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

	# Forest tiles — passable, defenders here take less damage
	for f: Vector2i in forests:
		var fx: float = GRID_OFFSET.x + f.x * TILE_SIZE
		var fy: float = GRID_OFFSET.y + f.y * TILE_SIZE
		# Mossy ground tint
		draw_rect(Rect2(Vector2(fx, fy), Vector2(TILE_SIZE - 1.0, TILE_SIZE - 1.0)),
				Color(0.12, 0.28, 0.14, 0.85))
		# Three little pine triangles
		var trees := [Vector2(fx + 14, fy + 50), Vector2(fx + 35, fy + 56), Vector2(fx + 52, fy + 48)]
		var sizes := [12.0, 14.0, 11.0]
		for i in range(trees.size()):
			var c: Vector2 = trees[i]
			var s: float = sizes[i]
			draw_polygon(
				PackedVector2Array([
					Vector2(c.x - s,       c.y),
					Vector2(c.x + s,       c.y),
					Vector2(c.x,           c.y - s * 1.7),
				]),
				PackedColorArray([Color(0.18, 0.48, 0.22)]))
			draw_rect(Rect2(Vector2(c.x - 1.5, c.y), Vector2(3.0, 5.0)),
					Color(0.30, 0.20, 0.12))
	# Hill tiles — high ground, occupant deals more damage
	for h: Vector2i in hills:
		var hx: float = GRID_OFFSET.x + h.x * TILE_SIZE
		var hy: float = GRID_OFFSET.y + h.y * TILE_SIZE
		draw_rect(Rect2(Vector2(hx, hy), Vector2(TILE_SIZE - 1.0, TILE_SIZE - 1.0)), Color(0.28, 0.23, 0.13))
		draw_polygon(PackedVector2Array([
			Vector2(hx + 6, hy + 58), Vector2(hx + 35, hy + 24), Vector2(hx + 64, hy + 58)]),
			PackedColorArray([Color(0.55, 0.45, 0.28)]))
		draw_string(ThemeDB.fallback_font, Vector2(hx + 4, hy + 16), "↑",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.5))
	# Lava tiles — burns the occupant each round
	for l: Vector2i in lava:
		var lx: float = GRID_OFFSET.x + l.x * TILE_SIZE
		var ly: float = GRID_OFFSET.y + l.y * TILE_SIZE
		draw_rect(Rect2(Vector2(lx, ly), Vector2(TILE_SIZE - 1.0, TILE_SIZE - 1.0)), Color(0.55, 0.18, 0.06))
		draw_rect(Rect2(Vector2(lx + 10, ly + 24), Vector2(48, 20)), Color(0.95, 0.5, 0.1))
		draw_rect(Rect2(Vector2(lx + 20, ly + 30), Vector2(28, 9)), Color(1.0, 0.82, 0.2))

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

	# Damage forecast over targetable enemies (attack + ability phases) —
	# always-on per-tile tag. Note: doesn't show flank bonus, so the hover
	# preview below adds that detail during the attack phase.
	if selected_unit and phase in [Phase.PLAYER_SELECT_ATTACK, Phase.PLAYER_SELECT_ABILITY]:
		var cells := attack_cells if phase == Phase.PLAYER_SELECT_ATTACK else ability_cells
		for t: Unit in enemy_units:
			if not t.is_alive() or t.grid_pos not in cells:
				continue
			var has_cover: bool = t.grid_pos in forests
			# Terrain-aware forecast (forest cover + hill bonus folded in)
			var dmg := _attack_damage(selected_unit, t)
			var lethal: bool = t.hp <= dmg
			var txt: String = "KILL" if lethal else "-%d" % dmg
			if has_cover and not lethal:
				txt += " ♣"
			var col: Color = Color(1.0, 0.35, 0.3) if lethal else Color(1.0, 0.92, 0.4)
			var base := GRID_OFFSET + Vector2(t.grid_pos.x * TILE_SIZE + 6.0, t.grid_pos.y * TILE_SIZE + 18.0)
			draw_string(ThemeDB.fallback_font, base + Vector2(1, 1), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0, 0, 0, 0.8))  # shadow
			draw_string(ThemeDB.fallback_font, base, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)

	# Hover tooltip: more detail (flank, resulting HP) for the currently
	# hovered attackable tile during the attack phase only.
	_draw_damage_preview()

	# Initiative strip — shows who has and hasn't acted this round
	_draw_initiative_strip()

# ---------------------------------------------------------------------------
# Build UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_grid_node          = Node2D.new()
	_grid_node.position = GRID_OFFSET
	add_child(_grid_node)

	# Hurt overlay — full-grid red flash when the player takes damage.
	# Sits above the grid but below the side panel; alpha is tweened from 0.
	_hurt_overlay              = ColorRect.new()
	_hurt_overlay.color        = Color(0.85, 0.10, 0.10, 0.0)
	_hurt_overlay.position     = Vector2(0.0, 0.0)
	_hurt_overlay.size         = Vector2(PANEL_X, 720.0)
	_hurt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt_overlay)

	var panel_bg := ColorRect.new()
	panel_bg.color    = Color(0.10, 0.10, 0.15)
	panel_bg.position = Vector2(PANEL_X, 0.0)
	panel_bg.size     = Vector2(1280.0 - PANEL_X, 720.0)
	add_child(panel_bg)

	_phase_label          = _make_label(22, Color(0.95, 0.90, 0.50))
	_phase_label.position = Vector2(PANEL_X + 20.0, 22.0)
	add_child(_phase_label)

	# Speed badge sits in the top-right of the side panel
	_speed_badge          = _make_label(14, Color(0.70, 0.70, 0.75))
	_speed_badge.text     = "▶ 1×"
	_speed_badge.position = Vector2(1280.0 - 60.0, 26.0)
	add_child(_speed_badge)

	# Relics strip — read-only reminder of which run-long passives are active,
	# so the player can interpret damage forecasts and HP totals at a glance.
	_relics_label = _make_label(11, Color(0.78, 0.70, 0.95))
	_relics_label.position      = Vector2(PANEL_X + 20.0, 50.0)
	_relics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_relics_label.size          = Vector2(480.0, 14.0)
	add_child(_relics_label)
	_refresh_relics_label()

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

	_build_ability_bar()

	_skip_btn = _make_button("Skip Attack", Vector2(PANEL_X + 20.0, 560.0), Vector2(220.0, 50.0))
	_skip_btn.pressed.connect(_on_skip_pressed)
	add_child(_skip_btn)

	_end_btn = _make_button("End Turn", Vector2(PANEL_X + 258.0, 560.0), Vector2(220.0, 50.0))
	_end_btn.pressed.connect(_on_end_turn)
	add_child(_end_btn)

	# Battle log — last few combat events, sits below the action buttons
	var log_header := _make_label(11, Color(0.45, 0.45, 0.50))
	log_header.text     = "Battle log"
	log_header.position = Vector2(PANEL_X + 20.0, 618.0)
	add_child(log_header)

	_log_label               = _make_label(12, Color(0.72, 0.78, 0.82))
	_log_label.position      = Vector2(PANEL_X + 20.0, 634.0)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.size          = Vector2(480.0, 82.0)
	add_child(_log_label)

func _refresh_hover_unit_info() -> void:
	if _unit_info_label == null:
		return
	if _hover_cell == Vector2i(-1, -1):
		_unit_info_label.text = ""
		return
	var hovered: Unit = null
	for u: Unit in player_units + enemy_units:
		if u.is_alive() and u.grid_pos == _hover_cell:
			hovered = u
			break
	if hovered == null:
		_unit_info_label.text = ""
		return
	var udata: Dictionary = GameManager.UNIT_TYPES[hovered.unit_type]
	var tag: String = "You" if hovered.team == 0 else "Enemy"
	var status_parts: PackedStringArray = []
	if hovered.stunned:
		status_parts.append("STUNNED")
	if hovered.poison_turns > 0:
		status_parts.append("POISON %d" % hovered.poison_turns)
	if hovered.burn_turns > 0:
		status_parts.append("BURN %d" % hovered.burn_turns)
	if hovered.has_acted:
		status_parts.append("acted")
	var status_str: String = "  ·  " + ", ".join(status_parts) if status_parts.size() > 0 else ""
	_unit_info_label.text = "[%s] %s%s\nHP: %d / %d\nMove: %d  ·  Range: %d  ·  Dmg: %d" % [
		tag, udata["name"], status_str,
		hovered.hp, hovered.max_hp,
		hovered.get_move_range(),
		hovered.get_attack_range(),
		hovered.get_damage()
	]

func _refresh_relics_label() -> void:
	if _relics_label == null:
		return
	if GameManager.relics.is_empty():
		_relics_label.text = ""
		return
	var parts: PackedStringArray = []
	for id: String in GameManager.relics:
		if GameManager.RELICS.has(id):
			parts.append("◆ " + String(GameManager.RELICS[id]["name"]))
	_relics_label.text = "Relics:  " + "   ".join(parts)

func _build_unit_legend() -> void:
	var header := _make_label(12, Color(0.50, 0.50, 0.55))
	header.text     = "Unit types:"
	header.position = Vector2(PANEL_X + 20.0, 424.0)
	add_child(header)
	var y := 442.0
	for utype: String in GameManager.recruitable_types():
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

# Single-character glyph that visually represents each ability id.
const ABILITY_ICONS: Dictionary = {
	"bash":      "⚡",
	"pierce":    "➤",
	"dash":      "»",
	"heal_ally": "✚",
}

# Builds the ability action bar below the grid. The bar contains a large
# icon, the ability's name and description, and a [Q] hotkey hint. The whole
# bar is hidden when the currently selected unit has no usable ability so the
# space stays unobtrusive.
func _build_ability_bar() -> void:
	_ability_panel              = Control.new()
	_ability_panel.position     = Vector2(40.0, 625.0)
	_ability_panel.size         = Vector2(700.0, 80.0)
	_ability_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_ability_panel.visible      = false
	add_child(_ability_panel)

	_ability_bg = ColorRect.new()
	_ability_bg.color    = Color(0.18, 0.13, 0.26, 0.92)
	_ability_bg.position = Vector2.ZERO
	_ability_bg.size     = Vector2(700.0, 80.0)
	_ability_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_panel.add_child(_ability_bg)

	# The button itself fills the panel so the whole bar is clickable.
	_ability_btn = Button.new()
	_ability_btn.text     = ""
	_ability_btn.position = Vector2.ZERO
	_ability_btn.size     = Vector2(700.0, 80.0)
	_ability_btn.flat     = true
	_ability_btn.pressed.connect(_on_ability_pressed)
	_ability_panel.add_child(_ability_btn)

	_ability_icon_lbl = _make_label(46, STUN_COLOR)
	_ability_icon_lbl.position = Vector2(16.0, 8.0)
	_ability_icon_lbl.size     = Vector2(70.0, 70.0)
	_ability_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ability_icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_ability_icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_panel.add_child(_ability_icon_lbl)

	_ability_name_lbl = _make_label(18, Color(0.95, 0.92, 1.0))
	_ability_name_lbl.position = Vector2(100.0, 12.0)
	_ability_name_lbl.size     = Vector2(520.0, 26.0)
	_ability_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_panel.add_child(_ability_name_lbl)

	_ability_desc_lbl = _make_label(13, Color(0.75, 0.72, 0.85))
	_ability_desc_lbl.position = Vector2(100.0, 42.0)
	_ability_desc_lbl.size     = Vector2(520.0, 30.0)
	_ability_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ability_desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_panel.add_child(_ability_desc_lbl)

	_ability_hint_lbl = _make_label(13, Color(0.70, 0.65, 0.85))
	_ability_hint_lbl.text     = "[Q]"
	_ability_hint_lbl.position = Vector2(640.0, 32.0)
	_ability_hint_lbl.size     = Vector2(50.0, 18.0)
	_ability_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ability_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_panel.add_child(_ability_hint_lbl)

# Refresh the ability bar's contents and visibility based on the current
# selection and phase. Called every time _update_ui runs.
func _refresh_ability_bar() -> void:
	if _ability_panel == null:
		return
	var show: bool = phase in [Phase.PLAYER_SELECT_MOVE, Phase.PLAYER_SELECT_ATTACK] \
			and selected_unit != null \
			and not selected_unit.ability_used
	if not show:
		_ability_panel.visible = false
		return
	var abil: Dictionary = selected_unit.get_ability()
	if abil.is_empty():
		_ability_panel.visible = false
		return
	var has_target: bool = not _ability_target_cells(selected_unit, abil["id"]).is_empty()
	_ability_panel.visible = true
	_ability_btn.disabled  = not has_target
	_ability_icon_lbl.text = String(ABILITY_ICONS.get(abil["id"], "✦"))
	_ability_name_lbl.text = String(abil.get("name", "Ability"))
	_ability_desc_lbl.text = String(abil.get("desc", ""))
	# Dim everything when the ability has no valid target right now
	var dim: float = 0.45 if not has_target else 1.0
	_ability_bg.color        = Color(0.18, 0.13, 0.26, 0.92 if has_target else 0.55)
	_ability_icon_lbl.modulate = Color(STUN_COLOR.r, STUN_COLOR.g, STUN_COLOR.b, dim)
	_ability_name_lbl.modulate = Color(0.95, 0.92, 1.0, dim)
	_ability_desc_lbl.modulate = Color(0.75, 0.72, 0.85, dim)
	_ability_hint_lbl.modulate = Color(0.70, 0.65, 0.85, dim)

# ---------------------------------------------------------------------------
# Spawn units
# ---------------------------------------------------------------------------
func _spawn_units() -> void:
	var roster := GameManager.player_roster
	var p_rows := _distribute_rows(roster.size())
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var u := _create_unit(entry["type"], 0, Vector2i(0, p_rows[i]), entry.get("upgrades", []))
		# Carry persisted HP forward (clamped to current max — VETERAN may have raised it)
		u.hp = clampi(int(entry["hp"]), 1, u.max_hp)
		# Field Kit relic: start each battle a little healed
		if GameManager.has_relic("medkit"):
			u.hp = mini(u.max_hp, u.hp + 15)
		u._refresh_hp_bar()
		player_units.append(u)

	var tier    := GameManager.pending_battle_tier
	var elite   := GameManager.pending_battle_elite
	var hp_mult := GameManager.get_hp_multiplier(tier, elite)
	var e_list  := GameManager.get_battle_enemy_roster(tier, elite)
	var e_rows  := _distribute_rows(e_list.size())
	for i in range(e_list.size()):
		var u := _create_unit(e_list[i], 1, Vector2i(GRID_COLS - 1, e_rows[i]), [])
		u.max_hp = int(u.max_hp * hp_mult)
		u.hp     = u.max_hp
		u._refresh_hp_bar()
		enemy_units.append(u)

	_recompute_threat()

# Recompute which cells are currently within attack reach of any alive enemy.
# Cheap (O(enemies × range²)) and only called when the situation changes.
func _recompute_threat() -> void:
	_threat_cells.clear()
	for u: Unit in enemy_units:
		if not u.is_alive() or u.stunned:
			continue
		var r := u.get_attack_range()
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if dx == 0 and dy == 0:
					continue
				var c := u.grid_pos + Vector2i(dx, dy)
				if not _valid_cell(c):
					continue
				_threat_cells[c] = int(_threat_cells.get(c, 0)) + 1

func _distribute_rows(count: int) -> Array[int]:
	var rows: Array[int] = []
	var step := float(GRID_ROWS) / float(count + 1)
	for i in range(count):
		rows.append(int(step * (i + 1)))
	return rows

func _create_unit(unit_type: String, team: int, pos: Vector2i, ups: Array = []) -> Unit:
	var scene: PackedScene = load("res://src/battle/unit.tscn")
	var u := scene.instantiate() as Unit
	_grid_node.add_child(u)
	u.upgrades = ups.duplicate()
	u.setup(unit_type, team, pos)
	return u

# ---------------------------------------------------------------------------
# Update UI
# ---------------------------------------------------------------------------
func _update_ui() -> void:
	# Disarm the end-turn confirmation whenever we're not in the unit-select
	# phase — the user took an action, so the previous "are you sure?" state
	# should be discarded.
	if phase != Phase.PLAYER_SELECT_UNIT:
		_end_turn_armed_at = -1.0
	match phase:
		Phase.PLAYER_SELECT_UNIT:
			_phase_label.text    = "Your Turn"
			_instruct_label.text = "Click a unit to select it.\nStep on an objective (★) to capture it."
			_unit_info_label.text = ""
			_skip_btn.visible    = false
			_end_btn.visible     = true
			_refresh_end_turn_button()
		Phase.PLAYER_SELECT_MOVE:
			_phase_label.text    = "Move Unit"
			_instruct_label.text = "Click a blue tile to move, a red tile to attack from here, or Skip Move.\nRight-click to deselect."
			_skip_btn.visible    = true
			_skip_btn.text       = "Skip Move"
			_end_btn.visible     = true
			_end_btn.text        = "Forfeit Unit"
		Phase.PLAYER_SELECT_ATTACK:
			_phase_label.text    = "Attack"
			_instruct_label.text = "Click a red tile to attack, use your ability, or Skip Attack.\nRight-click to cancel move."
			_skip_btn.visible    = true
			_skip_btn.text       = "Skip Attack"
			_end_btn.visible     = false
		Phase.PLAYER_SELECT_ABILITY:
			var abil_ui: Dictionary = selected_unit.get_ability() if selected_unit else {}
			_phase_label.text    = abil_ui.get("name", "Ability")
			_instruct_label.text = "Click a purple tile to use %s.\nRight-click to cancel." % abil_ui.get("name", "ability")
			_skip_btn.visible    = false
			_end_btn.visible     = false
		Phase.AI_ACTING:
			_phase_label.text    = "Enemy Turn"
			_instruct_label.text = "Enemy is acting…"
			_unit_info_label.text = ""
			_skip_btn.visible    = false
			_end_btn.visible     = false
		Phase.BATTLE_WON, Phase.BATTLE_LOST:
			_skip_btn.visible    = false
			_end_btn.visible     = false

	# The ability action bar (icon-rich panel below the grid) figures out
	# its own visibility/disabled state based on the current phase and unit.
	_refresh_ability_bar()

	if selected_unit and phase in [Phase.PLAYER_SELECT_MOVE, Phase.PLAYER_SELECT_ATTACK]:
		var udata: Dictionary = GameManager.UNIT_TYPES[selected_unit.unit_type]
		var ups := selected_unit.upgrade_short_labels()
		var up_str: String = ("   ✦ " + ", ".join(ups)) if ups.size() > 0 else ""
		# Show effective stats (post-upgrade), with base in parens when bonused
		_unit_info_label.text = "[%s]%s\nHP: %d / %d\nMove: %d  ·  Range: %d  ·  Dmg: %d" % [
			udata["name"], up_str,
			selected_unit.hp, selected_unit.max_hp,
			selected_unit.get_move_range(),
			selected_unit.get_attack_range(),
			selected_unit.get_damage()
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
# Battle log
# ---------------------------------------------------------------------------
func _log_event(text: String) -> void:
	_battle_log.append(text)
	while _battle_log.size() > LOG_MAX_LINES:
		_battle_log.pop_front()
	if _log_label:
		_log_label.text = "\n".join(_battle_log)

func _unit_label(u: Unit) -> String:
	var name_str: String = GameManager.UNIT_TYPES[u.unit_type]["name"]
	return ("You-" if u.team == 0 else "Enemy-") + name_str

# ---------------------------------------------------------------------------
# Initiative strip
# ---------------------------------------------------------------------------
func _draw_initiative_strip() -> void:
	var font: Font = ThemeDB.fallback_font
	var y: float = 22.0
	var x: float = 50.0
	draw_string(font, Vector2(8.0, y + 12.0), "TURN:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.55, 0.60))
	x = 50.0
	for u: Unit in player_units:
		if not u.is_alive():
			continue
		_draw_init_token(font, x, y, u, false)
		x += 28.0
	# Divider
	draw_line(Vector2(x + 4.0, y - 6.0), Vector2(x + 4.0, y + 22.0),
		Color(0.45, 0.45, 0.50, 0.6), 2.0)
	x += 14.0
	for u: Unit in enemy_units:
		if not u.is_alive():
			continue
		_draw_init_token(font, x, y, u, true)
		x += 28.0

func _draw_init_token(font: Font, x: float, y: float, u: Unit, is_enemy: bool) -> void:
	var udata: Dictionary = GameManager.UNIT_TYPES[u.unit_type]
	var base_col: Color = udata["color"] if not is_enemy else Color(0.92, 0.32, 0.32)
	var alpha: float = 0.30 if u.has_acted else 1.0
	var col := Color(base_col.r, base_col.g, base_col.b, alpha)
	var center := Vector2(x + 11.0, y + 9.0)
	draw_circle(center, 11.0, col)
	# Outline (yellow if this unit is the next to act)
	var is_next: bool = _is_next_to_act(u)
	var outline_col: Color = (Color(1.0, 0.92, 0.30, 0.95) if is_next
		else Color(0.0, 0.0, 0.0, 0.6 * alpha))
	var outline_w: float = 2.5 if is_next else 1.0
	draw_arc(center, 11.0, 0.0, TAU, 20, outline_col, outline_w)
	var letter: String = (udata["name"] as String).substr(0, 1).to_upper()
	draw_string(font, Vector2(x + 6.0, y + 14.0), letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.05, 0.05, 0.05, alpha))

func _is_next_to_act(u: Unit) -> bool:
	# In PLAYER_SELECT_UNIT: next is first player with !has_acted and alive
	# In AI_ACTING: next is first enemy with !has_acted and alive
	if u.has_acted or not u.is_alive():
		return false
	if phase == Phase.AI_ACTING:
		for e: Unit in enemy_units:
			if e.is_alive() and not e.has_acted:
				return e == u
		return false
	# Player phases — highlight the selected unit if any, otherwise first unacted
	if selected_unit != null and u.team == 0:
		return u == selected_unit
	if u.team == 0:
		for p: Unit in player_units:
			if p.is_alive() and not p.has_acted:
				return p == u
	return false

# ---------------------------------------------------------------------------
# Damage preview overlay
# ---------------------------------------------------------------------------
func _draw_damage_preview() -> void:
	# Damage forecast is helpful both when standing in attack-select phase
	# and when surveying attack targets reachable from the unit's current
	# cell during the move phase.
	if phase != Phase.PLAYER_SELECT_ATTACK and phase != Phase.PLAYER_SELECT_MOVE:
		return
	if selected_unit == null:
		return
	if _hover_cell == Vector2i(-1, -1) or _hover_cell not in attack_cells:
		return

	var target: Unit = null
	for t: Unit in enemy_units:
		if t.is_alive() and t.grid_pos == _hover_cell:
			target = t
			break
	if target == null:
		return

	# Use base damage + flank + cover — don't leak the random crit roll
	var base := selected_unit.get_damage()
	var flank := _is_flanking(selected_unit, target)
	var cover: bool = target.grid_pos in forests
	# Flank bonus × terrain (forest cover + hill high-ground)
	var mult: float = (FLANK_MULT if flank else 1.0) * _terrain_mult(selected_unit, target)
	var dmg: int = maxi(1, int(round(base * mult)))
	var lethal := dmg >= target.hp

	var line1 := "%d dmg → HP %d/%d" % [dmg, max(0, target.hp - dmg), target.max_hp]
	var line2 := ""
	if lethal:
		line2 = "LETHAL"
	elif flank and cover:
		line2 = "FLANKED in COVER"
	elif flank:
		line2 = "FLANKED!"
	elif cover:
		line2 = "IN COVER"

	var origin := GRID_OFFSET + Vector2(_hover_cell.x * TILE_SIZE, _hover_cell.y * TILE_SIZE)
	# Position tooltip above the tile, or below if near top edge
	var tip_above := _hover_cell.y >= 1
	var tip_y: float = origin.y - 38.0 if tip_above else origin.y + TILE_SIZE + 4.0
	var tip_rect := Rect2(origin.x - 10.0, tip_y, 130.0, 34.0)
	draw_rect(tip_rect, Color(0.0, 0.0, 0.0, 0.78))
	draw_rect(tip_rect, Color(0.95, 0.30, 0.25, 0.9), false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(tip_rect.position.x + 6.0, tip_rect.position.y + 14.0),
			line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))
	if line2 != "":
		var col2: Color = Color(1.0, 0.55, 0.30) if lethal else Color(1.0, 0.85, 0.30)
		draw_string(ThemeDB.fallback_font, Vector2(tip_rect.position.x + 6.0, tip_rect.position.y + 29.0),
				line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col2)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if phase in [Phase.AI_ACTING, Phase.BATTLE_WON, Phase.BATTLE_LOST]:
		return

	# Mouse motion → track hover cell for the damage preview overlay
	if event is InputEventMouseMotion:
		var hc := _world_to_grid(event.position)
		if not _valid_cell(hc):
			hc = Vector2i(-1, -1)
		if hc != _hover_cell:
			_hover_cell = hc
			queue_redraw()
			# Hovering over a unit during the unit-select phase pre-fills the
			# unit info panel so the player can scout enemy stats without
			# having to commit a selection first.
			if phase == Phase.PLAYER_SELECT_UNIT:
				_refresh_hover_unit_info()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
		return

	if not (event is InputEventMouseButton and event.pressed):
		return
	var cell := _world_to_grid(event.position)
	if not _valid_cell(cell):
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:  _handle_left_click(cell)
		MOUSE_BUTTON_RIGHT: _handle_right_click()

# ---------------------------------------------------------------------------
# Keyboard shortcuts
#   Esc       – deselect / cancel current action (same as right-click)
#   Enter/Sp  – end turn (when not in the middle of an action)
#   Tab       – cycle to next unacted player unit
# ---------------------------------------------------------------------------
func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_ESCAPE:
			_handle_right_click()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if phase == Phase.PLAYER_SELECT_UNIT:
				_on_end_turn()
		KEY_TAB:
			if phase == Phase.PLAYER_SELECT_UNIT:
				_cycle_to_next_unacted_unit()
		KEY_T:
			_show_threat = not _show_threat
			_show_toast("Threat overlay: " + ("ON" if _show_threat else "OFF"),
					Color(0.85, 0.55, 0.55))
			queue_redraw()
		KEY_F:
			_set_fast_mode(not _fast_mode)
		KEY_Q:
			# Trigger the ability bar if it's currently usable.
			if _ability_btn != null and _ability_panel != null \
					and _ability_panel.visible and not _ability_btn.disabled:
				_on_ability_pressed()

# Apply the speed multiplier engine-wide so AI timers, attack lunges and
# move tweens all fast-forward together. Reset on scene exit.
func _set_fast_mode(on: bool) -> void:
	_fast_mode = on
	Engine.time_scale = FAST_MULT if on else 1.0
	if _speed_badge:
		_speed_badge.text = "▶▶ 2×" if on else "▶ 1×"
		_speed_badge.modulate = (Color(1.0, 0.85, 0.30) if on
				else Color(0.70, 0.70, 0.75))
	_show_toast("Game speed: " + ("2×" if on else "1×"),
			Color(1.0, 0.85, 0.30) if on else Color(0.70, 0.70, 0.75))

func _exit_tree() -> void:
	# Never leave the engine in fast mode when the scene unloads
	Engine.time_scale = 1.0

func _cycle_to_next_unacted_unit() -> void:
	# Build the list of cyclable units (alive + not yet acted) in roster order.
	var pool: Array[Unit] = []
	for u: Unit in player_units:
		if u.is_alive() and not u.has_acted:
			pool.append(u)
	if pool.is_empty():
		return
	# Anchor the rotation on the last unit we cycled to (if it's still in
	# the pool) so repeated Tab presses step through every unit in turn.
	var start: int = 0
	var anchor: Unit = selected_unit if selected_unit != null else _last_cycled_unit
	if anchor != null:
		var idx: int = pool.find(anchor)
		if idx != -1:
			start = (idx + 1) % pool.size()
	for offset in range(pool.size()):
		var pick: Unit = pool[(start + offset) % pool.size()]
		_try_select_unit(pick.grid_pos)
		if selected_unit == pick:
			_last_cycled_unit = pick
			# Brief flash so the eye finds the new selection quickly.
			_flash_unit(pick)
			return

func _flash_unit(u: Unit) -> void:
	var t := create_tween()
	var base: Color = u.modulate
	t.tween_property(u, "modulate", Color(1.6, 1.6, 0.9, base.a), 0.08)
	t.tween_property(u, "modulate", base, 0.18)


func _world_to_grid(screen_pos: Vector2) -> Vector2i:
	var local := screen_pos - GRID_OFFSET
	return Vector2i(int(local.x / TILE_SIZE), int(local.y / TILE_SIZE))

func _valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_COLS and cell.y >= 0 and cell.y < GRID_ROWS

func _handle_left_click(cell: Vector2i) -> void:
	match phase:
		Phase.PLAYER_SELECT_UNIT:    _try_select_unit(cell)
		Phase.PLAYER_SELECT_MOVE:    _try_move_unit(cell)
		Phase.PLAYER_SELECT_ATTACK:  _try_attack(cell)
		Phase.PLAYER_SELECT_ABILITY: _try_ability(cell)

func _handle_right_click() -> void:
	match phase:
		Phase.PLAYER_SELECT_MOVE:
			selected_unit = null
			move_cells.clear()
			attack_cells.clear()
			ability_cells.clear()
			phase = Phase.PLAYER_SELECT_UNIT
			_update_ui()
		Phase.PLAYER_SELECT_ATTACK:
			# Restore the unit to where it was before the move and cancel the whole action
			selected_unit.grid_pos = _selected_unit_origin
			selected_unit.update_visual_position()
			selected_unit = null
			move_cells.clear()
			attack_cells.clear()
			ability_cells.clear()
			phase = Phase.PLAYER_SELECT_UNIT
			_update_ui()
		Phase.PLAYER_SELECT_ABILITY:
			# Cancel ability targeting, back to attack phase
			ability_cells.clear()
			attack_cells = _get_attack_cells(selected_unit, enemy_units)
			phase = Phase.PLAYER_SELECT_ATTACK
			_update_ui()

# ---------------------------------------------------------------------------
# Player actions
# ---------------------------------------------------------------------------
func _try_select_unit(cell: Vector2i) -> void:
	for u: Unit in player_units:
		if u.is_alive() and u.grid_pos == cell and not u.has_acted:
			selected_unit        = u
			_selected_unit_origin = u.grid_pos
			move_cells           = _get_move_cells(u)
			# Surface attack targets reachable from the unit's current cell
			# so the player can attack without having to commit a move first.
			attack_cells         = _get_attack_cells(u, enemy_units)
			phase = Phase.PLAYER_SELECT_MOVE
			_update_ui()
			return

func _try_move_unit(cell: Vector2i) -> void:
	# Clicking an in-range enemy from the move phase performs an attack from
	# the current cell without consuming a move step. Attack cells take
	# precedence over move cells if they ever overlap (they shouldn't, since
	# enemies block movement, but defend against it anyway).
	if cell in attack_cells:
		move_cells.clear()
		_try_attack(cell)
		return
	if cell not in move_cells:
		return
	if cell != selected_unit.grid_pos:
		var origin := selected_unit.grid_pos
		selected_unit.grid_pos = cell
		# Visually walk along the BFS path. Fire-and-forget — the tween plays
		# while the player is reading their attack options.
		_animate_unit_to(selected_unit, origin, cell)
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

# ---------------------------------------------------------------------------
# Combat resolution — crits + flanking bonuses + terrain
# ---------------------------------------------------------------------------
const FLANK_MULT: float = 1.25
const CRIT_MULT:  float = 1.5
const CRIT_CHANCE: float = 0.15

# Flanking: an ally of the attacker is on the cell exactly opposite the attacker
# along an orthogonal axis (defender between attacker and ally).
func _is_flanking(attacker: Unit, defender: Unit) -> bool:
	var dx := defender.grid_pos.x - attacker.grid_pos.x
	var dy := defender.grid_pos.y - attacker.grid_pos.y
	if (dx == 0) == (dy == 0):
		return false  # not aligned on a single axis
	var step := Vector2i(sign(dx), sign(dy))
	var opposite := defender.grid_pos + step
	var allies := player_units if attacker.team == 0 else enemy_units
	for a: Unit in allies:
		if a != attacker and a.is_alive() and a.grid_pos == opposite:
			return true
	return false

# Terrain damage multiplier: hill boosts the attacker, forest protects the defender.
func _terrain_mult(attacker: Unit, defender: Unit) -> float:
	var m := 1.0
	if attacker.grid_pos in hills:
		m *= HILL_ATTACK
	if defender.grid_pos in forests:
		m *= FOREST_DEFENSE
	return m

# Deterministic damage (terrain only, no crit/flank) — used by the forecast UI.
func _attack_damage(attacker: Unit, defender: Unit) -> int:
	return maxi(1, int(round(attacker.get_damage() * _terrain_mult(attacker, defender))))

# Returns { "damage": int, "crit": bool, "flank": bool, "cover": bool }.
# Crit and flank don't stack — crit takes precedence. Terrain (forest cover,
# hill high-ground) multiplies on top of whichever bonus applies.
func _resolve_damage(attacker: Unit, defender: Unit) -> Dictionary:
	var base := attacker.get_damage()
	var crit_chance: float = CRIT_CHANCE + attacker.get_crit_chance_bonus()
	var crit := randf() < crit_chance
	var flank := _is_flanking(attacker, defender)
	var mult: float = 1.0
	if crit:
		mult = CRIT_MULT
	elif flank:
		mult = FLANK_MULT
	mult *= _terrain_mult(attacker, defender)   # forest cover + hill high-ground
	var cover: bool = defender.grid_pos in forests
	# Defender-side mitigation (Ironhide upgrade)
	mult *= defender.get_damage_taken_mult()
	return {
		"damage": maxi(1, int(round(base * mult))),
		"crit":   crit,
		"flank":  flank and not crit,
		"cover":  cover,
	}

func _do_attack(attacker: Unit, defender: Unit) -> void:
	var res := _resolve_damage(attacker, defender)
	var dmg: int = res["damage"]
	_lunge(attacker, defender)
	defender.take_damage(dmg)
	Sfx.play("attack")
	# Stat tracking — bucket by attacker identity so we can pick an MVP later
	var aid: int = attacker.get_instance_id()
	if attacker.team == 0:
		_damage_dealt_by[aid] = int(_damage_dealt_by.get(aid, 0)) + dmg
	else:
		_damage_taken_total += dmg
		# Enemy hit a player unit — extra "hit" cue + red flash, intensity ∝ damage.
		Sfx.play("hit")
		_flash_hurt(dmg, defender.max_hp)
	if res["crit"]:
		defender.show_combat_label("CRIT!", Color(1.0, 0.45, 0.20))
		_log_event("%s ⚡ CRIT %d → %s" % [_unit_label(attacker), dmg, _unit_label(defender)])
		_shake_grid(4.5)
	elif res["flank"]:
		defender.show_combat_label("FLANKED!", Color(1.0, 0.85, 0.30))
		_log_event("%s ⚔ flank %d → %s" % [_unit_label(attacker), dmg, _unit_label(defender)])
		_shake_grid(3.5)
	else:
		_log_event("%s hits %s for %d" % [_unit_label(attacker), _unit_label(defender), dmg])
		_shake_grid(2.5)
	# Cover tag — shown alongside whatever main combat label fired
	if res["cover"] and not (res["crit"]):
		defender.show_combat_label("COVER −25%", Color(0.45, 0.85, 0.45))
	if not defender.is_alive():
		_kill_punch()
		Sfx.play("kill")
		defender.play_death_animation()
		defender.modulate = DEATH_TINT
		Sfx.play("death")
		_log_event("%s is defeated" % _unit_label(defender))
		if attacker.team == 0:
			_kills_by[attacker.get_instance_id()] = int(_kills_by.get(attacker.get_instance_id(), 0)) + 1
	else:
		# Boss enrage check: cross the HP threshold once → permanent buff
		_check_enrage(defender)
	# Venom relic: melee hits poison the target
	if GameManager.has_relic("venom") and attacker.team == 0 \
			and _chebyshev(attacker.grid_pos, defender.grid_pos) <= 1 and defender.is_alive():
		defender.apply_poison(2)
		defender.show_status_popup("POISONED", Color(0.45, 0.85, 0.30))
	# Enemy roster/positions may have changed — refresh the threat overlay.
	_recompute_threat()

# If the defender is a boss whose HP just crossed its enrage threshold,
# flip the enraged flag and announce it loudly.
func _check_enrage(u: Unit) -> void:
	if u.enraged:
		return
	var udata: Dictionary = GameManager.UNIT_TYPES[u.unit_type]
	if not bool(udata.get("is_boss", false)):
		return
	var thresh: float = float(udata.get("enrage_threshold", 0.5))
	if float(u.hp) / float(u.max_hp) > thresh:
		return
	u.enraged = true
	u.show_status_popup("ENRAGED!", Color(1.0, 0.30, 0.20))
	u.show_combat_label("+%d DMG  +%d MOVE" % [
			int(udata.get("enrage_damage_bonus", 0)),
			int(udata.get("enrage_move_bonus", 0))
		], Color(1.0, 0.55, 0.30))
	_shake_grid(8.0)
	_log_event("⚠ %s is ENRAGED!" % _unit_label(u))
	_show_toast("The %s ENRAGES!" % udata.get("name", "Boss"), Color(1.0, 0.45, 0.25))
	# Tint the body more aggressively
	if u._body:
		u._body.modulate = Color(1.45, 0.55, 0.55)

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

# Red flash over the grid when the player takes a hit. Intensity scales
# with the proportion of max-HP just lost (capped) so chip damage barely
# registers but a fat crit reads as a screen punch.
func _flash_hurt(dmg: int, defender_max_hp: int) -> void:
	if _hurt_overlay == null:
		return
	var ratio: float = 0.0
	if defender_max_hp > 0:
		ratio = clamp(float(dmg) / float(defender_max_hp), 0.0, 1.0)
	# Map 0..1 ratio onto 0.08..0.30 alpha so even small hits are visible.
	var peak: float = 0.08 + ratio * 0.22
	var tw := create_tween()
	tw.tween_property(_hurt_overlay, "color:a", peak, 0.05)
	tw.tween_property(_hurt_overlay, "color:a", 0.0,  0.32)

# Kill-feel punch: hard shake plus a brief slow-mo so the moment lands.
# Uses an ignore_time_scale timer so 0.20 seconds of real time always pass
# regardless of the fast-forward toggle or the slow scale we just set.
func _kill_punch() -> void:
	_shake_grid(8.0)
	var base_scale: float = FAST_MULT if _fast_mode else 1.0
	Engine.time_scale = base_scale * 0.25
	await get_tree().create_timer(0.20, true, false, true).timeout
	# Only restore if no later call already changed it (best-effort)
	Engine.time_scale = FAST_MULT if _fast_mode else 1.0

func _commit_player_unit_turn() -> void:
	selected_unit.has_acted = true
	selected_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
	selected_unit           = null
	move_cells.clear()
	attack_cells.clear()
	ability_cells.clear()

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

# ---------------------------------------------------------------------------
# Abilities (once per battle per unit)
# ---------------------------------------------------------------------------
# Cells a unit may target/use its ability on right now (empty = unusable).
func _ability_target_cells(unit: Unit, id: String) -> Array[Vector2i]:
	match id:
		"dash":
			# Usable if it can still move somewhere
			return _get_move_cells(unit)
		"pierce":
			# Any enemy within attack range (the behind-hit is a bonus)
			return _get_attack_cells(unit, enemy_units)
		"bash":
			# Adjacent (incl. diagonal) enemies only
			var cells: Array[Vector2i] = []
			for t: Unit in enemy_units:
				if t.is_alive() and _chebyshev(unit.grid_pos, t.grid_pos) <= 1:
					cells.append(t.grid_pos)
			return cells
		"heal_ally":
			# Wounded allies within 2 tiles (excluding self)
			var allies := player_units if unit.team == 0 else enemy_units
			var cells: Array[Vector2i] = []
			for a: Unit in allies:
				if a != unit and a.is_alive() and a.hp < a.max_hp \
						and _chebyshev(unit.grid_pos, a.grid_pos) <= 2:
					cells.append(a.grid_pos)
			return cells
	return []

func _on_ability_pressed() -> void:
	if not selected_unit or selected_unit.ability_used:
		return
	var id: String = selected_unit.get_ability().get("id", "")
	if id == "dash":
		# Grant a second move immediately
		selected_unit.ability_used = true
		Sfx.play("ability")
		selected_unit.show_status_popup("DASH!", Color(0.95, 0.85, 0.2))
		move_cells   = _get_move_cells(selected_unit)
		attack_cells.clear()
		ability_cells.clear()
		phase = Phase.PLAYER_SELECT_MOVE
		_update_ui()
	else:
		# Targeted abilities: enter ability-targeting phase
		ability_cells = _ability_target_cells(selected_unit, id)
		attack_cells.clear()
		phase = Phase.PLAYER_SELECT_ABILITY
		_update_ui()

func _try_ability(cell: Vector2i) -> void:
	if cell not in ability_cells:
		return
	var id: String = selected_unit.get_ability().get("id", "")

	# Healer targets a friendly unit
	if id == "heal_ally":
		for a: Unit in player_units:
			if a.is_alive() and a.grid_pos == cell:
				a.hp = mini(a.max_hp, a.hp + GameManager.HEAL_ABILITY_AMOUNT)
				a._refresh_hp_bar()
				a.show_status_popup("+%d" % GameManager.HEAL_ABILITY_AMOUNT, Color(0.4, 0.95, 0.5))
				Sfx.play("heal")
				break
		selected_unit.ability_used = true
		ability_cells.clear()
		_commit_player_unit_turn()
		return

	var target: Unit = null
	for t: Unit in enemy_units:
		if t.is_alive() and t.grid_pos == cell:
			target = t
			break
	if target == null:
		return

	match id:
		"pierce":
			_do_attack(selected_unit, target)
			# Hit the unit directly behind the target (same direction)
			var d := target.grid_pos - selected_unit.grid_pos
			var step := Vector2i(signi(d.x), signi(d.y))
			var behind := target.grid_pos + step
			for t: Unit in enemy_units:
				if t.is_alive() and t.grid_pos == behind:
					_do_attack(selected_unit, t)
					break
		"bash":
			_do_attack(selected_unit, target)
			if target.is_alive():
				target.stunned = true
				target.show_status_popup("STUNNED!", STUN_COLOR)
				Sfx.play("stun")
				_recompute_threat()   # stunned enemy no longer threatens

	selected_unit.ability_used = true
	ability_cells.clear()
	_commit_player_unit_turn()

func _on_end_turn() -> void:
	# Confirmation gate — if there are still units that haven't acted, first
	# press just arms the button. The next press within END_TURN_ARM_WINDOW
	# actually skips them.
	var unacted: int = _unacted_player_count()
	if unacted > 0 and phase == Phase.PLAYER_SELECT_UNIT:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _end_turn_armed_at > END_TURN_ARM_WINDOW:
			_end_turn_armed_at = now
			_refresh_end_turn_button()
			_show_toast(
				"%d unit%s still ready — press End Turn again to skip them" % [
					unacted, "" if unacted == 1 else "s"
				],
				Color(0.95, 0.75, 0.30)
			)
			return
	_end_turn_armed_at = -1.0

	if selected_unit:
		selected_unit.has_acted = true
		selected_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
		selected_unit           = null
	move_cells.clear()
	attack_cells.clear()
	ability_cells.clear()

	if _all_dead(enemy_units):
		_trigger_win()
		return

	_mark_all_acted(player_units)
	_run_all_remaining_ai_units()

func _unacted_player_count() -> int:
	var n := 0
	for u: Unit in player_units:
		if u.is_alive() and not u.has_acted:
			n += 1
	return n

# Updates the End Turn button label + tint based on how many of the player's
# units still have a pending action this round.
func _refresh_end_turn_button() -> void:
	if _end_btn == null:
		return
	var n: int = _unacted_player_count()
	var armed: bool = _end_turn_armed_at >= 0.0 \
			and (Time.get_ticks_msec() / 1000.0 - _end_turn_armed_at) <= END_TURN_ARM_WINDOW
	if n == 0:
		_end_btn.text = "End Turn"
		_end_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	elif armed:
		_end_btn.text = "Confirm: skip %d unit%s?" % [n, "" if n == 1 else "s"]
		_end_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
	else:
		_end_btn.text = "End Turn  (%d ready)" % n
		_end_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))

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
		Sfx.play("capture")
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
	await get_tree().create_timer(0.35).timeout

	if _all_dead(enemy_units):
		_trigger_win()
		return

	var ai_unit: Unit = null
	for u: Unit in enemy_units:
		if u.is_alive() and not u.has_acted:
			ai_unit = u
			break

	if ai_unit == null:
		# All alive enemies have acted for this round — check full-round completion
		_check_round_complete()
		return

	# Stunned units lose this activation (it counts as their turn)
	if _consume_stun(ai_unit):
		_check_round_complete()
		return

	await _ai_act(ai_unit)
	ai_unit.has_acted = true
	ai_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
	queue_redraw()

	if _all_dead(player_units):
		_trigger_loss()
		return

	_check_round_complete()

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
		_start_new_round()
		return

	await get_tree().create_timer(0.35).timeout

	var ai_unit: Unit = unacted[0]
	if _consume_stun(ai_unit):
		_execute_remaining_ai_units()
		return

	await _ai_act(ai_unit)
	ai_unit.has_acted = true
	ai_unit.modulate  = Color(0.58, 0.58, 0.58, 1.0)
	queue_redraw()

	if _all_dead(player_units):
		_trigger_loss()
		return

	_execute_remaining_ai_units()

# ---------------------------------------------------------------------------
# Round completion helpers
# ---------------------------------------------------------------------------
func _start_new_round() -> void:
	_round_count += 1
	_reset_acted_flags(player_units)
	_reset_acted_flags(enemy_units)
	_recompute_threat()   # stuns cleared at round start may re-enable threats
	phase = Phase.PLAYER_SELECT_UNIT
	_update_ui()

func _check_round_complete() -> void:
	if _all_dead(enemy_units):
		_trigger_win()
		return
	if _all_dead(player_units):
		_trigger_loss()
		return

	var player_done := not player_units.any(func(u: Unit) -> bool: return u.is_alive() and not u.has_acted)
	var enemy_done  := not enemy_units.any(func(u: Unit) -> bool: return u.is_alive() and not u.has_acted)

	if player_done and enemy_done:
		_start_new_round()
	elif player_done:
		# Player exhausted; remaining enemies finish the round
		_show_toast("All your units have acted — enemy continues…", Color(0.90, 0.82, 0.25))
		phase = Phase.AI_ACTING
		_update_ui()
		_execute_remaining_ai_units()
	else:
		# Player still has units to act
		phase = Phase.PLAYER_SELECT_UNIT
		_update_ui()

# ---------------------------------------------------------------------------
# AI decision-making (objectives + combat)
#
# Strategy: enumerate every viable (move_cell, attack_target) pair and score
# them. Higher score wins. Falls back to objective/closing behaviour when no
# attack is possible this turn.
#
# Scoring rewards:
#   • Lethal hits (would kill the target)
#   • Hitting low-HP targets
#   • Ranged units staying away from melee threats (kiting)
#   • Standing on a capturable objective (capture bonus)
# ---------------------------------------------------------------------------
func _ai_act(ai_unit: Unit) -> void:
	# Healers prioritise patching up wounded allies
	if _try_ai_heal(ai_unit):
		return

	var damage := ai_unit.get_damage()
	var range_val := ai_unit.get_attack_range()
	var is_ranged := range_val >= 2

	# All cells this unit could move to (plus staying in place)
	var move_options: Array[Vector2i] = _get_move_cells(ai_unit)
	move_options.append(ai_unit.grid_pos)

	var best_score: float = -INF
	var best_cell: Vector2i = ai_unit.grid_pos
	var best_target: Unit = null

	for cell: Vector2i in move_options:
		# Score this cell on its own merits (capture / kiting), independent of attack
		var cell_value: float = _score_cell(ai_unit, cell, is_ranged)

		for t: Unit in player_units:
			if not t.is_alive():
				continue
			if _chebyshev(cell, t.grid_pos) > range_val:
				continue
			var hit_score: float = cell_value + 1000.0
			# Hitting a low-HP target is better; killing is best of all
			if damage >= t.hp:
				hit_score += 2000.0 + t.max_hp  # finishing high-HP targets is extra valuable
			else:
				hit_score += float(damage) - float(t.hp) * 0.4
			# Per-class target preference (scouts/archers snipe the wounded)
			hit_score += _target_priority(ai_unit, t)

			if hit_score > best_score:
				best_score  = hit_score
				best_cell   = cell
				best_target = t

	# Execute chosen move (only if we actually have a target — otherwise leave
	# movement to the fallback so we don't end up moving twice)
	if best_target != null:
		if best_cell != ai_unit.grid_pos:
			var origin := ai_unit.grid_pos
			ai_unit.grid_pos = best_cell
			await _animate_unit_to(ai_unit, origin, best_cell).finished
		_check_capture(ai_unit)
		_do_attack(ai_unit, best_target)
		return

	# Fallback — no target in range from any reachable cell. Move toward an
	# uncaptured objective if it's the closest goal, else close on nearest enemy.
	var combat_target := _nearest_alive(ai_unit, player_units)
	var obj_cell      := _nearest_capturable_obj(ai_unit)
	var target_cell: Vector2i = Vector2i(-1, -1)
	if obj_cell != Vector2i(-1, -1):
		var od := _manhattan(ai_unit.grid_pos, obj_cell)
		var ed: int = 9999 if combat_target == null else _manhattan(ai_unit.grid_pos, combat_target.grid_pos)
		target_cell = obj_cell if od <= ed else combat_target.grid_pos
	elif combat_target != null:
		target_cell = combat_target.grid_pos

	if target_cell != Vector2i(-1, -1):
		var closer := _best_move_to_cell(ai_unit, target_cell)
		if closer != ai_unit.grid_pos:
			var origin := ai_unit.grid_pos
			ai_unit.grid_pos = closer
			await _animate_unit_to(ai_unit, origin, closer).finished
			_recompute_threat()   # enemy position changed
		_check_capture(ai_unit)
		# Opportunistic attack after closing
		if combat_target != null and combat_target.is_alive() \
				and _chebyshev(ai_unit.grid_pos, combat_target.grid_pos) <= range_val:
			_do_attack(ai_unit, combat_target)

# Position-only score: rewards capturable objectives and (for ranged units)
# distance from melee player threats. Per-class personalities:
#   • soldier  — neutral, charges and brawls
#   • archer   — strongest kiter, hates being adjacent to melee
#   • scout    — assassin, prefers being adjacent to wounded targets
#   • warlord  — boss, ignores positional caution
func _score_cell(ai_unit: Unit, cell: Vector2i, is_ranged: bool) -> float:
	var score := 0.0
	for obj: Dictionary in objectives:
		if obj["grid_pos"] == cell and int(obj["owner"]) != ai_unit.team:
			score += 60.0
	# Forest cover is universally useful — defenders take 25% less, so
	# every personality prefers ending its turn in a forest (small bonus,
	# big enough to break ties but not enough to skip a clean attack)
	if cell in forests:
		score += 15.0

	var personality: String = ai_unit.unit_type
	# Boss never kites and never camps objectives — it hunts the party.
	if personality == "warlord":
		var closest_d: int = 99
		for p: Unit in player_units:
			if not p.is_alive():
				continue
			closest_d = mini(closest_d, _chebyshev(cell, p.grid_pos))
		# Reward closing the gap (1 tile away ideal for melee boss)
		score += float(max(0, 8 - closest_d)) * 4.0
		return score

	if is_ranged:
		# Archer kites HARDER than the generic ranged baseline
		var adj_penalty: float = -50.0 if personality == "archer" else -35.0
		var spacing_bonus: float = 12.0 if personality == "archer" else 5.0
		for p: Unit in player_units:
			if not p.is_alive():
				continue
			if p.get_attack_range() <= 1:
				var d := _chebyshev(cell, p.grid_pos)
				if d <= 1:
					score += adj_penalty
				elif d == 2:
					score += spacing_bonus
	elif personality == "scout":
		# Scouts WANT to be next to a wounded target — gives them a tiny
		# offensive bias toward closing for the kill rather than caution
		for p: Unit in player_units:
			if not p.is_alive():
				continue
			if _chebyshev(cell, p.grid_pos) == 1 and p.hp < p.max_hp * 0.6:
				score += 10.0
	return score

# Per-class target-selection bias added to hit_score. Scouts and archers
# strongly prefer wounded targets (snipers/assassins); soldiers and the
# boss go for whatever's already efficient.
func _target_priority(ai_unit: Unit, target: Unit) -> float:
	var wound_ratio: float = 1.0 - float(target.hp) / float(max(1, target.max_hp))
	match ai_unit.unit_type:
		"scout":   return wound_ratio * 150.0
		"archer":  return wound_ratio * 80.0
		"warlord": return wound_ratio * 100.0
		_:         return 0.0

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

# BFS path from `start` to `end` (orthogonal, mountain-aware, treating only
# `excluded` as walkable among unit-occupied cells). Returns the list of
# cells AFTER start, ending at `end` — i.e. the cells the unit walks through.
# Returns empty if no path is found.
func _bfs_path(start: Vector2i, end: Vector2i, excluded: Unit) -> Array[Vector2i]:
	if start == end:
		return []
	var blockers := _occupied_cells_except(excluded)
	var came_from: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var found := false
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		if pos == end:
			found = true
			break
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := pos + dir
			if next in came_from:
				continue
			if not _valid_cell(next) or next in mountains:
				continue
			# Blockers are passable only as the final destination
			if next != end and next in blockers:
				continue
			came_from[next] = pos
			queue.append(next)
	if not found:
		return []
	# Reconstruct (excluding the starting cell)
	var path: Array[Vector2i] = []
	var cur := end
	while cur != start:
		path.insert(0, cur)
		cur = came_from[cur]
	return path

# Kick off a walk animation for `unit` from `origin` to `dest`. Logical
# grid_pos must already be set to `dest` by the caller. Returns the tween
# so AI flows can `await tw.finished`.
func _animate_unit_to(unit: Unit, origin: Vector2i, dest: Vector2i) -> Tween:
	var path := _bfs_path(origin, dest, unit)
	# Fallback to a straight slide if no path exists (e.g. for abilities)
	if path.is_empty():
		path = [dest]
	var pts: Array = []
	for c: Vector2i in path:
		pts.append(Vector2(c.x * TILE_SIZE + TILE_SIZE / 2.0, c.y * TILE_SIZE + TILE_SIZE / 2.0))
	return unit.animate_move_along(pts)

func _get_attack_cells(attacker: Unit, targets: Array[Unit]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var range_val := attacker.get_attack_range()
	for t: Unit in targets:
		if t.is_alive() and _chebyshev(attacker.grid_pos, t.grid_pos) <= range_val:
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

# Most-wounded living ally (by missing HP), excluding the unit itself.
func _most_wounded_ally(unit: Unit, allies: Array[Unit]) -> Unit:
	var worst: Unit = null
	var most_missing := 0
	for a: Unit in allies:
		if a != unit and a.is_alive():
			var missing := a.max_hp - a.hp
			if missing > most_missing:
				most_missing = missing
				worst = a
	return worst

# Enemy healer behaviour: move toward and heal the most-wounded ally.
# Returns true when it has taken the healer's action this turn.
func _try_ai_heal(ai_unit: Unit) -> bool:
	if ai_unit.get_ability().get("id", "") != "heal_ally" or ai_unit.ability_used:
		return false
	var wounded := _most_wounded_ally(ai_unit, enemy_units)
	if wounded == null:
		return false  # nobody hurt — behave like a normal unit
	if _chebyshev(ai_unit.grid_pos, wounded.grid_pos) > 2:
		var best := _best_move_to_cell(ai_unit, wounded.grid_pos)
		if best != ai_unit.grid_pos:
			ai_unit.grid_pos = best
			ai_unit.update_visual_position()
		_check_capture(ai_unit)
	if _chebyshev(ai_unit.grid_pos, wounded.grid_pos) <= 2:
		wounded.hp = mini(wounded.max_hp, wounded.hp + GameManager.HEAL_ABILITY_AMOUNT)
		wounded._refresh_hp_bar()
		wounded.show_status_popup("+%d" % GameManager.HEAL_ABILITY_AMOUNT, Color(0.4, 0.95, 0.5))
		ai_unit.ability_used = true
	return true

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

# Chebyshev (chessboard) distance — used for attack range so a unit can hit
# diagonally adjacent targets, not just orthogonal ones.
func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))

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
		if not u.is_alive():
			continue
		# Damage-over-time ticks at the start of the unit's round (may kill)
		_tick_statuses(u)
		if not u.is_alive():
			continue
		u.has_acted = false
		u.modulate  = Color(1.0, 1.0, 1.0, 1.0)
		# A unit that began the round stunned loses it
		_consume_stun(u)

# Apply poison/burn damage-over-time and lava terrain burn to a unit.
func _tick_statuses(u: Unit) -> void:
	# Standing in lava refreshes burn
	if u.grid_pos in lava and u.is_alive():
		u.apply_burn(2)
	if u.poison_turns > 0:
		u.take_damage(POISON_DMG)
		u.show_status_popup("-%d poison" % POISON_DMG, Color(0.45, 0.85, 0.30))
		u.poison_turns -= 1
	if u.is_alive() and u.burn_turns > 0:
		u.take_damage(BURN_DMG)
		u.show_status_popup("-%d burn" % BURN_DMG, Color(1.0, 0.5, 0.15))
		u.burn_turns -= 1
	if not u.is_alive():
		u.modulate = DEATH_TINT

# If the unit is stunned, clear it and mark it as having spent its turn.
# Returns true when the activation was consumed by the stun.
func _consume_stun(u: Unit) -> bool:
	if not u.stunned:
		return false
	u.stunned   = false
	u.has_acted = true
	u.modulate  = Color(0.58, 0.58, 0.58, 1.0)
	u.show_status_popup("STUNNED!", STUN_COLOR)
	return true

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
var _relic_reward: String = ""

func _trigger_win() -> void:
	phase = Phase.BATTLE_WON
	Sfx.play("victory")
	_persist_roster()
	_gold_reward = GameManager.battle_gold_reward(
		GameManager.pending_battle_tier, GameManager.pending_battle_elite)
	GameManager.add_gold(_gold_reward)
	GameManager.register_battle_won(GameManager.pending_battle_elite)
	# Elite battles award a random relic
	_relic_reward = ""
	if GameManager.pending_battle_elite:
		_relic_reward = GameManager.grant_random_relic()
	Sfx.play("win")
	_update_ui()
	_show_result_overlay(true)

# Survivors (incl. objective-spawned reinforcements) carry forward with their
# remaining HP; the fallen are dropped from the roster — permadeath.
func _persist_roster() -> void:
	var survivors: Array[Dictionary] = []
	for u: Unit in player_units:
		if u.is_alive():
			survivors.append({
				"type": u.unit_type,
				"hp":   u.hp,
				"upgrades": u.upgrades.duplicate(),
			})
	GameManager.set_roster(survivors)

func _trigger_loss() -> void:
	phase = Phase.BATTLE_LOST
	Sfx.play("lose")
	_update_ui()
	_show_result_overlay(false)

func _show_result_overlay(won: bool) -> void:
	var panel := Panel.new()
	panel.position = Vector2(220.0, 110.0)
	panel.size     = Vector2(840.0, 500.0)

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
	title.add_theme_font_size_override("font_size", 48)
	title.modulate  = Color(0.95, 0.85, 0.20) if won else Color(0.95, 0.30, 0.30)
	title.position  = Vector2(330.0, 22.0)
	panel.add_child(title)

	var sub := Label.new()
	if won:
		sub.text = "All enemies defeated.   +%d gold  (total %d)\nBattles won this run: %d   ·   Best ever: %d" % [
			_gold_reward, GameManager.gold,
			GameManager.battles_won, GameManager.best_streak_ever
		]
		if _relic_reward != "":
			sub.text += "\nRelic found: %s — %s" % [
				GameManager.RELICS[_relic_reward]["name"], GameManager.RELICS[_relic_reward]["desc"]]
	else:
		sub.text = "All your units were destroyed.\nFinal streak: %d battles won" % GameManager.battles_won
	sub.add_theme_font_size_override("font_size", 16)
	sub.modulate  = Color(0.72, 0.72, 0.72)
	sub.position  = Vector2(180.0, 90.0)
	panel.add_child(sub)

	# Battle stats scoreboard — added for both win and loss
	_build_stats_block(panel, won)

	if won and not GameManager.player_roster.is_empty():
		_build_upgrade_picker(panel)
	else:
		_build_post_battle_buttons(panel, won)

# Reward step: 3 random upgrade cards. Click → choose a survivor.
func _build_upgrade_picker(panel: Panel) -> void:
	var header := Label.new()
	header.text = "Choose a Reward"
	header.add_theme_font_size_override("font_size", 22)
	header.modulate = Color(0.95, 0.90, 0.45)
	header.position = Vector2(310.0, 200.0)
	panel.add_child(header)

	var hint := Label.new()
	hint.text = "Pick an upgrade card, then assign it to a surviving unit."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.65, 0.65, 0.65)
	hint.position = Vector2(225.0, 232.0)
	panel.add_child(hint)

	var choices := GameManager.random_upgrade_choices(3)
	for i in range(choices.size()):
		var id: String = choices[i]
		var data: Dictionary = GameManager.UPGRADE_TYPES[id]
		var card := Button.new()
		card.position = Vector2(60.0 + i * 250.0, 258.0)
		card.size     = Vector2(220.0, 110.0)
		card.text     = "%s\n\n%s" % [data["name"], data["desc"]]
		card.add_theme_font_size_override("font_size", 15)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.16, 0.16, 0.22)
		st.border_color = data["color"]
		st.border_width_left = 2
		st.border_width_right = 2
		st.border_width_top = 2
		st.border_width_bottom = 2
		st.corner_radius_top_left = 6
		st.corner_radius_top_right = 6
		st.corner_radius_bottom_left = 6
		st.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("normal", st)
		card.add_theme_stylebox_override("hover", st)
		card.add_theme_stylebox_override("pressed", st)
		card.pressed.connect(_on_upgrade_card_picked.bind(panel, id))
		panel.add_child(card)

	var skip := Button.new()
	skip.text = "Skip reward — Continue"
	skip.position = Vector2(290.0, 430.0)
	skip.size     = Vector2(260.0, 44.0)
	skip.add_theme_font_size_override("font_size", 15)
	skip.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	)
	skip.name = "SkipBtn"
	panel.add_child(skip)

# Card clicked: replace cards with survivor-picker buttons
func _on_upgrade_card_picked(panel: Panel, upgrade_id: String) -> void:
	# Strip out the upgrade-card buttons and the skip button
	for child in panel.get_children():
		if child is Button:
			child.queue_free()
	# Update header
	for child in panel.get_children():
		if child is Label and (child as Label).text.begins_with("Choose"):
			(child as Label).text = "Apply '%s' to which unit?" % \
					GameManager.UPGRADE_TYPES[upgrade_id]["name"]

	var roster := GameManager.player_roster
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var udata: Dictionary = GameManager.UNIT_TYPES[entry["type"]]
		var max_hp: int = GameManager.unit_effective_max_hp(entry)
		var ups: Array = entry.get("upgrades", [])
		var label_txt: String = "%s\nHP %d/%d" % [udata["name"], int(entry["hp"]), max_hp]
		if ups.size() > 0:
			label_txt += "\n✦ %d upgrade%s" % [ups.size(), "" if ups.size() == 1 else "s"]
		var btn := Button.new()
		# Three-per-row grid
		var col := i % 3
		var row := i / 3
		btn.position = Vector2(70.0 + col * 250.0, 270.0 + row * 90.0)
		btn.size     = Vector2(220.0, 80.0)
		btn.text     = label_txt
		btn.add_theme_font_size_override("font_size", 14)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.14, 0.18, 0.22)
		st.border_color = udata["color"]
		st.border_width_left = 2
		st.border_width_right = 2
		st.border_width_top = 2
		st.border_width_bottom = 2
		btn.add_theme_stylebox_override("normal", st)
		btn.pressed.connect(_on_upgrade_assigned.bind(i, upgrade_id))
		panel.add_child(btn)

func _on_upgrade_assigned(roster_index: int, upgrade_id: String) -> void:
	GameManager.apply_upgrade(roster_index, upgrade_id)
	get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

# Defeat / fallback buttons (no upgrade flow)
func _build_post_battle_buttons(panel: Panel, won: bool) -> void:
	var btn1 := Button.new()
	btn1.position = Vector2(165.0, 320.0)
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
	btn2.position = Vector2(455.0, 320.0)
	btn2.size     = Vector2(220.0, 60.0)
	btn2.add_theme_font_size_override("font_size", 18)
	btn2.pressed.connect(func() -> void:
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	)
	panel.add_child(btn2)

# Battle scoreboard — rounds taken, total damage dealt/taken, MVP unit.
# Inserted into the result panel between the subtitle and the reward picker.
func _build_stats_block(panel: Panel, _won: bool) -> void:
	# Identify the MVP: the player unit (alive or dead) that dealt the most damage.
	# Falls back to most kills if everyone dealt zero.
	var mvp_name: String = ""
	var mvp_dmg: int = 0
	var mvp_kills: int = 0
	var total_dealt: int = 0
	for u: Unit in player_units:
		var id: int = u.get_instance_id()
		var d: int = int(_damage_dealt_by.get(id, 0))
		var k: int = int(_kills_by.get(id, 0))
		total_dealt += d
		if d > mvp_dmg or (d == mvp_dmg and k > mvp_kills):
			mvp_dmg   = d
			mvp_kills = k
			mvp_name  = GameManager.UNIT_TYPES[u.unit_type]["name"]

	var line1 := "⏱ %d round%s   ·   ⚔ %d dmg dealt   ·   🛡 %d dmg taken" % [
		_round_count, "" if _round_count == 1 else "s",
		total_dealt, _damage_taken_total
	]
	var mvp_line := ""
	if mvp_name != "" and mvp_dmg > 0:
		mvp_line = "★ MVP: %s — %d dmg, %d kill%s" % [
			mvp_name, mvp_dmg, mvp_kills, "" if mvp_kills == 1 else "s"
		]

	var lbl := Label.new()
	lbl.text = line1 + ("\n" + mvp_line if mvp_line != "" else "")
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.82, 0.84, 0.78)
	lbl.position = Vector2(120.0, 145.0)
	lbl.size     = Vector2(600.0, 50.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
