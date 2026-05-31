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
	# New Game button
	# -----------------------------------------------------------------------
	var btn := Button.new()
	btn.text     = "New Game"
	btn.position = Vector2(490.0, 360.0)
	btn.size     = Vector2(300.0, 70.0)
	btn.add_theme_font_size_override("font_size", 28)

	var style_normal := _btn_style(Color(0.18, 0.36, 0.65))
	var style_hover  := _btn_style(Color(0.28, 0.50, 0.85))
	var style_press  := _btn_style(Color(0.12, 0.26, 0.50))
	btn.add_theme_stylebox_override("normal",  style_normal)
	btn.add_theme_stylebox_override("hover",   style_hover)
	btn.add_theme_stylebox_override("pressed", style_press)
	btn.add_theme_stylebox_override("focus",   style_normal)

	btn.pressed.connect(_on_new_game)
	add_child(btn)

	_build_meta_panel()

	# -----------------------------------------------------------------------
	# Controls hint
	# -----------------------------------------------------------------------
	var hint := Label.new()
	hint.text = "Left-click to act  ·  Right-click / Esc to cancel  ·  Tab cycles units  ·  Enter ends turn  ·  Q uses ability  ·  T threat overlay  ·  F fast-forward (2×)  ·  Forests grant defenders −25% dmg"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.40, 0.40, 0.45)
	hint.position = Vector2(60.0, 680.0)
	add_child(hint)

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

func _on_new_game() -> void:
	GameManager.reset()
	get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

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
	panel.position = Vector2(440.0, 460.0)
	panel.size     = Vector2(400.0, 170.0)
	add_child(panel)

	var border := ColorRect.new()
	border.color    = Color(0.30, 0.32, 0.40, 1.0)
	border.position = Vector2(440.0, 460.0)
	border.size     = Vector2(400.0, 2.0)
	add_child(border)

	var header := Label.new()
	header.text = "PROGRESS"
	header.add_theme_font_size_override("font_size", 14)
	header.modulate = Color(0.85, 0.85, 0.45)
	header.position = Vector2(456.0, 470.0)
	add_child(header)

	var y: float = 494.0
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
