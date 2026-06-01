extends Node2D

# Real-time-with-pause skirmish mode. Standalone — does not touch the
# turn-based campaign state, the run/relic systems, or GameManager mutation.
# Designed to be reached from the title screen as a "Skirmish" button and to
# return there when finished.
#
# Controls:
#   - SPACE        : start battle / toggle pause
#   - Left-click   : select a friendly regiment (clears prior selection)
#   - Right-click  : queue an order with the selected regiment
#                       on empty ground → move there
#                       on an enemy regiment → attack it
#   - Esc          : return to title

const UITheme := preload("res://src/ui/ui_theme.gd")
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
const PICK_RADIUS_PADDING: float = 14.0
const OPENING_AI_DELAY: float = 2.0

var player_units: Array = []   # Array[RTUnit]
var enemy_units:  Array = []
var selected_units: Array = []          # Array[RTUnit]
var _hovered_unit: RTUnit = null

var _paused: bool = true
var _settings_overlay: Control = null
var _help_overlay: Control = null
var _battle_started: bool = false

const HELP_BODY: String = "Real-time-with-pause tactics — command regiments of soldiers.\n\n- Left-drag: band-box select (Shift adds to the selection)\n- Right-click: move there, or attack the enemy regiment under the cursor\n- Idle regiments hold ground and auto-engage anything that comes in range\n- Orders can be queued while paused, then play out when you resume\n\nSPACE start / pause  ·  R restart (when ended)  ·  Esc menu  ·  H help"
var _player_has_issued_order: bool = false
var _ended: bool = false

# --- Campaign integration (battle_mode "rt") -------------------------------
const CAMPAIGN_RT_MAP: Dictionary = {
	"soldier": "soldier", "archer": "archer", "scout": "scout", "healer": "healer",
	"knight": "scout", "mage": "archer", "guardian": "healer",
	"warlord": "soldier", "pyromancer": "archer", "juggernaut": "healer",
}
var _campaign: bool = false
var _campaign_lost: bool = false
var _campaign_relic: String = ""
var _campaign_reward_gold: int = 0

# Drag-rectangle selection state
var _drag_active: bool = false
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _drag_additive: bool = false        # shift-held → add to selection
const DRAG_THRESHOLD: float = 8.0       # pixels of motion to count as a drag

# Transient feedback markers — small visual pings spawned when an order is
# issued. Each is {pos: Vector2, age: float, lifetime: float, color: Color}.
var _waypoints: Array = []

# Enemy AI re-targeting cadence — every N seconds, idle/lost enemies pick
# the nearest living player regiment to advance on. Kept slow so orders
# feel deliberate rather than twitchy.
var _ai_retarget_timer: float = 0.0
var _opening_ai_timer: float = 0.0
const AI_RETARGET_PERIOD: float = 0.6

# UI nodes
var _status_label: Label
var _info_panel: Panel
var _info_label: Label
var _selection_label: Label
var _command_label: Label
var _result_label: Label
var _restart_hint_label: Label
var _drag_box_rect: ColorRect

func _set_passthrough(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_build_field()
	_build_ui()
	if GameManager.pending_rt:
		GameManager.pending_rt = false
		_campaign = true
		_spawn_campaign_armies()
	else:
		_spawn_armies()
	_refresh_ui()

# Campaign armies: your roster (left) vs the tier's enemy roster (right).
func _spawn_campaign_armies() -> void:
	var tier: int = GameManager.pending_battle_tier
	var elite: bool = GameManager.pending_battle_elite
	var roster: Array = GameManager.player_roster
	var n: int = maxi(1, roster.size())
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var rtype: String = String(CAMPAIGN_RT_MAP.get(String(entry["type"]), "soldier"))
		var y: float = 180.0 + float(i) * (380.0 / float(n))
		var u := _spawn_regiment(rtype, 0, Vector2(230.0 + float(i % 2) * 56.0, y))
		u.set_meta("roster_entry", entry)
		player_units.append(u)
	var etypes: Array = GameManager.get_battle_enemy_roster(tier, elite)
	var mult: float = GameManager.get_hp_multiplier(tier, elite)
	var en: int = maxi(1, etypes.size())
	for i in range(etypes.size()):
		var rtype2: String = String(CAMPAIGN_RT_MAP.get(String(etypes[i]), "soldier"))
		var y2: float = 180.0 + float(i) * (380.0 / float(en))
		var u2 := _spawn_regiment(rtype2, 1, Vector2(1050.0 - float(i % 2) * 56.0, y2))
		u2.max_hp = int(round(float(u2.max_hp) * mult))
		u2.hp = u2.max_hp
		enemy_units.append(u2)

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
	_set_passthrough(bg)
	add_child(bg)

	var field := ColorRect.new()
	field.color    = Color(0.16, 0.24, 0.18)
	field.position = FIELD_RECT.position
	field.size     = FIELD_RECT.size
	_set_passthrough(field)
	add_child(field)

func _build_ui() -> void:
	# Top status strip — pause indicator, hotkeys
	var top := ColorRect.new()
	top.color    = Color(0.07, 0.09, 0.13, 0.92)
	top.position = Vector2(0.0, 0.0)
	top.size     = Vector2(1280.0, 72.0)
	_set_passthrough(top)
	add_child(top)

	var title := Label.new()
	title.text = "SKIRMISH — Real-time tactics"
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(0.90, 0.85, 0.50)
	title.position = Vector2(20.0, 8.0)
	_set_passthrough(title)
	add_child(title)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.position = Vector2(20.0, 32.0)
	_set_passthrough(_status_label)
	add_child(_status_label)

	# Hover info card — stats for the unit under the cursor (either team)
	_info_panel = Panel.new()
	_info_panel.size = Vector2(280.0, 78.0)
	_info_panel.visible = false
	_set_passthrough(_info_panel)
	var ips := StyleBoxFlat.new()
	ips.bg_color = Color(0.06, 0.07, 0.10, 0.92)
	for side in ["left", "right", "top", "bottom"]:
		ips.set("border_width_" + side, 2)
	ips.border_color = Color(0.5, 0.55, 0.65)
	_info_panel.add_theme_stylebox_override("panel", ips)
	add_child(_info_panel)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.position = Vector2(10.0, 8.0)
	_set_passthrough(_info_label)
	_info_panel.add_child(_info_label)

	_command_label = Label.new()
	_command_label.text = "Select blue regiments, queue orders while paused, then press Space."
	_command_label.add_theme_font_size_override("font_size", 13)
	_command_label.modulate = Color(0.74, 0.78, 0.84)
	_command_label.position = Vector2(302.0, 39.0)
	_command_label.size = Vector2(530.0, 22.0)
	_set_passthrough(_command_label)
	add_child(_command_label)

	var hint := Label.new()
	hint.text = "Drag-box select  ·  Shift add  ·  Right-click queues move / attack"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.55, 0.55, 0.65)
	hint.position = Vector2(302.0, 16.0)
	_set_passthrough(hint)
	add_child(hint)

	add_child(UITheme.button("Start/Pause", Vector2(884.0, 14.0), Vector2(104.0, 40.0), Color(0.18, 0.26, 0.36), _on_pause_button, 14))
	add_child(UITheme.button("Restart", Vector2(1000.0, 14.0), Vector2(104.0, 40.0), Color(0.28, 0.22, 0.34), _on_restart_button, 15))
	add_child(UITheme.button("Menu", Vector2(1116.0, 14.0), Vector2(104.0, 40.0), Color(0.30, 0.20, 0.20), _on_menu_button, 15))

	# Bottom strip — selection info
	var bot := ColorRect.new()
	bot.color    = Color(0.07, 0.09, 0.13, 0.92)
	bot.position = Vector2(0.0, 660.0)
	bot.size     = Vector2(1280.0, 60.0)
	_set_passthrough(bot)
	add_child(bot)

	_selection_label = Label.new()
	_selection_label.add_theme_font_size_override("font_size", 15)
	_selection_label.modulate = Color(0.85, 0.90, 0.95)
	_selection_label.position = Vector2(20.0, 676.0)
	_selection_label.size     = Vector2(1240.0, 30.0)
	_set_passthrough(_selection_label)
	add_child(_selection_label)

	# Centred result banner (hidden until win/lose)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.position = Vector2(420.0, 290.0)
	_result_label.size     = Vector2(440.0, 80.0)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible  = false
	_set_passthrough(_result_label)
	add_child(_result_label)

	# Restart hint shown beneath the result banner — keeps the post-battle
	# loop one-keypress short.
	_restart_hint_label = Label.new()
	_restart_hint_label.add_theme_font_size_override("font_size", 18)
	_restart_hint_label.modulate = Color(0.80, 0.80, 0.88)
	_restart_hint_label.position = Vector2(420.0, 360.0)
	_restart_hint_label.size     = Vector2(440.0, 30.0)
	_restart_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart_hint_label.text     = "Press R to fight again  ·  Esc to return to menu"
	_restart_hint_label.visible  = false
	_set_passthrough(_restart_hint_label)
	add_child(_restart_hint_label)

	# Drag-rectangle visual — a thin translucent box rendered while the
	# player is band-boxing units. Hidden by default.
	_drag_box_rect              = ColorRect.new()
	_drag_box_rect.color        = Color(0.85, 0.95, 0.55, 0.16)
	_drag_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_box_rect.visible      = false
	_drag_box_rect.z_index      = 50
	add_child(_drag_box_rect)

func _on_pause_button() -> void:
	if not _ended:
		_set_paused(not _paused)

func _on_restart_button() -> void:
	get_tree().reload_current_scene()

func _on_menu_button() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _toggle_settings_menu() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	_settings_overlay = UITheme.pause_menu(_toggle_settings_menu, _on_menu_button)
	add_child(_settings_overlay)

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
		_age_waypoints(delta)
		queue_redraw()
		return
	if _paused:
		_update_hover()
		queue_redraw()
		return
	# All units share a flat neighbour list for cheap collision/separation.
	var all_units: Array = []
	all_units.append_array(player_units)
	all_units.append_array(enemy_units)
	if _player_has_issued_order:
		if _opening_ai_timer > 0.0:
			_opening_ai_timer = max(0.0, _opening_ai_timer - delta)
		else:
			_ai_tick(delta)
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
	_age_waypoints(delta)
	_update_hover()
	_refresh_ui()
	_check_end_condition()
	queue_redraw()

# ---------------------------------------------------------------------------
# Custom drawing — order feedback (waypoint markers, attack target rings)
# ---------------------------------------------------------------------------
func _draw() -> void:
	# Waypoint markers: a fading circle at the destination so the player can
	# see at a glance where each move order is heading.
	for wp: Dictionary in _waypoints:
		var t: float = clamp(1.0 - wp["age"] / wp["lifetime"], 0.0, 1.0)
		var c: Color = wp["color"]
		c.a *= t
		var rad: float = 10.0 + (1.0 - t) * 8.0
		draw_arc(wp["pos"], rad, 0.0, TAU, 24, c, 1.5, true)
		draw_circle(wp["pos"], 2.0, c)

	# Attack target indicator: a red ring around any enemy currently being
	# attacked by one of the player's selected units.
	for u: RTUnit in selected_units:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		if u.order != RTUnit.Order.ATTACK or u.attack_target == null \
				or not u.attack_target.is_alive():
			continue
		var tgt: RTUnit = u.attack_target
		draw_arc(tgt.position, tgt.radius + 5.0, 0.0, TAU, 32,
				Color(1.0, 0.30, 0.30, 0.70), 2.0, true)
		# Thin line from attacker to target so the relationship is unambiguous
		draw_line(u.position, tgt.position, Color(1.0, 0.30, 0.30, 0.35), 1.0, true)

# ---------------------------------------------------------------------------
# Enemy AI — minimalist "advance and engage". Periodically re-targets any
# enemy regiment that is idle or whose target has died, so the AI side keeps
# pressure on without needing per-unit scripting.
# ---------------------------------------------------------------------------
func _ai_tick(delta: float) -> void:
	_ai_retarget_timer -= delta
	if _ai_retarget_timer > 0.0:
		return
	_ai_retarget_timer = AI_RETARGET_PERIOD
	for u: RTUnit in enemy_units:
		if not u.is_alive():
			continue
		var needs_target: bool = (
			u.order == RTUnit.Order.IDLE
			or (u.order == RTUnit.Order.ATTACK and (u.attack_target == null
					or not u.attack_target.is_alive()))
		)
		if not needs_target:
			continue
		# Smarter target pick: mostly the nearest, but heavily favour wounded
		# regiments so the AI concentrates fire and secures kills instead of
		# spreading damage. A near-dead target is worth ~180px of extra reach.
		var best: RTUnit = null
		var best_score: float = INF
		for p: RTUnit in player_units:
			if not p.is_alive():
				continue
			var d: float = u.position.distance_to(p.position)
			var wounded: float = 1.0 - float(p.hp) / float(maxi(1, p.max_hp))
			var score: float = d - wounded * 180.0
			if score < best_score:
				best_score = score
				best = p
		if best != null:
			u.order_attack(best)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_active:
			_drag_current = event.position
			_update_drag_box_visual()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var in_field := FIELD_RECT.has_point(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not in_field:
					return
				_begin_left_press(event.position, event.shift_pressed)
			else:
				if not _drag_active:
					return
				_end_left_press(event.position, event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not in_field:
				return
			_handle_right_click(event.position)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _help_overlay != null:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_H, KEY_ESCAPE]:
			_toggle_help()
		return
	# Pause menu open: Esc closes it, swallow everything else.
	if _settings_overlay != null:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_toggle_settings_menu()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_set_paused(not _paused)
			KEY_R:
				if _ended:
					get_tree().reload_current_scene()
			KEY_H:
				_toggle_help()
			KEY_ESCAPE:
				_toggle_settings_menu()
		return

func _toggle_help() -> void:
	if _help_overlay != null:
		_help_overlay.queue_free()
		_help_overlay = null
		return
	_help_overlay = UITheme.help_overlay("2D Real-Time — Help", HELP_BODY, _toggle_help)
	add_child(_help_overlay)

# Left-click down: start a drag candidate. We don't know yet whether the
# player will band-box or simply click a unit, so we record the origin and
# wait for the mouse-up to commit.
func _begin_left_press(mouse: Vector2, shift: bool) -> void:
	if _ended:
		return
	_drag_active   = true
	_drag_origin   = mouse
	_drag_current  = mouse
	_drag_additive = shift
	_update_drag_box_visual()

func _end_left_press(mouse: Vector2, _shift: bool) -> void:
	if not _drag_active:
		return
	_drag_active = false
	_drag_box_rect.visible = false
	if _ended:
		return
	var drag_dist: float = mouse.distance_to(_drag_origin)
	if drag_dist >= DRAG_THRESHOLD:
		# Band-box select: pick up every friendly unit inside the rect.
		var rect := _drag_rect_normalized()
		var picked: Array = []
		for u: RTUnit in player_units:
			if u.is_alive() and rect.has_point(u.position):
				picked.append(u)
		_apply_selection(picked, _drag_additive)
	else:
		# Simple click — pick the unit under the cursor (if any).
		var picked: RTUnit = _pick_unit_at(mouse, player_units)
		if picked != null:
			_apply_selection([picked], _drag_additive)
		elif not _drag_additive:
			_apply_selection([], false)
	_refresh_ui()

func _apply_selection(units: Array, additive: bool) -> void:
	if not additive:
		for u: RTUnit in selected_units:
			if is_instance_valid(u):
				u.set_selected(false)
		selected_units.clear()
	for u: RTUnit in units:
		if not selected_units.has(u):
			selected_units.append(u)
			u.set_selected(true)

func _handle_right_click(mouse: Vector2) -> void:
	if _ended:
		return
	if selected_units.is_empty():
		if _command_label != null:
			_command_label.text = "Select one or more blue regiments before issuing an order."
			_command_label.modulate = Color(0.95, 0.65, 0.40)
		return
	# If we clicked an enemy, every selected unit attacks it. Otherwise,
	# spread the selection in a small clump around the target point so they
	# don't all try to converge on a single pixel and shove each other.
	var enemy: RTUnit = _pick_unit_at(mouse, enemy_units)
	if enemy != null:
		var ordered_count: int = 0
		for u: RTUnit in selected_units:
			if u.is_alive():
				u.order_attack(enemy)
				ordered_count += 1
		if ordered_count <= 0:
			return
		_mark_player_order_issued()
		_spawn_waypoint(enemy.position, Color(1.0, 0.40, 0.40), 0.6)
		if _command_label != null:
			_command_label.text = "Attack order: %d regiment%s focusing %s." % [
				ordered_count, "" if ordered_count == 1 else "s", enemy.unit_name
			]
		_refresh_ui()
		return
	var target := Vector2(
		clamp(mouse.x, FIELD_RECT.position.x + 10.0, FIELD_RECT.end.x - 10.0),
		clamp(mouse.y, FIELD_RECT.position.y + 10.0, FIELD_RECT.end.y - 10.0)
	)
	# Arrange selected units in a loose ring/line around the click point.
	var alive_sel: Array = []
	for u: RTUnit in selected_units:
		if u.is_alive():
			alive_sel.append(u)
	var n: int = alive_sel.size()
	if n <= 0:
		return
	for i in range(n):
		var u: RTUnit = alive_sel[i]
		var dest: Vector2 = target
		if n > 1:
			# Spread targets perpendicular to the unit's approach direction.
			var spread: float = u.radius * 1.6
			var to_t: Vector2 = (target - u.position).normalized()
			var perp: Vector2 = Vector2(-to_t.y, to_t.x)
			var offset_idx: float = float(i) - (float(n) - 1.0) * 0.5
			dest = target + perp * offset_idx * spread
			dest.x = clamp(dest.x, FIELD_RECT.position.x + 10.0, FIELD_RECT.end.x - 10.0)
			dest.y = clamp(dest.y, FIELD_RECT.position.y + 10.0, FIELD_RECT.end.y - 10.0)
		u.order_move(dest)
	_mark_player_order_issued()
	_spawn_waypoint(target, Color(0.55, 0.95, 0.55), 0.6)
	if _command_label != null:
		_command_label.text = "Move order: %d regiment%s to marked ground." % [
			n, "" if n == 1 else "s"
		]
	_refresh_ui()

func _pick_unit_at(p: Vector2, pool: Array) -> RTUnit:
	var best: RTUnit = null
	var best_d: float = INF
	for u: RTUnit in pool:
		if not u.is_alive():
			continue
		var d: float = u.position.distance_to(p)
		if d <= u.radius + PICK_RADIUS_PADDING and d < best_d:
			best   = u
			best_d = d
	return best

# Mouse-hover highlight on selectable units — gives a clear "this is
# interactable" affordance, particularly while paused.
func _update_hover() -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var under: RTUnit = _pick_unit_at(mouse, player_units)
	if under == null:
		under = _pick_unit_at(mouse, enemy_units)
	if under != _hovered_unit:
		if _hovered_unit != null and is_instance_valid(_hovered_unit):
			_hovered_unit.set_hovered(false)
		_hovered_unit = under
		if _hovered_unit != null:
			_hovered_unit.set_hovered(true)
	_update_info_panel(mouse)

func _update_info_panel(mouse: Vector2) -> void:
	if _info_panel == null:
		return
	if _hovered_unit == null or not is_instance_valid(_hovered_unit) or not _hovered_unit.is_alive():
		_info_panel.visible = false
		return
	_info_label.text = _hovered_unit.describe()
	_info_label.modulate = (Color(0.78, 0.86, 1.0) if _hovered_unit.team == 0 else Color(1.0, 0.78, 0.74))
	var vs := get_viewport().get_visible_rect().size
	var pos := mouse + Vector2(18.0, 18.0)
	pos.x = clamp(pos.x, 0.0, vs.x - _info_panel.size.x)
	pos.y = clamp(pos.y, 0.0, vs.y - _info_panel.size.y)
	_info_panel.position = pos
	_info_panel.visible = true

# ---------------------------------------------------------------------------
# Drag-box helpers
# ---------------------------------------------------------------------------
func _drag_rect_normalized() -> Rect2:
	var x0: float = min(_drag_origin.x, _drag_current.x)
	var y0: float = min(_drag_origin.y, _drag_current.y)
	var x1: float = max(_drag_origin.x, _drag_current.x)
	var y1: float = max(_drag_origin.y, _drag_current.y)
	return Rect2(x0, y0, x1 - x0, y1 - y0)

func _update_drag_box_visual() -> void:
	if not _drag_active or _drag_box_rect == null:
		return
	var drag_dist: float = _drag_origin.distance_to(_drag_current)
	if drag_dist < DRAG_THRESHOLD:
		_drag_box_rect.visible = false
		return
	var r := _drag_rect_normalized()
	_drag_box_rect.position = r.position
	_drag_box_rect.size     = r.size
	_drag_box_rect.visible  = true

# ---------------------------------------------------------------------------
# Waypoint feedback
# ---------------------------------------------------------------------------
func _spawn_waypoint(pos: Vector2, color: Color, lifetime: float) -> void:
	_waypoints.append({"pos": pos, "age": 0.0, "lifetime": lifetime, "color": color})

func _age_waypoints(delta: float) -> void:
	var still_alive: Array = []
	for wp: Dictionary in _waypoints:
		wp["age"] += delta
		if wp["age"] < wp["lifetime"]:
			still_alive.append(wp)
	_waypoints = still_alive

# ---------------------------------------------------------------------------
# UI state
# ---------------------------------------------------------------------------
func _set_paused(v: bool) -> void:
	if not v and not _battle_started:
		_battle_started = true
		if _player_has_issued_order:
			_opening_ai_timer = OPENING_AI_DELAY
		if _command_label != null:
			_command_label.text = "Orders are live. Select and right-click to redirect regiments mid-fight."
	_paused = v
	_refresh_ui()

func _mark_player_order_issued() -> void:
	if _player_has_issued_order:
		return
	_player_has_issued_order = true
	if _battle_started and not _paused:
		_opening_ai_timer = OPENING_AI_DELAY

func _refresh_ui() -> void:
	if _status_label != null:
		if _ended:
			_status_label.text = "Battle over"
			_status_label.modulate = Color(0.70, 0.70, 0.75)
		elif not _battle_started:
			_status_label.text = "PLANNING  (select units, right-click orders, SPACE to start)"
			_status_label.modulate = Color(1.0, 0.80, 0.35)
		elif _paused:
			_status_label.text = "❚❚ PAUSED  (SPACE to resume)"
			_status_label.modulate = Color(1.0, 0.80, 0.35)
		elif not _player_has_issued_order:
			_status_label.text = "▶ RUNNING  awaiting your first order"
			_status_label.modulate = Color(0.70, 0.90, 1.0)
		elif _opening_ai_timer > 0.0:
			_status_label.text = "▶ RUNNING  enemy advance in %.1fs" % _opening_ai_timer
			_status_label.modulate = Color(0.70, 0.90, 1.0)
		else:
			_status_label.text = "▶ RUNNING  (SPACE to pause)"
			_status_label.modulate = Color(0.55, 0.95, 0.55)

	if _selection_label != null:
		var alive_sel: Array = []
		for u: RTUnit in selected_units:
			if is_instance_valid(u) and u.is_alive():
				alive_sel.append(u)
		# Drop dead entries from the selection list so it doesn't grow stale
		if alive_sel.size() != selected_units.size():
			selected_units = alive_sel
		if alive_sel.is_empty():
			_selection_label.text = "No regiment selected — left-click or drag-box blue regiments, then right-click ground or enemies to queue orders."
			if _command_label != null and not _ended:
				_command_label.modulate = Color(0.64, 0.68, 0.74)
		elif alive_sel.size() == 1:
			var u: RTUnit = alive_sel[0]
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
			if _command_label != null:
				_command_label.modulate = Color(0.80, 0.86, 0.92)
		else:
			var total_hp: int = 0
			var total_max: int = 0
			for u: RTUnit in alive_sel:
				total_hp  += u.hp
				total_max += u.max_hp
			_selection_label.text = (
				"%d regiments selected  ·  %d / %d HP combined  ·  right-click to queue group order"
				% [alive_sel.size(), total_hp, total_max]
			)
			if _command_label != null:
				_command_label.modulate = Color(0.80, 0.86, 0.92)

func _on_unit_died(u: RTUnit) -> void:
	if selected_units.has(u):
		selected_units.erase(u)
	if _hovered_unit == u:
		_hovered_unit = null
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
	var won: bool = p_alive and not e_alive
	if _campaign:
		_conclude_campaign(won)
		_show_campaign_result(won)
		_refresh_ui()
		return
	if _result_label != null:
		if won:
			_result_label.text = "VICTORY"
			_result_label.modulate = Color(0.55, 0.95, 0.55)
		elif e_alive and not p_alive:
			_result_label.text = "DEFEAT"
			_result_label.modulate = Color(0.95, 0.45, 0.45)
		else:
			_result_label.text = "DRAW"
			_result_label.modulate = Color(0.85, 0.85, 0.55)
		_result_label.visible = true
	if _restart_hint_label != null:
		_restart_hint_label.visible = true
	_refresh_ui()

func _conclude_campaign(win: bool) -> void:
	var tier: int = GameManager.pending_battle_tier
	var elite: bool = GameManager.pending_battle_elite
	_campaign_lost = not win
	if win:
		var survivors: Array[Dictionary] = []
		for u: RTUnit in player_units:
			if is_instance_valid(u) and u.is_alive() and u.has_meta("roster_entry"):
				survivors.append(u.get_meta("roster_entry"))
		if survivors.is_empty() and not GameManager.player_roster.is_empty():
			survivors.append(GameManager.player_roster[0])
		GameManager.set_roster(survivors)
		_campaign_reward_gold = GameManager.battle_gold_reward(tier, elite)
		GameManager.add_gold(_campaign_reward_gold)
		GameManager.register_battle_won(elite)
		GameManager.pending_upgrade_reward = true
		if elite:
			_campaign_relic = GameManager.grant_random_relic()
		GameManager.save_run()
	else:
		GameManager.clear_run()

func _show_campaign_result(win: bool) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 80
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	UITheme.panel(root, Vector2(480.0, 244.0), Vector2(320.0, 220.0))
	root.add_child(UITheme.label("VICTORY" if win else "DEFEAT", 40,
		UITheme.GOLD if win else UITheme.RED, Vector2(556.0, 266.0)))
	var sub: String = ("+%d gold%s" % [_campaign_reward_gold,
		"   ·   Relic: %s" % String(GameManager.RELICS[_campaign_relic]["name"]) if _campaign_relic != "" else ""]) if win \
		else "Your army was wiped out — the run ends here."
	root.add_child(UITheme.label(sub, 15, UITheme.TEXT_MUTED, Vector2(500.0, 322.0), Vector2(280.0, 40.0)))
	if win:
		root.add_child(UITheme.button("Continue", Vector2(512.0, 372.0), Vector2(256.0, 46.0),
			UITheme.GREEN, func() -> void: get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")))
	else:
		root.add_child(UITheme.button("To Title", Vector2(512.0, 372.0), Vector2(256.0, 46.0),
			Color(0.45, 0.30, 0.34), func() -> void: get_tree().change_scene_to_file("res://src/title/title.tscn")))
	add_child(root)
