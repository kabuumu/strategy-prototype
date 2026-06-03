extends Control
# Deck management screen (Spec B) — view your Card deck and prune unwanted cards.
# Opened from the overworld; cards removed here go to the graveyard for the run.

const UITheme := preload("res://src/ui/ui_theme.gd")

var _on_close: Callable = Callable()

func setup(on_close: Callable) -> void:
	_on_close = on_close
	z_index = 300
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.86)
	dim.size = Vector2(1280.0, 720.0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	UITheme.panel(self, Vector2(240.0, 56.0), Vector2(800.0, 608.0), UITheme.PANEL, UITheme.LINE)
	add_child(UITheme.label("YOUR DECK", 28, UITheme.GOLD, Vector2(264.0, 70.0), Vector2(500.0, 36.0)))
	add_child(UITheme.label("Draw pile %d  ·  Hand %d  ·  Spent %d   —   remove cards to prune your deck" % [
		GameManager.card_deck.size(), GameManager.card_hand.size(), GameManager.card_graveyard.size()],
		14, UITheme.TEXT_MUTED, Vector2(264.0, 110.0), Vector2(740.0, 22.0)))

	# Combine hand + draw pile, counted by id.
	var counts: Dictionary = {}
	for id in GameManager.card_hand:
		counts[id] = int(counts.get(id, 0)) + 1
	for id in GameManager.card_deck:
		counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()

	if ids.is_empty():
		add_child(UITheme.label("— deck empty —", 15, UITheme.TEXT_MUTED, Vector2(280.0, 160.0), Vector2(520.0, 22.0)))
	var y: float = 150.0
	for id in ids:
		if y > 588.0:
			break
		var cd: Dictionary = GameManager.card_def(String(id))
		var cat: String = String(cd.get("category", ""))
		add_child(UITheme.label("%s   ×%d   [%s]" % [String(cd.get("name", id)), int(counts[id]), cat],
			14, UITheme.TEXT, Vector2(284.0, y + 6.0), Vector2(520.0, 22.0)))
		add_child(UITheme.button("Remove", Vector2(852.0, y), Vector2(120.0, 32.0),
			Color(0.50, 0.28, 0.28), _on_prune.bind(String(id)), 13))
		y += 40.0

	add_child(UITheme.button("Close", Vector2(560.0, 636.0), Vector2(160.0, 40.0),
		Color(0.30, 0.32, 0.44), _on_close_pressed, 16))

func _on_prune(id: String) -> void:
	if GameManager.card_prune(id):
		GameManager.save_run()
		_rebuild()

func _on_close_pressed() -> void:
	var cb := _on_close
	queue_free()
	if cb.is_valid():
		cb.call()
