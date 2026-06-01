extends Node2D

const UITheme := preload("res://src/ui/ui_theme.gd")

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const TIER_Y: Array[float] = [630.0, 510.0, 390.0, 270.0, 150.0]
const NODE_R: float = 32.0
const MAP_LEFT: float = 72.0
const MAP_RIGHT: float = 820.0
const SIDE_X: float = 880.0

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
var _relics_label: Label
var _depth_label: Label
var _node_detail_label: Label
var _popup: Control = null
var _settings_overlay: Control = null
var _shop_relic_offer: String = ""

# Hover preview — built once, shown when the cursor enters a battle node so
# the player can see what they're walking into before committing.
var _preview_panel: Panel = null
var _preview_label: Label = null

# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_node_buttons()
	_build_hud()
	# Checkpoint the run between battles so it can be resumed. Once the run is
	# over (boss cleared), drop the save instead.
	if GameManager.current_tier < GameManager.MAP_TIERS:
		GameManager.save_run()
	else:
		GameManager.clear_run()
	# Small hint that Esc opens the menu
	add_child(UITheme.label("Esc — Menu", 13, UITheme.TEXT_MUTED, Vector2(1150.0, 26.0), Vector2(110.0, 20.0)))
	_refresh()

func _on_exit_to_menu() -> void:
	if GameManager.current_tier < GameManager.MAP_TIERS:
		GameManager.save_run()   # keep the run resumable
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# Esc closes a shop/unit popup if open; otherwise toggles the settings menu
		if _popup != null:
			return
		_toggle_settings_menu()

# Pause/settings overlay opened with Esc.
func _toggle_settings_menu() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 200
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks to the map
	root.add_child(dim)
	UITheme.panel(root, Vector2(490.0, 230.0), Vector2(300.0, 260.0))
	root.add_child(UITheme.label("Menu", 26, UITheme.GOLD, Vector2(610.0, 250.0)))
	root.add_child(UITheme.button("Resume", Vector2(520.0, 300.0), Vector2(240.0, 50.0),
		Color(0.20, 0.45, 0.30), _toggle_settings_menu))
	root.add_child(UITheme.button("Exit to Main Menu", Vector2(520.0, 360.0), Vector2(240.0, 50.0),
		Color(0.45, 0.30, 0.34), _on_exit_to_menu))
	root.add_child(UITheme.label("Your run is saved — Continue resumes it.", 12,
		UITheme.TEXT_MUTED, Vector2(516.0, 428.0), Vector2(250.0, 36.0)))
	add_child(root)
	_settings_overlay = root

func _draw() -> void:
	# Background
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), UITheme.BG)
	draw_rect(Rect2(SIDE_X - 22.0, 0.0, 422.0, 720.0), Color(0.035, 0.040, 0.060, 0.74))
	draw_line(Vector2(SIDE_X - 22.0, 0.0), Vector2(SIDE_X - 22.0, 720.0), Color(0.25, 0.27, 0.35, 0.85), 1.0)
	# Connection lines — drawn from stored connections so locked-out paths aren't shown
	for tier in range(GameManager.MAP_TIERS - 1):
		var from_count: int = GameManager.map_data[tier].size()
		var to_count:   int = GameManager.map_data[tier + 1].size()
		for i in range(from_count):
			var from := Vector2(_node_x(i, from_count), TIER_Y[tier])
			for j in GameManager.map_data[tier][i]["connections"]:
				var to := Vector2(_node_x(j, to_count), TIER_Y[tier + 1])
				draw_line(from, to, Color(0.36, 0.37, 0.50, 0.62), 2.0)

# ---------------------------------------------------------------------------
# Build UI
# ---------------------------------------------------------------------------
func _build_node_buttons() -> void:
	add_child(UITheme.label("Choose Your Path", 38, Color(0.95, 0.90, 0.65), Vector2(72.0, 24.0)))
	add_child(UITheme.label("Only highlighted nodes are reachable. Hover a node to preview the commitment.", 14, UITheme.TEXT_MUTED, Vector2(76.0, 70.0), Vector2(720.0, 28.0)))

	# Node buttons
	for tier in range(GameManager.MAP_TIERS):
		for i in range(GameManager.map_data[tier].size()):
			_add_node_button(tier, i)

func _node_x(index: int, count: int) -> float:
	if count == 1:
		return (MAP_LEFT + MAP_RIGHT) * 0.5
	return MAP_LEFT + float(index) * (MAP_RIGHT - MAP_LEFT) / float(count - 1)

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
	btn.mouse_entered.connect(_show_node_detail.bind(tier, index))
	add_child(btn)
	_node_buttons.append({"button": btn, "tier": tier, "index": index})

# ---------------------------------------------------------------------------
# Battle preview tooltip
# ---------------------------------------------------------------------------
func _ensure_preview_panel() -> void:
	if _preview_panel != null:
		return
	_preview_panel = Panel.new()
	_preview_panel.z_index = 100
	_preview_panel.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color        = Color(0.08, 0.08, 0.12, 0.96)
	s.border_color    = Color(0.85, 0.30, 0.25, 0.95)
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2;  s.border_width_bottom = 2
	s.corner_radius_top_left = 4; s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top  = 8;  s.content_margin_bottom = 8
	_preview_panel.add_theme_stylebox_override("panel", s)
	add_child(_preview_panel)
	_preview_label = Label.new()
	_preview_label.add_theme_font_size_override("font_size", 12)
	_preview_label.modulate = Color(0.95, 0.92, 0.85)
	_preview_panel.add_child(_preview_label)

func _on_battle_node_hover(tier: int, _index: int, node_pos: Vector2) -> void:
	_ensure_preview_panel()
	var nd: Dictionary = GameManager.map_data[tier][_index]
	var elite: bool = nd["type"] == "elite_battle"
	var roster: Array[String] = GameManager.get_battle_enemy_roster(tier, elite)
	# Count occurrences per unit type
	var counts: Dictionary = {}
	for k in roster:
		counts[k] = counts.get(k, 0) + 1
	var lines: Array[String] = []
	if GameManager.is_final_battle(tier, elite):
		lines.append("⚔  FINAL BATTLE  ⚔")
	else:
		lines.append("Enemy forces" + ("  (ELITE)" if elite else ""))
	for k: String in counts.keys():
		var udata: Dictionary = GameManager.UNIT_TYPES[k]
		var line := "  %d× %s  (%dHP · %ddmg · rng %d)" % [
			counts[k], udata["name"], udata["max_hp"], udata["damage"], udata["attack_range"]
		]
		lines.append(line)
	var hp_mult: float = GameManager.get_hp_multiplier(tier, elite)
	if hp_mult > 1.001:
		lines.append("  HP ×%.2f scaling" % hp_mult)
	_preview_label.text = "\n".join(lines)
	_preview_label.position = Vector2.ZERO
	# Force a layout pass so size reflects the text, then place it
	_preview_label.reset_size()
	var ts := _preview_label.size + Vector2(20.0, 16.0)
	_preview_panel.size = ts
	# Place to the right of the node (or left if there's no room)
	var px: float = node_pos.x + NODE_R + 14.0
	if px + ts.x > 1280.0 - 8.0:
		px = node_pos.x - NODE_R - 14.0 - ts.x
	var py: float = node_pos.y - ts.y * 0.5
	py = clampf(py, 8.0, 660.0 - ts.y)
	_preview_panel.position = Vector2(px, py)
	_preview_panel.visible = true

func _hide_battle_preview() -> void:
	if _preview_panel:
		_preview_panel.visible = false

func _show_node_detail(tier: int, index: int) -> void:
	if _node_detail_label == null:
		return
	_node_detail_label.text = _node_detail_text(tier, index)

func _node_detail_text(tier: int, index: int) -> String:
	var nd: Dictionary = GameManager.map_data[tier][index]
	var type_key: String = String(nd["type"])
	var title: String = TYPE_LABELS.get(type_key, "Node")
	var lines: Array[String] = [title, TYPE_DESC.get(type_key, "")]
	if type_key in ["battle", "elite_battle"]:
		var elite := type_key == "elite_battle"
		var roster: Array[String] = GameManager.get_battle_enemy_roster(tier, elite)
		var counts: Dictionary = {}
		for k: String in roster:
			counts[k] = int(counts.get(k, 0)) + 1
		lines.append("")
		lines.append("Enemy preview:")
		for k: String in counts.keys():
			var udata: Dictionary = GameManager.UNIT_TYPES[k]
			lines.append("%dx %s" % [counts[k], udata["name"]])
		var hp_mult: float = GameManager.get_hp_multiplier(tier, elite)
		if hp_mult > 1.001:
			lines.append("HP scaling x%.2f" % hp_mult)
	elif type_key == "gain_unit":
		lines.append("")
		lines.append("Adds one recruit of your choice.")
	elif type_key == "shop":
		lines.append("")
		lines.append("Spend gold on healing, units, or a relic offer.")
	elif type_key == "heal":
		lines.append("")
		lines.append("Restores every surviving unit to full HP.")
	return "\n".join(lines)

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
	var side := UITheme.panel(self, Vector2(SIDE_X, 24.0), Vector2(328.0, 652.0), UITheme.PANEL, Color(0.34, 0.36, 0.46))
	side.add_child(UITheme.label("Run", 24, UITheme.GOLD, Vector2(18.0, 14.0)))

	_depth_label = UITheme.label("", 14, UITheme.TEXT_MUTED, Vector2(18.0, 48.0), Vector2(286.0, 22.0))
	side.add_child(_depth_label)
	_gold_label = UITheme.label("", 18, UITheme.GOLD, Vector2(18.0, 82.0), Vector2(286.0, 24.0))
	side.add_child(_gold_label)

	side.add_child(UITheme.label("Roster", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 124.0)))
	_roster_label = UITheme.label("", 13, Color(0.90, 0.85, 0.70), Vector2(18.0, 144.0), Vector2(292.0, 112.0))
	side.add_child(_roster_label)

	side.add_child(UITheme.label("Relics", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 272.0)))
	_relics_label = UITheme.label("", 12, Color(0.75, 0.85, 0.95), Vector2(18.0, 292.0), Vector2(292.0, 82.0))
	side.add_child(_relics_label)

	side.add_child(UITheme.label("Node", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 396.0)))
	_node_detail_label = UITheme.label("", 13, UITheme.TEXT, Vector2(18.0, 418.0), Vector2(292.0, 132.0))
	side.add_child(_node_detail_label)

	side.add_child(UITheme.label("Legend", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 570.0)))
	var lx := 18.0
	var ly := 594.0
	for type_key: String in TYPE_COLORS.keys():
		UITheme.chip(side, TYPE_LABELS[type_key], Vector2(lx, ly), TYPE_COLORS[type_key], 92.0)
		lx += 100.0
		if lx > 220.0:
			lx = 18.0
			ly += 30.0

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

	_roster_label.text = _roster_text()
	_gold_label.text   = "Gold: %d" % GameManager.gold
	_relics_label.text = _relics_text()
	_depth_label.text  = "Tier %d / %d   ·   Wins: %d   ·   Best: %d" % [
		cur_tier, GameManager.MAP_TIERS,
		GameManager.battles_won, GameManager.best_streak_ever
	]
	if _node_detail_label != null and _node_detail_label.text == "":
		var reach: Array = GameManager.get_reachable_indices()
		if not reach.is_empty() and cur_tier < GameManager.MAP_TIERS:
			_show_node_detail(cur_tier, int(reach[0]))

	if cur_tier >= GameManager.MAP_TIERS:
		_show_victory()

	queue_redraw()

func _relics_text() -> String:
	if GameManager.relics.is_empty():
		return "(none)"
	var names: Array[String] = []
	for id: String in GameManager.relics:
		names.append(GameManager.RELICS[id]["name"])
	return "  ·  ".join(names)

func _roster_text() -> String:
	if GameManager.player_roster.is_empty():
		return "(none)"
	var parts: Array[String] = []
	for entry: Dictionary in GameManager.player_roster:
		var udata: Dictionary = GameManager.UNIT_TYPES[entry["type"]]
		var hp: int = int(entry["hp"])
		var max_hp: int = GameManager.unit_effective_max_hp(entry)
		# Flag wounded units so heal nodes read as worthwhile
		var hp_str: String = "%d/%d" % [hp, max_hp]
		if hp < max_hp:
			hp_str += "⚠"
		var ups: Array = entry.get("upgrades", [])
		var up_str: String = (" ✦%d" % ups.size()) if ups.size() > 0 else ""
		parts.append("%s %s%s" % [udata["name"], hp_str, up_str])
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
			# Route to the run's chosen battle style.
			match GameManager.battle_mode:
				"3d":
					GameManager.pending_skirmish = true
					get_tree().change_scene_to_file("res://src/skirmish3d/skirmish3d.tscn")
				"auto":
					GameManager.pending_autobattle = true
					get_tree().change_scene_to_file("res://src/autobattler/autobattler.tscn")
				_:
					get_tree().change_scene_to_file("res://src/battle/battle.tscn")
		"gain_unit":
			_show_unit_select_popup()
		"shop":
			_show_shop_popup()
		"heal":
			GameManager.heal_roster()
			Sfx.play("heal")
			_refresh()
			_show_toast("Party fully healed!", Color(0.20, 0.72, 0.35))
		_:
			_refresh()

# ---------------------------------------------------------------------------
# Unit selection popup
# ---------------------------------------------------------------------------
func _show_unit_select_popup() -> void:
	_popup = Panel.new()
	_popup.position = Vector2(130.0, 180.0)
	_popup.size = Vector2(1020.0, 360.0)

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
	title.position = Vector2(330.0, 16.0)
	_popup.add_child(title)

	# 4-column grid so the roster of recruitable types wraps cleanly.
	var keys := GameManager.recruitable_types()
	var cols := 4
	for i in range(keys.size()):
		var utype: String = keys[i]
		var udata: Dictionary = GameManager.UNIT_TYPES[utype]
		var col := i % cols
		var row := i / cols
		var btn := Button.new()
		btn.position = Vector2(20.0 + col * 248.0, 60.0 + row * 145.0)
		btn.size = Vector2(235.0, 132.0)
		btn.text = "%s\nHP %d   Mv %d\nRng %d   Dmg %d\n%s" % [
			udata["name"], udata["max_hp"], udata["move_range"],
			udata["attack_range"], udata["damage"], udata["ability"]["name"]
		]
		btn.add_theme_font_size_override("font_size", 14)
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
	# Pick one relic to offer for this visit (random unowned)
	var pool := GameManager.unowned_relics()
	_shop_relic_offer = pool[0] if not pool.is_empty() else ""
	_popup = Panel.new()
	_popup.position = Vector2(130.0, 130.0)
	_popup.size = Vector2(1020.0, 460.0)
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
	gold_lbl.position = Vector2(860.0, 20.0)
	_popup.add_child(gold_lbl)

	# Heal party
	var heal_btn := _make_shop_button(
		"Heal Party to Full   (%d gold)" % GameManager.SHOP_HEAL_COST,
		Vector2(24.0, 56.0), Vector2(480.0, 70.0),
		Color(0.20, 0.55, 0.30), GameManager.gold >= GameManager.SHOP_HEAL_COST)
	heal_btn.pressed.connect(_on_shop_heal)
	_popup.add_child(heal_btn)

	# Buy a relic (one offered per visit)
	var relic_enabled := _shop_relic_offer != "" and GameManager.gold >= GameManager.SHOP_RELIC_COST
	var relic_txt: String
	if _shop_relic_offer == "":
		relic_txt = "All relics owned"
	else:
		var r: Dictionary = GameManager.RELICS[_shop_relic_offer]
		relic_txt = "Relic: %s   (%d gold)\n%s" % [r["name"], GameManager.SHOP_RELIC_COST, r["desc"]]
	var relic_btn := _make_shop_button(relic_txt,
		Vector2(516.0, 56.0), Vector2(480.0, 70.0),
		Color(0.45, 0.35, 0.62), relic_enabled)
	relic_btn.pressed.connect(_on_shop_relic)
	_popup.add_child(relic_btn)

	# Buy a unit (one button per class) — 4-column grid so it wraps cleanly.
	var keys := GameManager.recruitable_types()
	var cols := 4
	for i in range(keys.size()):
		var utype: String = keys[i]
		var udata: Dictionary = GameManager.UNIT_TYPES[utype]
		var col := i % cols
		var row := i / cols
		var can_afford := GameManager.gold >= GameManager.SHOP_UNIT_COST
		var btn := _make_shop_button(
			"Buy %s\nHP %d  Mv %d\nRng %d  Dmg %d\n%d gold" % [
				udata["name"], udata["max_hp"], udata["move_range"],
				udata["attack_range"], udata["damage"], GameManager.SHOP_UNIT_COST],
			Vector2(20.0 + col * 248.0, 140.0 + row * 124.0), Vector2(235.0, 116.0),
			udata["color"].darkened(0.1), can_afford)
		btn.pressed.connect(_on_shop_buy_unit.bind(utype))
		_popup.add_child(btn)

	var leave := Button.new()
	leave.text = "Leave"
	leave.position = Vector2(24.0, 400.0)
	leave.size = Vector2(972.0, 44.0)
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
		Sfx.play("heal")
		_show_toast("Party healed!", Color(0.30, 0.85, 0.45))
		_populate_shop()

func _on_shop_buy_unit(unit_type: String) -> void:
	if GameManager.spend_gold(GameManager.SHOP_UNIT_COST):
		GameManager.add_unit(unit_type)
		Sfx.play("gold")
		var name_str: String = GameManager.UNIT_TYPES[unit_type]["name"]
		_show_toast("Bought %s!" % name_str, GameManager.UNIT_TYPES[unit_type]["color"])
		_populate_shop()

func _on_shop_relic() -> void:
	if _shop_relic_offer == "":
		return
	if GameManager.spend_gold(GameManager.SHOP_RELIC_COST):
		var id := _shop_relic_offer
		GameManager.add_relic(id)
		Sfx.play("gold")
		_show_toast("Acquired %s!" % GameManager.RELICS[id]["name"], Color(0.65, 0.55, 0.95))
		# Offer the next unowned relic (if any)
		var pool := GameManager.unowned_relics()
		_shop_relic_offer = pool[0] if not pool.is_empty() else ""
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
