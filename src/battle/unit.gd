class_name Unit
extends Node2D

const TILE_SIZE: int = 70

var unit_type: String = "soldier"
var team: int = 0          # 0 = player, 1 = enemy
var hp: int = 100
var max_hp: int = 100
var grid_pos: Vector2i = Vector2i.ZERO
var has_acted: bool = false
var stunned: bool = false       # skips its next activation
var ability_used: bool = false  # special ability is once per battle

var _body: Sprite2D
var _hp_bar: ColorRect

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

func _build_visuals(_udata: Dictionary) -> void:
	# Team stripe above the body
	var stripe := ColorRect.new()
	stripe.size     = Vector2(52.0, 5.0)
	stripe.position = Vector2(-26.0, -35.0)
	stripe.color    = Color(0.2, 0.5, 1.0) if team == 0 else Color(1.0, 0.2, 0.2)
	add_child(stripe)

	# Main body — pixel-art sprite (class by silhouette, team by palette)
	var team_name: String = "player" if team == 0 else "enemy"
	var tex: Texture2D = load("res://assets/units/%s_%s.png" % [unit_type, team_name])
	_body = Sprite2D.new()
	_body.texture        = tex
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixels
	_body.scale          = Vector2(1.7, 1.7)                  # 32px → ~54px
	add_child(_body)

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

# Animate this unit walking along a sequence of world-space points (one per
# tile, in visit order, starting from the unit's current tile). Returns the
# tween so callers can `await tw.finished`. Snaps to the final point at the
# end so logical/visual state stay in sync.
func animate_move_along(world_points: Array) -> Tween:
	var tw := create_tween()
	if world_points.is_empty():
		# No-op tween that completes immediately, so await is safe
		tw.tween_interval(0.0)
		return tw
	# Per-tile hop duration with a tiny ease — feels like running, not gliding
	var per_step := 0.07
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for p: Vector2 in world_points:
		tw.tween_property(self, "position", p, per_step)
	# Safety snap in case any property tween rounded oddly
	tw.tween_callback(update_visual_position)
	return tw

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	_refresh_hp_bar()
	_spawn_damage_number(amount)
	_flash_hit()

# Floating damage number that drifts up and fades
func _spawn_damage_number(amount: int) -> void:
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.modulate = Color(1.0, 0.85, 0.2)
	lbl.position = Vector2(-12.0, -34.0)
	lbl.z_index  = 100
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", -58.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tw.chain().tween_callback(lbl.queue_free)

# Quick red flash on the sprite (independent of the unit's acted/dead tint)
func _flash_hit() -> void:
	if not _body:
		return
	_body.modulate = Color(1.8, 0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(_body, "modulate", Color(1.0, 1.0, 1.0), 0.25)

# Floating status word (e.g. "STUNNED!") that rises and fades
func show_status_popup(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.modulate = color
	lbl.position = Vector2(-26.0, -48.0)
	lbl.z_index  = 100
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", -70.0, 0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(lbl.queue_free)

func get_ability() -> Dictionary:
	return GameManager.UNIT_TYPES[unit_type].get("ability", {})

func _refresh_hp_bar() -> void:
	var ratio: float = float(hp) / float(max_hp)
	_hp_bar.size.x = 52.0 * ratio
	# Green → yellow → red as HP drops
	_hp_bar.color = Color(min(1.0, 2.0 * (1.0 - ratio)), min(1.0, 2.0 * ratio), 0.05)

func is_alive() -> bool:
	return hp > 0

# Floating coloured label (e.g. "CRIT!" / "FLANKED!") shown above the unit.
func show_combat_label(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = color
	lbl.position = Vector2(-26.0, -54.0)
	lbl.z_index  = 101
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", -78.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.30)
	tw.chain().tween_callback(lbl.queue_free)

func get_move_range() -> int:
	return GameManager.UNIT_TYPES[unit_type]["move_range"]

func get_attack_range() -> int:
	return GameManager.UNIT_TYPES[unit_type]["attack_range"]

func get_damage() -> int:
	return GameManager.UNIT_TYPES[unit_type]["damage"]
