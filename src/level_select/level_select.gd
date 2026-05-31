extends Node2D

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const NODE_X: Array[float] = [320.0, 640.0, 960.0]
const TIER_Y: Array[float] = [630.0, 510.0, 390.0, 270.0, 150.0]
const NODE_R: float = 34.0

const TYPE_COLORS: Dictionary = {
	"battle":       Color(0.80, 0.28, 0.28),
	"elite_battle": Color(0.55, 0.10, 0.65),
	"gain_unit":    Color(0.25, 0.55, 0.95),
	"heal":         Color(0.20, 0.72, 0.35)
}
const TYPE_LABELS: Dictionary = {
	"battle":       "Battle",
	"elite_battle": "Elite!",
	"gain_unit":    "+Unit",
	"heal":         "Heal"
}
const TYPE_DESC: Dictionary = {
	"battle":       "Standard battle",
	"elite_battle": "Harder battle, tougher enemies",
	"gain_unit":    "Choose a new unit",
	"heal":         "Gain a free Scout"
}

# ---------------------------------------------------------------------------
var _node_buttons: Array = []
var _roster_label: Label
var _depth_label: Label
var _popup: Control = null

# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_node_buttons()
	_build_hud()
	_refresh()

func _draw() -> void:
	# Background
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.06, 0.07, 0.10))
	# HUD bar
	draw_rect(Rect2(0.0, 670.0, 1280.0, 50.0), Color(0.08, 0.08, 0.14))
	# Connection lines between tiers
	for tier in range(GameManager.MAP_TIERS - 1):
		for i in range(GameManager.NODES_PER_TIER):
			var from := Vector2(NODE_X[i], TIER_Y[tier])
			var targets: Array = [i]
			if i > 0:
				targets.append(i - 1)
			if i < GameManager.NODES_PER_TIER - 1:
				targets.append(i + 1)
			for j in targets:
				var to := Vector2(NODE_X[j], TIER_Y[tier + 1])
				draw_line(from, to, Color(0.35, 0.35, 0.48, 0.65), 2.0)

# ---------------------------------------------------------------------------
# Build UI
# ---------------------------------------------------------------------------
func _build_node_buttons() -> void:
	# Title
	var title := Label.new()
	title.text = "Choose Your Path"
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(0.95, 0.90, 0.65)
	title.position = Vector2(460.0, 22.0)
	add_child(title)

	# Legend
	var legend_x := 20.0
	for type_key: String in TYPE_COLORS.keys():
		var dot := ColorRect.new()
		dot.color = TYPE_COLORS[type_key]
		dot.size = Vector2(14.0, 14.0)
		dot.position = Vector2(legend_x, 698.0)
		add_child(dot)
		var lbl := Label.new()
		lbl.text = TYPE_LABELS[type_key] + ": " + TYPE_DESC[type_key]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.modulate = Color(0.75, 0.75, 0.75)
		lbl.position = Vector2(legend_x + 18.0, 696.0)
		add_child(lbl)
		legend_x += 260.0

	# Node buttons
	for tier in range(GameManager.MAP_TIERS):
		for i in range(GameManager.NODES_PER_TIER):
			_add_node_button(tier, i)

func _add_node_button(tier: int, index: int) -> void:
	var node_data: Dictionary = GameManager.map_data[tier][index]
	var base_color: Color = TYPE_COLORS.get(node_data["type"], Color.GRAY)
	var pos := Vector2(NODE_X[index], TIER_Y[tier])

	var btn := Button.new()
	btn.size = Vector2(NODE_R * 2.0, NODE_R * 2.0)
	btn.position = pos - Vector2(NODE_R, NODE_R)
	btn.text = TYPE_LABELS.get(node_data["type"], "?")
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_stylebox_override("normal",   _circle_style(base_color, NODE_R))
	btn.add_theme_stylebox_override("hover",    _circle_style(base_color.lightened(0.25), NODE_R))
	btn.add_theme_stylebox_override("pressed",  _circle_style(base_color.darkened(0.25), NODE_R))
	btn.add_theme_stylebox_override("disabled", _circle_style(Color(0.28, 0.28, 0.32), NODE_R))
	btn.pressed.connect(_on_node_pressed.bind(tier, index))
	add_child(btn)
	_node_buttons.append({"button": btn, "tier": tier, "index": index})

func _circle_style(color: Color, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	var r := int(radius)
	s.corner_radius_top_left    = r
	s.corner_radius_top_right   = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	return s

func _build_hud() -> void:
	_roster_label = Label.new()
	_roster_label.add_theme_font_size_override("font_size", 15)
	_roster_label.modulate = Color(0.90, 0.85, 0.70)
	_roster_label.position = Vector2(12.0, 678.0)
	add_child(_roster_label)

	_depth_label = Label.new()
	_depth_label.add_theme_font_size_override("font_size", 15)
	_depth_label.modulate = Color(0.70, 0.70, 0.70)
	_depth_label.position = Vector2(1100.0, 678.0)
	add_child(_depth_label)

# ---------------------------------------------------------------------------
# Refresh state
# ---------------------------------------------------------------------------
func _refresh() -> void:
	var reachable := GameManager.get_reachable_indices()
	var cur_tier := GameManager.current_tier

	for btn_data: Dictionary in _node_buttons:
		var tier: int = btn_data["tier"]
		var index: int = btn_data["index"]
		var btn: Button = btn_data["button"]
		var node_data: Dictionary = GameManager.map_data[tier][index]

		var is_reachable := tier == cur_tier and index in reachable
		var is_visited := node_data["visited"]
		btn.disabled = not is_reachable

		var base_color: Color = TYPE_COLORS.get(node_data["type"], Color.GRAY)
		var display_color: Color
		if is_visited:
			display_color = base_color.darkened(0.6)
		elif not is_reachable:
			display_color = base_color.darkened(0.38)
		else:
			display_color = base_color

		var style := _circle_style(display_color, NODE_R)
		if is_reachable:
			style.border_width_left   = 3
			style.border_width_right  = 3
			style.border_width_top    = 3
			style.border_width_bottom = 3
			style.border_color = Color(1.0, 1.0, 1.0, 0.9)
		btn.add_theme_stylebox_override("normal",   style)
		btn.add_theme_stylebox_override("disabled", style)

	_roster_label.text = "Roster: " + _roster_text()
	_depth_label.text  = "Tier %d / %d" % [cur_tier, GameManager.MAP_TIERS]

	if cur_tier >= GameManager.MAP_TIERS:
		_show_victory()

	queue_redraw()

func _roster_text() -> String:
	var counts: Dictionary = {}
	for u: String in GameManager.player_roster:
		counts[u] = counts.get(u, 0) + 1
	var parts: Array[String] = []
	for type_key: String in counts:
		parts.append("%d× %s" % [counts[type_key], GameManager.UNIT_TYPES[type_key]["name"]])
	return "  ".join(parts)

# ---------------------------------------------------------------------------
# Node interaction
# ---------------------------------------------------------------------------
func _on_node_pressed(tier: int, index: int) -> void:
	if _popup:
		return
	var node_data: Dictionary = GameManager.map_data[tier][index]
	GameManager.visit_node(tier, index)

	match node_data["type"]:
		"battle", "elite_battle":
			GameManager.pending_battle_tier  = tier
			GameManager.pending_battle_elite = node_data["type"] == "elite_battle"
			get_tree().change_scene_to_file("res://src/battle/battle.tscn")
		"gain_unit":
			_show_unit_select_popup()
		"heal":
			GameManager.add_unit("scout")
			_show_toast("Gained a free Scout!", Color(0.20, 0.72, 0.35))
		_:
			_refresh()

# ---------------------------------------------------------------------------
# Unit selection popup
# ---------------------------------------------------------------------------
func _show_unit_select_popup() -> void:
	_popup = Panel.new()
	_popup.position = Vector2(190.0, 180.0)
	_popup.size = Vector2(900.0, 360.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.16, 0.97)
	for side in ["left", "right", "top", "bottom"]:
		style.set("border_width_" + side, 2)
	style.border_color = Color(0.50, 0.50, 0.75)
	for corner in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(corner, 8)
	_popup.add_theme_stylebox_override("panel", style)
	add_child(_popup)

	var title := Label.new()
	title.text = "Choose a Unit to Add to Your Roster"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(0.95, 0.90, 1.0)
	title.position = Vector2(220.0, 18.0)
	_popup.add_child(title)

	var keys := GameManager.UNIT_TYPES.keys()
	for i in range(keys.size()):
		var utype: String = keys[i]
		var udata: Dictionary = GameManager.UNIT_TYPES[utype]
		var btn := Button.new()
		btn.position = Vector2(30.0 + i * 285.0, 65.0)
		btn.size = Vector2(260.0, 240.0)
		btn.text = "%s\n\nHP:     %d\nMove:  %d tiles\nRange: %d tile%s\nDmg:   %d" % [
			udata["name"], udata["max_hp"], udata["move_range"],
			udata["attack_range"], ("s" if udata["attack_range"] > 1 else ""),
			udata["damage"]
		]
		btn.add_theme_font_size_override("font_size", 16)
		var bs := _circle_style(udata["color"].darkened(0.15), 8)
		btn.add_theme_stylebox_override("normal",  bs)
		btn.add_theme_stylebox_override("hover",   _circle_style(udata["color"].lightened(0.15), 8))
		btn.add_theme_stylebox_override("pressed", _circle_style(udata["color"].darkened(0.30), 8))
		btn.pressed.connect(_on_unit_chosen.bind(utype))
		_popup.add_child(btn)

func _on_unit_chosen(unit_type: String) -> void:
	GameManager.add_unit(unit_type)
	_popup.queue_free()
	_popup = null
	var name_str: String = GameManager.UNIT_TYPES[unit_type]["name"]
	var color: Color = GameManager.UNIT_TYPES[unit_type]["color"]
	_show_toast("Added %s to your roster!" % name_str, color)

# ---------------------------------------------------------------------------
# Toast / Victory
# ---------------------------------------------------------------------------
func _show_toast(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.modulate = color
	lbl.position = Vector2(400.0, 330.0)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(lbl.queue_free)
	tw.tween_callback(_refresh)

func _show_victory() -> void:
	var panel := Panel.new()
	panel.position = Vector2(290.0, 200.0)
	panel.size = Vector2(700.0, 320.0)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	for side in ["left", "right", "top", "bottom"]:
		s.set("border_width_" + side, 3)
	s.border_color = Color(0.9, 0.8, 0.2)
	panel.add_theme_stylebox_override("panel", s)
	add_child(panel)

	var title := Label.new()
	title.text = "You conquered the map!"
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = Color(0.95, 0.85, 0.25)
	title.position = Vector2(100.0, 60.0)
	panel.add_child(title)

	var btn := Button.new()
	btn.text = "Play Again"
	btn.position = Vector2(260.0, 200.0)
	btn.size = Vector2(180.0, 60.0)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func() -> void:
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	)
	panel.add_child(btn)
