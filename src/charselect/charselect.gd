extends Node2D

# Character Select — pick a hero, then start a fresh auto-battler campaign.
# All UI is built in code (project convention: no UI nodes in the .tscn).

# Six heroes (3 starters + 3 unlockable) laid out as two rows of three.
const CARD_W: float = 380.0
const CARD_H: float = 246.0
const CARD_GAP_X: float = 26.0
const CARD_GAP_Y: float = 22.0
const COLS: int = 3
const CARD_TOP: float = 138.0

func _ready() -> void:
	Music.play("title")
	_build_ui()

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), UITheme.BG)
	draw_line(Vector2(220.0, 116.0), Vector2(1060.0, 116.0), UITheme.LINE, 1.0)

func _build_ui() -> void:
	add_child(UITheme.label("CHOOSE YOUR HERO", 44, UITheme.GOLD,
		Vector2(0.0, 28.0), Vector2(1280.0, 56.0)))
	var heading := get_child(get_child_count() - 1) as Label
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	add_child(UITheme.label("Your hero shapes how the campaign begins — and how each fight can be won.",
		17, UITheme.TEXT_MUTED, Vector2(0.0, 82.0), Vector2(1280.0, 26.0)))
	var sub := get_child(get_child_count() - 1) as Label
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var count: int = GameManager.HERO_IDS.size()
	var row_w: float = COLS * CARD_W + (COLS - 1) * CARD_GAP_X
	var start_x: float = (1280.0 - row_w) * 0.5
	for i in range(count):
		var col: int = i % COLS
		var row: int = i / COLS
		var pos := Vector2(
			start_x + col * (CARD_W + CARD_GAP_X),
			CARD_TOP + row * (CARD_H + CARD_GAP_Y))
		_build_card(GameManager.HERO_IDS[i], pos)

	add_child(UITheme.button("Back", Vector2(540.0, 666.0), Vector2(200.0, 40.0),
		Color(0.30, 0.32, 0.44), _on_back, 18))

func _build_card(hero_id: String, pos: Vector2) -> void:
	var hero: Dictionary = GameManager.HEROES[hero_id]
	var unlocked: bool = GameManager.is_hero_unlocked(hero_id)

	# Locked cards are dimmed: darker panel, greyed text, inactive Choose button.
	var panel_bg: Color = UITheme.PANEL if unlocked else UITheme.PANEL.darkened(0.45)
	var panel_border: Color = UITheme.LINE if unlocked else UITheme.LINE.darkened(0.4)
	UITheme.panel(self, pos, Vector2(CARD_W, CARD_H), panel_bg, panel_border)

	var gold: Color = UITheme.GOLD if unlocked else UITheme.GOLD.darkened(0.5)
	var text_col: Color = UITheme.TEXT if unlocked else UITheme.TEXT_MUTED.darkened(0.2)

	# Portrait (left) — dimmed when locked.
	var tex: Texture2D = load("res://assets/units/%s_player.png" % hero["sprite_key"])
	if tex != null:
		var portrait := TextureRect.new()
		portrait.texture = tex
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.position = pos + Vector2(18.0, 18.0)
		portrait.size = Vector2(72.0, 72.0)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			portrait.modulate = Color(0.45, 0.45, 0.5, 0.8)
		add_child(portrait)

	# Name (right of portrait).
	var name_lbl := UITheme.label(str(hero["name"]), 24, gold,
		pos + Vector2(102.0, 22.0), Vector2(CARD_W - 120.0, 30.0))
	add_child(name_lbl)

	if unlocked:
		# Blurb.
		add_child(UITheme.label(str(hero["blurb"]), 14, text_col,
			pos + Vector2(102.0, 54.0), Vector2(CARD_W - 120.0, 44.0)))
	else:
		# Locked hint replaces the blurb.
		add_child(UITheme.label("🔒 Locked — %s" % GameManager.hero_unlock_hint(hero_id),
			14, UITheme.GOLD.darkened(0.25),
			pos + Vector2(102.0, 54.0), Vector2(CARD_W - 120.0, 44.0)))

	# Info lines (full width, below portrait/name).
	var buff: Dictionary = hero["buff"]
	var blue: Color = UITheme.BLUE.lightened(0.25) if unlocked else UITheme.BLUE.darkened(0.15)
	var green: Color = UITheme.GREEN.lightened(0.18) if unlocked else UITheme.GREEN.darkened(0.3)
	var gold_sway: Color = UITheme.GOLD.lightened(0.1) if unlocked else UITheme.GOLD.darkened(0.45)
	var y: float = pos.y + 104.0
	add_child(UITheme.label("Fight:  %s Lv%d" % [str(hero["fight_archetype"]).capitalize(),
		int(hero["fight_level"])], 14, blue,
		Vector2(pos.x + 18.0, y), Vector2(CARD_W - 36.0, 22.0)))
	y += 26.0
	add_child(UITheme.label("Aura:  %s — %s" % [str(buff["name"]),
		str(buff["desc"])], 14, green,
		Vector2(pos.x + 18.0, y), Vector2(CARD_W - 36.0, 40.0)))
	y += 44.0
	add_child(UITheme.label("Sways:  %s" % _best_sway(hero["sway_aptitudes"]), 14,
		gold_sway, Vector2(pos.x + 18.0, y), Vector2(CARD_W - 36.0, 22.0)))

	# Choose button — disabled (and visibly inactive) for locked heroes.
	var btn := UITheme.button("Choose",
		pos + Vector2((CARD_W - 180.0) * 0.5, CARD_H - 50.0),
		Vector2(180.0, 38.0), UITheme.GREEN.darkened(0.1), _on_choose.bind(hero_id), 18)
	if not unlocked:
		btn.disabled = true
		var dis := UITheme.button_style(Color(0.16, 0.17, 0.20))
		dis.border_color = Color(0.22, 0.23, 0.27)
		btn.add_theme_stylebox_override("disabled", dis)
		btn.add_theme_color_override("font_disabled_color", UITheme.TEXT_MUTED.darkened(0.25))
	add_child(btn)

# Returns the display name of the highest sway aptitude.
func _best_sway(aptitudes: Dictionary) -> String:
	var labels: Dictionary = {"dialogue": "Dialogue", "persuasion": "Persuasion", "duel": "Duels"}
	var best_key: String = "dialogue"
	var best_val: int = -1
	for key in ["dialogue", "persuasion", "duel"]:
		var v: int = int(aptitudes.get(key, 0))
		if v > best_val:
			best_val = v
			best_key = key
	return str(labels.get(best_key, best_key.capitalize()))

func _on_choose(hero_id: String) -> void:
	# Guard: locked heroes are never selectable (button is disabled, but be safe).
	if not GameManager.is_hero_unlocked(hero_id):
		return
	# Start the run immediately. The permanent skill tree is earned/spent
	# in-game (press T on the overworld), not in this dialog.
	# Order matters: reset() before select_hero() so the roster/gold exist for
	# the hero's start_bonus. hero_meta (the tree) is NOT cleared by reset().
	GameManager.clear_run()
	GameManager.reset()
	GameManager.battle_mode = "auto"
	GameManager.select_hero(hero_id)
	get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_back()
