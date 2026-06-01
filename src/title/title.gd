extends Node2D

func _ready() -> void:
	Music.play("title")
	_build_ui()

func _draw() -> void:
	# Background gradient effect — two overlapping rects
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.05, 0.06, 0.09))
	# Subtle decorative line under the title block
	draw_line(Vector2(220.0, 124.0), Vector2(1060.0, 124.0), Color(0.20, 0.22, 0.30, 0.40), 1.0)

func _build_ui() -> void:
	var has_save: bool = GameManager.has_saved_run()

	_add_centered_label("STRATEGY PROTOTYPE", 56, Color(0.95, 0.90, 0.60), 30.0)
	_add_centered_label("Medieval strategy roguelite — build an army, auto-resolve the fights", 18,
		Color(0.55, 0.55, 0.65), 96.0)

	# Continue an in-progress run.
	if has_save:
		_add_menu_button("Continue Run", Vector2(490.0, 200.0), Vector2(300.0, 56.0),
			Color(0.20, 0.55, 0.32), _on_continue, 24)

	# New campaign — pick a hero, then start an auto-battler roguelite run.
	_add_menu_button("New Campaign", Vector2(490.0, 280.0), Vector2(300.0, 56.0),
		Color(0.30, 0.50, 0.38), _on_new_campaign, 24,
		"Choose a hero, then your roster auto-resolves each fight. Strength comes from the army you've built.")

	# Quick skirmish — a one-off auto battle, no campaign state touched.
	_add_menu_button("Quick Auto Battle", Vector2(490.0, 356.0), Vector2(300.0, 50.0),
		Color(0.28, 0.44, 0.34), _on_auto_battler, 20,
		"A single auto-resolved fight — no campaign state touched.")

	_add_centered_label("H help · Esc back",
		13, Color(0.40, 0.40, 0.45), 692.0)

	_add_menu_button("Settings", Vector2(1120.0, 24.0), Vector2(140.0, 40.0),
		Color(0.26, 0.28, 0.38), _show_settings, 16)

	if not has_save:
		_build_meta_panel()

var _settings_overlay: Control = null

func _show_settings() -> void:
	if _settings_overlay != null:
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := ColorRect.new()
	panel.color = Color(0.10, 0.12, 0.18, 0.99)
	panel.position = Vector2(440.0, 250.0)
	panel.size = Vector2(400.0, 220.0)
	root.add_child(panel)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(0.95, 0.90, 0.60)
	title.position = Vector2(466.0, 268.0)
	root.add_child(title)
	var vol_lbl := Label.new()
	vol_lbl.add_theme_font_size_override("font_size", 16)
	vol_lbl.modulate = Color(0.82, 0.86, 0.92)
	vol_lbl.position = Vector2(466.0, 322.0)
	vol_lbl.text = "Master Volume: %d%%" % int(round(GameManager.master_volume * 100.0))
	root.add_child(vol_lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = GameManager.master_volume
	slider.position = Vector2(466.0, 352.0)
	slider.size = Vector2(348.0, 24.0)
	slider.value_changed.connect(func(v: float) -> void:
		GameManager.set_master_volume(v)
		vol_lbl.text = "Master Volume: %d%%" % int(round(v * 100.0)))
	root.add_child(slider)
	root.add_child(UITheme.button("Close", Vector2(530.0, 410.0), Vector2(220.0, 44.0),
		Color(0.30, 0.32, 0.44), _close_settings))
	add_child(root)
	_settings_overlay = root

func _close_settings() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null

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

func _add_menu_button(text: String, pos: Vector2, sz: Vector2, color: Color, cb: Callable, fs: int = -1, tip: String = "") -> void:
	var btn := Button.new()
	btn.text     = text
	btn.position = pos
	btn.size     = sz
	if tip != "":
		btn.tooltip_text = tip
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

func _on_new_campaign() -> void:
	# Route to character select; the chosen hero kicks off the auto-battler run.
	get_tree().change_scene_to_file("res://src/charselect/charselect.tscn")

func _on_continue() -> void:
	if GameManager.load_run():
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	else:
		# Corrupt/empty save — fall back to a fresh run
		GameManager.clear_run()
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

func _on_auto_battler() -> void:
	# Quick skirmish — self-contained, no campaign state touched.
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
