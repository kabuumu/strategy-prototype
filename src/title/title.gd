extends Node2D

func _ready() -> void:
	_build_ui()

func _draw() -> void:
	# Background gradient effect — two overlapping rects
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.05, 0.06, 0.09))
	# Subtle decorative line under the title block
	draw_line(Vector2(220.0, 124.0), Vector2(1060.0, 124.0), Color(0.20, 0.22, 0.30, 0.40), 1.0)

const CAMPAIGN_MODES: Array = [
	{"t": "2D Tactics",    "m": "2d",   "c": Color(0.18, 0.36, 0.65)},
	{"t": "3D Real-Time",  "m": "3d",   "c": Color(0.36, 0.26, 0.60)},
	{"t": "Auto-Battler",  "m": "auto", "c": Color(0.30, 0.50, 0.38)},
	{"t": "Tower Defence", "m": "td",   "c": Color(0.45, 0.38, 0.20)},
	{"t": "Base Building", "m": "base", "c": Color(0.50, 0.30, 0.26)},
]

func _build_ui() -> void:
	var has_save: bool = GameManager.has_saved_run()

	_add_centered_label("STRATEGY PROTOTYPE", 56, Color(0.95, 0.90, 0.60), 30.0)
	_add_centered_label("Medieval strategy roguelite — five ways to fight", 18,
		Color(0.55, 0.55, 0.65), 96.0)

	# Continue an in-progress run.
	if has_save:
		_add_menu_button("Continue Run", Vector2(490.0, 132.0), Vector2(300.0, 50.0),
			Color(0.20, 0.55, 0.32), _on_continue, 22)

	# New campaign — pick the battle style the whole run is fought in.
	_add_centered_label("NEW CAMPAIGN — choose your battle style", 15,
		Color(0.72, 0.74, 0.52), 198.0)
	_add_button_row(CAMPAIGN_MODES.map(func(md): return {
			"t": md["t"], "c": md["c"], "cb": _start_new_game.bind(md["m"])
		}), 226.0, 216.0, 64.0, 20)

	# Quick skirmishes — one-off battles, no campaign state touched.
	_add_centered_label("QUICK SKIRMISH — one-off battles, no campaign", 15,
		Color(0.62, 0.66, 0.74), 328.0)
	_add_button_row([
		{"t": "3D Skirmish",   "c": Color(0.45, 0.30, 0.62), "cb": _on_skirmish_3d},
		{"t": "2D Real-Time",  "c": Color(0.32, 0.40, 0.55), "cb": _on_skirmish_2d},
		{"t": "Auto Battle",   "c": Color(0.30, 0.48, 0.36), "cb": _on_auto_battler},
		{"t": "Tower Defence", "c": Color(0.45, 0.38, 0.20), "cb": _on_tower_defense},
		{"t": "Base Building", "c": Color(0.50, 0.30, 0.26), "cb": _on_base_builder},
	], 356.0, 214.0, 52.0, 17)

	_add_centered_label("Left-click act · Right-click / Esc cancel · Tab cycle · Enter end turn · Q ability · H help",
		13, Color(0.40, 0.40, 0.45), 692.0)

	if not has_save:
		_build_meta_panel()

# Centred full-width label helper.
func _add_centered_label(text: String, font_size: int, color: Color, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.modulate = color
	l.position = Vector2(0.0, y)
	l.size = Vector2(1280.0, float(font_size) + 8.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)

# Lay a row of {t, c, cb} buttons centred horizontally at y.
func _add_button_row(items: Array, y: float, bw: float, bh: float, fs: int) -> void:
	var gap: float = 8.0
	var total: float = items.size() * (bw + gap) - gap
	var sx: float = (1280.0 - total) * 0.5
	for i in range(items.size()):
		var it: Dictionary = items[i]
		_add_menu_button(String(it["t"]), Vector2(sx + i * (bw + gap), y),
			Vector2(bw, bh), it["c"], it["cb"], fs)

func _add_menu_button(text: String, pos: Vector2, sz: Vector2, color: Color, cb: Callable, fs: int = -1) -> void:
	var btn := Button.new()
	btn.text     = text
	btn.position = pos
	btn.size     = sz
	btn.add_theme_font_size_override("font_size", fs if fs > 0 else (19 if sz.x < 180.0 else 26))
	btn.add_theme_stylebox_override("normal",  _btn_style(color))
	btn.add_theme_stylebox_override("hover",   _btn_style(color.lightened(0.18)))
	btn.add_theme_stylebox_override("pressed", _btn_style(color.darkened(0.25)))
	btn.add_theme_stylebox_override("focus",   _btn_style(color))
	btn.pressed.connect(cb)
	add_child(btn)

func _btn_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color               = color
	s.corner_radius_top_left     = 8
	s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8
	s.corner_radius_bottom_right = 8
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.border_color = color.lightened(0.3)
	return s

func _start_new_game(mode: String) -> void:
	GameManager.clear_run()   # discard any in-progress run
	GameManager.reset()
	GameManager.battle_mode = mode   # "2d" hex turn-based / "3d" real-time / "auto" auto-battler
	get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

func _on_new_game_2d() -> void:
	_start_new_game("2d")

func _on_new_game_3d() -> void:
	_start_new_game("3d")

func _on_new_game_auto() -> void:
	_start_new_game("auto")

func _on_continue() -> void:
	if GameManager.load_run():
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	else:
		# Corrupt/empty save — fall back to a fresh run
		GameManager.clear_run()
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

func _on_skirmish_3d() -> void:
	# Skirmish is a self-contained battle scene — no campaign state is
	# touched, so the player can dip in and out without losing a run.
	get_tree().change_scene_to_file("res://src/skirmish3d/skirmish3d.tscn")

func _on_skirmish_2d() -> void:
	get_tree().change_scene_to_file("res://src/rtbattle/rtbattle.tscn")

func _on_auto_battler() -> void:
	get_tree().change_scene_to_file("res://src/autobattler/autobattler.tscn")

func _on_tower_defense() -> void:
	get_tree().change_scene_to_file("res://src/towerdefense/towerdefense.tscn")

func _on_base_builder() -> void:
	get_tree().change_scene_to_file("res://src/basebuilder/basebuilder.tscn")

# ---------------------------------------------------------------------------
# Meta-progression panel — shows previous run recap + lifetime bests so the
# title screen rewards repeat play. Hidden entirely on first launch.
# ---------------------------------------------------------------------------
func _build_meta_panel() -> void:
	var has_lifetime: bool = GameManager.total_runs > 0 or GameManager.best_streak_ever > 0
	var has_last_run: bool = GameManager.last_run_tier_reached > 0
	if not has_lifetime and not has_last_run:
		return

	var panel := ColorRect.new()
	panel.color    = Color(0.10, 0.12, 0.18, 0.92)
	panel.position = Vector2(360.0, 452.0)
	panel.size     = Vector2(560.0, 196.0)
	add_child(panel)

	var border := ColorRect.new()
	border.color    = Color(0.30, 0.32, 0.40, 1.0)
	border.position = Vector2(360.0, 452.0)
	border.size     = Vector2(560.0, 2.0)
	add_child(border)

	var header := Label.new()
	header.text = "PROGRESS"
	header.add_theme_font_size_override("font_size", 14)
	header.modulate = Color(0.85, 0.85, 0.45)
	header.position = Vector2(380.0, 462.0)
	add_child(header)

	var y: float = 488.0
	if has_last_run:
		var prefix: String = ("Cleared the campaign!" if GameManager.last_run_won
			else "Reached tier %d / %d" % [GameManager.last_run_tier_reached, GameManager.MAP_TIERS])
		var last := Label.new()
		last.text = "Last run: %s  ·  %d battles won" % [prefix, GameManager.last_run_battles_won]
		last.add_theme_font_size_override("font_size", 14)
		last.modulate = Color(0.80, 0.85, 0.90)
		last.position = Vector2(380.0, y)
		add_child(last)
		y += 24.0

	if has_lifetime:
		var best_tier_str: String = (
			"Best tier:  %d / %d" % [GameManager.best_tier_reached, GameManager.MAP_TIERS]
			if GameManager.best_tier_reached > 0
			else "Best tier:  —"
		)
		var bt := Label.new()
		bt.text = best_tier_str
		bt.add_theme_font_size_override("font_size", 14)
		bt.modulate = Color(0.70, 0.78, 0.90)
		bt.position = Vector2(380.0, y)
		add_child(bt)
		y += 22.0

		var bs := Label.new()
		bs.text = "Best streak:  %d wins" % GameManager.best_streak_ever
		bs.add_theme_font_size_override("font_size", 14)
		bs.modulate = Color(0.70, 0.78, 0.90)
		bs.position = Vector2(380.0, y)
		add_child(bs)
		y += 22.0

		var tr := Label.new()
		tr.text = "Total runs:  %d" % GameManager.total_runs
		tr.add_theme_font_size_override("font_size", 14)
		tr.modulate = Color(0.55, 0.60, 0.70)
		tr.position = Vector2(380.0, y)
		add_child(tr)
