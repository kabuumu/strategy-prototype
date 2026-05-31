extends Node2D

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const TIER_Y: Array[float] = [630.0, 510.0, 390.0, 270.0, 150.0]
const NODE_R: float = 34.0

const TYPE_COLORS: Dictionary = {
	"battle":       Color(0.80, 0.28, 0.28),
	"elite_battle": Color(0.55, 0.10, 0.65),
	"gain_unit":    Color(0.25, 0.55, 0.95),
	"shop":         Color(0.85, 0.70, 0.20),
	"heal":         Color(0.20, 0.72, 0.35)
}
const TYPE_LABELS: Dictionary = {
	"battle":       "Battle",
	"elite_battle": "Elite!",
	"gain_unit":    "+Unit",
	"shop":         "Shop",
	"heal":         "Heal"
}
const TYPE_DESC: Dictionary = {
	"battle":       "Standard battle",
	"elite_battle": "Harder battle, tougher enemies",
	"gain_unit":    "Choose a new unit",
	"shop":         "Spend gold on heals and units",
	"heal":         "Heal all units to full"
}

# ---------------------------------------------------------------------------
var _node_buttons: Array = []
var _roster_label: Label
var _gold_label: Label
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
	# Connection lines — drawn from stored connections so locked-out paths aren't shown
	for tier in range(GameManager.MAP_TIERS - 1):
		var from_count: int = GameManager.map_data[tier].size()
		var to_count:   int = GameManager.map_data[tier + 1].size()
		for i in range(from_count):
			var from := Vector2(_node_x(i, from_count), TIER_Y[tier])
			for j in GameManager.map_data[tier][i]["connections"]:
				var to := Vector2(_node_x(j, to_count), TIER_Y[tier + 1])
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
		for i in range(GameManager.map_data[tier].size()):
			_add_node_button(tier, i)

func _node_x(index: int, count: int) -> float:
	if count == 1:
		return 640.0
	var margin := 120.0
	return margin + float(index) * (1280.0 - margin * 2.0) / float(count - 1)

func _add_node_button(tier: int, index: int) -> void:
	var node_data: Dictionary = GameManager.map_data[tier][index]
	var base_color: Color = TYPE_COLORS.get(node_data["type"], Color.GRAY)
	var count: int = GameManager.map_data[tier].size()
	var pos := Vector2(_node_x(index, count), TIER_Y[tier])

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

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.modulate = Color(0.95, 0.82, 0.25)
	_gold_label.position = Vector2(12.0, 654.0)
	add_child(_gold_label)

	_depth_label = Label.new()
	_depth_label.add_theme_font_size_override("font_size", 15)
	_depth_label.modulate = Color(0.70, 0.70, 0.70)
	_depth_label.position = Vector2(900.0, 678.0)
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
		var is_visited: bool = node_data["visited"]
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
	_gold_label.text   = "Gold: %d" % GameManager.gold
	_depth_label.text  = "Tier %d / %d   ·   Wins: %d   ·   Best: %d" % [
		cur_tier, GameManager.MAP_TIERS,
		GameManager.battles_won, GameManager.best_streak_ever
	]

	if cur_tier >= GameManager.MAP_TIERS:
		_show_victory()

	queue_redraw()

func _roster_text() -> String:
	if GameManager.player_roster.is_empty():
		return "(none)"
	var parts: Array[String] = []
	for entry: Dictionary in GameManager.player_roster:
		var udata: Dictionary = GameManager.UNIT_TYPES[entry["type"]]
		var hp: int = int(entry["hp"])
		var max_hp: int = int(udata["max_hp"])
		# Flag wounded units so heal nodes read as worthwhile
		var hp_str: String = "%d/%d" % [hp, max_hp]
		if hp < max_hp:
			hp_str += "⚠"
		parts.append("%s %s" % [udata["name"], hp_str])
	return "   ".join(parts)

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
		"shop":
			_show_shop_popup()
		"heal":
			GameManager.heal_roster()
			_refresh()
			_show_toast("Party fully healed!", Color(0.20, 0.72, 0.35))
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
# Shop popup — spend gold; stays open for multiple purchases until "Leave"
# ---------------------------------------------------------------------------
func _show_shop_popup() -> void:
	_popup = Panel.new()
	_popup.position = Vector2(190.0, 150.0)
	_popup.size = Vector2(900.0, 420.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.05, 0.97)
	for side in ["left", "right", "top", "bottom"]:
		style.set("border_width_" + side, 2)
	style.border_color = Color(0.85, 0.70, 0.20)
	for corner in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(corner, 8)
	_popup.add_theme_stylebox_override("panel", style)
	add_child(_popup)
	_populate_shop()

func _populate_shop() -> void:
	for child in _popup.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1.0, 0.88, 0.35)
	title.position = Vector2(30.0, 16.0)
	_popup.add_child(title)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: %d" % GameManager.gold
	gold_lbl.add_theme_font_size_override("font_size", 18)
	gold_lbl.modulate = Color(0.95, 0.82, 0.25)
	gold_lbl.position = Vector2(740.0, 20.0)
	_popup.add_child(gold_lbl)

	# Heal party
	var heal_btn := _make_shop_button(
		"Heal Party to Full\n\n%d gold" % GameManager.SHOP_HEAL_COST,
		Vector2(30.0, 70.0), Vector2(260.0, 150.0),
		Color(0.20, 0.55, 0.30), GameManager.gold >= GameManager.SHOP_HEAL_COST)
	heal_btn.pressed.connect(_on_shop_heal)
	_popup.add_child(heal_btn)

	# Buy a unit (one button per class)
	var keys := GameManager.UNIT_TYPES.keys()
	for i in range(keys.size()):
		var utype: String = keys[i]
		var udata: Dictionary = GameManager.UNIT_TYPES[utype]
		var can_afford := GameManager.gold >= GameManager.SHOP_UNIT_COST
		var btn := _make_shop_button(
			"Buy %s\n\nHP:%d Mv:%d Rng:%d Dmg:%d\n\n%d gold" % [
				udata["name"], udata["max_hp"], udata["move_range"],
				udata["attack_range"], udata["damage"], GameManager.SHOP_UNIT_COST],
			Vector2(310.0 + i * 195.0, 70.0), Vector2(180.0, 230.0),
			udata["color"].darkened(0.1), can_afford)
		btn.pressed.connect(_on_shop_buy_unit.bind(utype))
		_popup.add_child(btn)

	var leave := Button.new()
	leave.text = "Leave"
	leave.position = Vector2(30.0, 340.0)
	leave.size = Vector2(260.0, 50.0)
	leave.add_theme_font_size_override("font_size", 18)
	leave.pressed.connect(func() -> void:
		_popup.queue_free()
		_popup = null
		_refresh())
	_popup.add_child(leave)

func _make_shop_button(txt: String, pos: Vector2, sz: Vector2, color: Color, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = sz
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_stylebox_override("normal",   _circle_style(color, 8))
	btn.add_theme_stylebox_override("hover",    _circle_style(color.lightened(0.15), 8))
	btn.add_theme_stylebox_override("pressed",  _circle_style(color.darkened(0.25), 8))
	btn.add_theme_stylebox_override("disabled", _circle_style(color.darkened(0.55), 8))
	return btn

func _on_shop_heal() -> void:
	if GameManager.spend_gold(GameManager.SHOP_HEAL_COST):
		GameManager.heal_roster()
		_show_toast("Party healed!", Color(0.30, 0.85, 0.45))
		_populate_shop()

func _on_shop_buy_unit(unit_type: String) -> void:
	if GameManager.spend_gold(GameManager.SHOP_UNIT_COST):
		GameManager.add_unit(unit_type)
		var name_str: String = GameManager.UNIT_TYPES[unit_type]["name"]
		_show_toast("Bought %s!" % name_str, GameManager.UNIT_TYPES[unit_type]["color"])
		_populate_shop()

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
