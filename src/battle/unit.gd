class_name Unit
extends Node2D

const TILE_SIZE: int = 70

var unit_type: String = "soldier"
var team: int = 0          # 0 = player, 1 = enemy
var hp: int = 100
var max_hp: int = 100
var grid_pos: Vector2i = Vector2i.ZERO
var has_acted: bool = false

var _body: ColorRect
var _hp_bar: ColorRect
var _label: Label

# ---------------------------------------------------------------------------
func setup(type: String, p_team: int, pos: Vector2i) -> void:
	unit_type = type
	team      = p_team
	grid_pos  = pos

	var udata: Dictionary = GameManager.UNIT_TYPES[unit_type]
	max_hp = udata["max_hp"]
	hp     = max_hp

	_build_visuals(udata)
	update_visual_position()

func _build_visuals(udata: Dictionary) -> void:
	var color: Color = udata["color"]
	# Enemies get a red tint so they're visually distinct
	if team == 1:
		color = color.lerp(Color(0.9, 0.2, 0.2), 0.45)

	# Team stripe above the body
	var stripe := ColorRect.new()
	stripe.size     = Vector2(52.0, 5.0)
	stripe.position = Vector2(-26.0, -35.0)
	stripe.color    = Color(0.2, 0.5, 1.0) if team == 0 else Color(1.0, 0.2, 0.2)
	add_child(stripe)

	# Main body
	_body = ColorRect.new()
	_body.size     = Vector2(52.0, 52.0)
	_body.position = Vector2(-26.0, -26.0)
	_body.color    = color
	add_child(_body)

	# Unit-type initial
	_label = Label.new()
	_label.text     = udata["name"][0]
	_label.position = Vector2(-8.0, -14.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	add_child(_label)

	# HP bar background
	var hp_bg := ColorRect.new()
	hp_bg.size     = Vector2(52.0, 7.0)
	hp_bg.position = Vector2(-26.0, 28.0)
	hp_bg.color    = Color(0.15, 0.15, 0.15)
	add_child(hp_bg)

	# HP bar fill
	_hp_bar = ColorRect.new()
	_hp_bar.size     = Vector2(52.0, 7.0)
	_hp_bar.position = Vector2(-26.0, 28.0)
	_hp_bar.color    = Color(0.2, 0.9, 0.2)
	add_child(_hp_bar)

# ---------------------------------------------------------------------------
func update_visual_position() -> void:
	position = Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2
	)

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	_refresh_hp_bar()

func _refresh_hp_bar() -> void:
	var ratio: float = float(hp) / float(max_hp)
	_hp_bar.size.x = 52.0 * ratio
	# Green → yellow → red as HP drops
	_hp_bar.color = Color(min(1.0, 2.0 * (1.0 - ratio)), min(1.0, 2.0 * ratio), 0.05)

func is_alive() -> bool:
	return hp > 0

func get_move_range() -> int:
	return GameManager.UNIT_TYPES[unit_type]["move_range"]

func get_attack_range() -> int:
	return GameManager.UNIT_TYPES[unit_type]["attack_range"]

func get_damage() -> int:
	return GameManager.UNIT_TYPES[unit_type]["damage"]
