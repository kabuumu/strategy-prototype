extends Node2D

# Character Select — pick a hero, then start a fresh auto-battler campaign.
# All UI is built in code (project convention: no UI nodes in the .tscn).

const CARD_W: float = 360.0
const CARD_H: float = 460.0
const CARD_GAP: float = 40.0
const CARD_TOP: float = 168.0

func _ready() -> void:
	Music.play("title")
	_build_ui()

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), UITheme.BG)
	draw_line(Vector2(220.0, 132.0), Vector2(1060.0, 132.0), UITheme.LINE, 1.0)

func _build_ui() -> void:
	add_child(UITheme.label("CHOOSE YOUR HERO", 48, UITheme.GOLD,
		Vector2(0.0, 36.0), Vector2(1280.0, 60.0)))
	var heading := get_child(get_child_count() - 1) as Label
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	add_child(UITheme.label("Your hero shapes how the campaign begins — and how each fight can be won.",
		18, UITheme.TEXT_MUTED, Vector2(0.0, 96.0), Vector2(1280.0, 28.0)))
	var sub := get_child(get_child_count() - 1) as Label
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var count: int = GameManager.HERO_IDS.size()
	var total_w: float = count * CARD_W + (count - 1) * CARD_GAP
	var start_x: float = (1280.0 - total_w) * 0.5
	for i in range(count):
		var hero_id: String = GameManager.HERO_IDS[i]
		_build_card(hero_id, Vector2(start_x + i * (CARD_W + CARD_GAP), CARD_TOP))

	add_child(UITheme.button("Back", Vector2(540.0, 656.0), Vector2(200.0, 44.0),
		Color(0.30, 0.32, 0.44), _on_back, 18))

func _build_card(hero_id: String, pos: Vector2) -> void:
	var hero: Dictionary = GameManager.HEROES[hero_id]
	UITheme.panel(self, pos, Vector2(CARD_W, CARD_H))

	# Portrait.
	var tex: Texture2D = load("res://assets/units/%s_player.png" % hero["sprite_key"])
	if tex != null:
		var portrait := TextureRect.new()
		portrait.texture = tex
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.position = pos + Vector2((CARD_W - 96.0) * 0.5, 20.0)
		portrait.size = Vector2(96.0, 96.0)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(portrait)

	# Name.
	var name_lbl := UITheme.label(str(hero["name"]), 26, UITheme.GOLD,
		pos + Vector2(0.0, 124.0), Vector2(CARD_W, 32.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_lbl)

	# Blurb.
	add_child(UITheme.label(str(hero["blurb"]), 15, UITheme.TEXT,
		pos + Vector2(20.0, 164.0), Vector2(CARD_W - 40.0, 60.0)))

	# Info lines.
	var buff: Dictionary = hero["buff"]
	var y: float = pos.y + 234.0
	add_child(UITheme.label("Fight:  %s Lv%d" % [str(hero["fight_archetype"]).capitalize(),
		int(hero["fight_level"])], 15, UITheme.BLUE.lightened(0.25),
		Vector2(pos.x + 20.0, y), Vector2(CARD_W - 40.0, 24.0)))
	y += 32.0
	add_child(UITheme.label("Buff:  %s — %s (%d Valor)" % [str(buff["name"]),
		str(buff["desc"]), int(buff["cost"])], 15, UITheme.GREEN.lightened(0.18),
		Vector2(pos.x + 20.0, y), Vector2(CARD_W - 40.0, 44.0)))
	y += 52.0
	add_child(UITheme.label("Sways:  %s" % _best_sway(hero["sway_aptitudes"]), 15,
		UITheme.GOLD.lightened(0.1), Vector2(pos.x + 20.0, y), Vector2(CARD_W - 40.0, 24.0)))

	# Choose button.
	add_child(UITheme.button("Choose", pos + Vector2((CARD_W - 200.0) * 0.5, CARD_H - 60.0),
		Vector2(200.0, 44.0), UITheme.GREEN.darkened(0.1), _on_choose.bind(hero_id), 20))

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
	# Order matters: reset() must run before select_hero() so the roster/gold
	# exist for the hero's start_bonus to add to.
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
