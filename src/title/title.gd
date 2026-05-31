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

	# -----------------------------------------------------------------------
	# Controls hint
	# -----------------------------------------------------------------------
	var hint := Label.new()
	hint.text = "Left-click to act  ·  Right-click / Esc to cancel  ·  Tab cycles units  ·  Enter ends turn  ·  T threat overlay  ·  F fast-forward (2×)  ·  Forests grant defenders −25% dmg"
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
