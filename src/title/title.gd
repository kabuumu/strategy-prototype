extends Node2D

func _ready() -> void:
	_build_ui()

func _draw() -> void:
	# Background gradient effect — two overlapping rects
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.05, 0.06, 0.09))
	# Subtle decorative line across the middle
	draw_line(Vector2(0.0, 370.0), Vector2(1280.0, 370.0), Color(0.20, 0.22, 0.30, 0.40), 1.0)

func _build_ui() -> void:
	# -----------------------------------------------------------------------
	# Title
	# -----------------------------------------------------------------------
	var title := Label.new()
	title.text = "STRATEGY PROTOTYPE"
	title.add_theme_font_size_override("font_size", 64)
	title.modulate = Color(0.95, 0.90, 0.60)
	title.position = Vector2(180.0, 160.0)
	add_child(title)

	# Subtitle
	var sub := Label.new()
	sub.text = "A turn-based strategy game"
	sub.add_theme_font_size_override("font_size", 20)
	sub.modulate = Color(0.55, 0.55, 0.65)
	sub.position = Vector2(470.0, 248.0)
	add_child(sub)

	# -----------------------------------------------------------------------
	# Continue (only when a run is saved) + New Game buttons
	# -----------------------------------------------------------------------
	var has_save: bool = GameManager.has_saved_run()
	var y: float = 300.0
	if has_save:
		_add_menu_button("Continue Run", Vector2(490.0, y), Vector2(300.0, 60.0),
			Color(0.20, 0.55, 0.32), _on_continue)
		y += 70.0

	# New run — pick how campaign battles are fought
	_add_menu_button("New Game · 2D Turn-Based", Vector2(490.0, y), Vector2(300.0, 58.0),
		Color(0.18, 0.36, 0.65), _on_new_game_2d)
	y += 64.0
	_add_menu_button("New Game · 3D Real-Time", Vector2(490.0, y), Vector2(300.0, 58.0),
		Color(0.36, 0.26, 0.60), _on_new_game_3d)
	y += 64.0
	_add_menu_button("New Game · Auto-Battler", Vector2(490.0, y), Vector2(300.0, 58.0),
		Color(0.30, 0.50, 0.38), _on_new_game_auto)
	y += 78.0

	# Skirmishes are self-contained battle modes, no campaign state touched.
	_add_menu_button("Skirmish 3D", Vector2(430.0, y), Vector2(120.0, 54.0),
		Color(0.45, 0.30, 0.62), _on_skirmish_3d)
	_add_menu_button("Skirmish 2D", Vector2(580.0, y), Vector2(120.0, 54.0),
		Color(0.32, 0.40, 0.55), _on_skirmish_2d)
	_add_menu_button("Auto Battle", Vector2(730.0, y), Vector2(120.0, 54.0),
		Color(0.30, 0.48, 0.36), _on_auto_battler)

	var hint := Label.new()
	hint.text = "Left-click to act  ·  Right-click / Esc cancel  ·  Tab cycles units  ·  Enter ends turn  ·  Q ability  ·  T threat  ·  E enemy intent  ·  F fast-forward  ·  Press H for full help"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.40, 0.40, 0.45)
	hint.position = Vector2(60.0, 680.0)
	add_child(hint)

	if not has_save:
		_build_meta_panel()

func _add_menu_button(text: String, pos: Vector2, sz: Vector2, color: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text     = text
	btn.position = pos
	btn.size     = sz
	btn.add_theme_font_size_override("font_size", 19 if sz.x < 180.0 else 26)
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
	panel.position = Vector2(440.0, 510.0)
	panel.size     = Vector2(400.0, 150.0)
	add_child(panel)

	var border := ColorRect.new()
	border.color    = Color(0.30, 0.32, 0.40, 1.0)
	border.position = Vector2(440.0, 510.0)
	border.size     = Vector2(400.0, 2.0)
	add_child(border)

	var header := Label.new()
	header.text = "PROGRESS"
	header.add_theme_font_size_override("font_size", 14)
	header.modulate = Color(0.85, 0.85, 0.45)
	header.position = Vector2(456.0, 520.0)
	add_child(header)

	var y: float = 544.0
	if has_last_run:
		var prefix: String = ("Cleared the campaign!" if GameManager.last_run_won
			else "Reached tier %d / %d" % [GameManager.last_run_tier_reached, GameManager.MAP_TIERS])
		var last := Label.new()
		last.text = "Last run: %s  ·  %d battles won" % [prefix, GameManager.last_run_battles_won]
		last.add_theme_font_size_override("font_size", 14)
		last.modulate = Color(0.80, 0.85, 0.90)
		last.position = Vector2(456.0, y)
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
		bt.position = Vector2(456.0, y)
		add_child(bt)
		y += 22.0

		var bs := Label.new()
		bs.text = "Best streak:  %d wins" % GameManager.best_streak_ever
		bs.add_theme_font_size_override("font_size", 14)
		bs.modulate = Color(0.70, 0.78, 0.90)
		bs.position = Vector2(456.0, y)
		add_child(bs)
		y += 22.0

		var tr := Label.new()
		tr.text = "Total runs:  %d" % GameManager.total_runs
		tr.add_theme_font_size_override("font_size", 14)
		tr.modulate = Color(0.55, 0.60, 0.70)
		tr.position = Vector2(456.0, y)
		add_child(tr)
