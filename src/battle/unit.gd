class_name Unit
extends Node2D

const TILE_SIZE: int = 70

var unit_type: String = "soldier"
var team: int = 0          # 0 = player, 1 = enemy
var hp: int = 100
var max_hp: int = 100
var grid_pos: Vector2i = Vector2i.ZERO
var has_acted: bool = false
var stunned: bool = false:       # skips its next activation
	set(v):
		stunned = v
		_refresh_status_badge()
var ability_used: bool = false  # special ability is once per battle
var upgrades: Array = []        # roguelike upgrades (see GameManager.UPGRADE_TYPES)
var enraged: bool = false       # boss state: gives stat bonuses
var poison_turns: int = 0:       # damage-over-time at round start
	set(v):
		poison_turns = v
		_refresh_status_badge()
var burn_turns: int = 0:
	set(v):
		burn_turns = v
		_refresh_status_badge()

func apply_poison(turns: int) -> void:
	poison_turns = maxi(poison_turns, turns)

func apply_burn(turns: int) -> void:
	burn_turns = maxi(burn_turns, turns)

var _body: Sprite2D
var _status_label: Label
var _hp_bar: ColorRect
var _float_slot: int = 0   # next free vertical slot for stacked floating text
var _bob_tween: Tween      # looping idle breathing animation

# ---------------------------------------------------------------------------
func setup(type: String, p_team: int, pos: Vector2i) -> void:
	unit_type = type
	team      = p_team
	grid_pos  = pos

	var udata: Dictionary = GameManager.UNIT_TYPES[unit_type]
	max_hp = udata["max_hp"]
	# VETERAN upgrade: +20 max HP per stack (applied here so HP bar/initial fill are right)
	for u in upgrades:
		if u == "veteran":
			max_hp += 20
	if team == 0:
		max_hp += GameManager.relic_max_hp_bonus()
	hp     = max_hp

	_build_visuals(udata)
	update_visual_position()
	_start_idle_bob()

# Gentle looping breathing bob so idle units feel alive. Killed before the
# death animation (which drives _body.position.y itself).
func _start_idle_bob() -> void:
	if _body == null:
		return
	_bob_tween = create_tween().set_loops()
	# Slight per-unit phase offset so a formation doesn't bob in lockstep
	var off := float((grid_pos.x + grid_pos.y) % 3) * 0.1
	_bob_tween.tween_interval(off)
	_bob_tween.tween_property(_body, "position:y", -3.0, 0.95) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_body, "position:y", 0.0, 0.95) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _build_visuals(udata: Dictionary) -> void:
	var is_boss: bool = bool(udata.get("is_boss", false))

	# Boss-only red aura ring behind everything else
	if is_boss:
		var aura := ColorRect.new()
		aura.size     = Vector2(80.0, 80.0)
		aura.position = Vector2(-40.0, -40.0)
		aura.color    = Color(1.0, 0.18, 0.18, 0.18)
		add_child(aura)

	# Team stripe above the body
	var stripe := ColorRect.new()
	var stripe_w: float = 64.0 if is_boss else 52.0
	stripe.size     = Vector2(stripe_w, 5.0)
	stripe.position = Vector2(-stripe_w * 0.5, -44.0 if is_boss else -35.0)
	stripe.color    = Color(0.2, 0.5, 1.0) if team == 0 else Color(1.0, 0.2, 0.2)
	add_child(stripe)

	# Main body — pixel-art sprite (class by silhouette, team by palette;
	# bosses have their own sprite under their type name).
	var sprite_key: String = String(udata.get("sprite_unit", unit_type))
	var team_name: String = "player" if team == 0 else "enemy"
	var tex: Texture2D = load("res://assets/units/%s_%s.png" % [sprite_key, team_name])
	_body = Sprite2D.new()
	_body.texture        = tex
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixels
	var s: float = 2.3 if is_boss else 1.7
	# Face inward: players look right (toward the enemy side), enemies look left.
	_body.scale = Vector2(-s if team == 1 else s, s)
	add_child(_body)

	# Boss nameplate
	if is_boss:
		var nameplate := Label.new()
		nameplate.text = "BOSS — %s" % String(udata.get("name", "Boss"))
		nameplate.add_theme_font_size_override("font_size", 11)
		nameplate.modulate = Color(1.0, 0.55, 0.30)
		nameplate.position = Vector2(-36.0, -60.0)
		add_child(nameplate)

	# HP bar background
	var hp_bg := ColorRect.new()
	var bar_w: float = 64.0 if is_boss else 52.0
	hp_bg.size     = Vector2(bar_w, 7.0)
	hp_bg.position = Vector2(-bar_w * 0.5, 32.0 if is_boss else 28.0)
	hp_bg.color    = Color(0.15, 0.15, 0.15)
	add_child(hp_bg)

	# HP bar fill
	_hp_bar = ColorRect.new()
	_hp_bar.size     = Vector2(bar_w, 7.0)
	_hp_bar.position = Vector2(-bar_w * 0.5, 32.0 if is_boss else 28.0)
	_hp_bar.color    = Color(0.2, 0.9, 0.2)
	add_child(_hp_bar)

	# Persistent status badge (stun / poison / burn icons). Empty until a
	# status flag flips, then updated via the property setters above.
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.position = Vector2(-26.0, -52.0 if is_boss else -48.0)
	_status_label.size     = Vector2(52.0, 14.0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)
	_refresh_status_badge()

func _refresh_status_badge() -> void:
	# Setter is called during initial var assignment before _build_visuals
	# runs, so guard against the label not existing yet.
	if _status_label == null:
		return
	var parts: PackedStringArray = []
	if stunned:
		parts.append("[⚡STUN]")
	if poison_turns > 0:
		parts.append("[☠%d]" % poison_turns)
	if burn_turns > 0:
		parts.append("[🔥%d]" % burn_turns)
	_status_label.text = " ".join(parts)
	# Colour the whole badge by the highest-priority effect
	if stunned:
		_status_label.modulate = Color(1.0, 0.85, 0.30)
	elif burn_turns > 0:
		_status_label.modulate = Color(1.0, 0.55, 0.20)
	elif poison_turns > 0:
		_status_label.modulate = Color(0.55, 1.0, 0.40)

# ---------------------------------------------------------------------------
func update_visual_position() -> void:
	# Hex centre, local to _grid_node (the parent already carries GRID_OFFSET).
	position = Hex.center_v(grid_pos)

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

# Plays a quick fall-and-fade on the dying unit's body. Called by battle.gd
# after _kill_punch so the death animation lands during the slow-mo window.
# Caller is responsible for the grey-tint final state and any logic — this
# is purely cosmetic and never queue_frees self.
func play_death_animation() -> void:
	if not _body:
		return
	# Stop the idle bob so it doesn't fight the collapse tween
	if _bob_tween and _bob_tween.is_valid():
		_bob_tween.kill()
	var tw := create_tween()
	tw.set_parallel(true)
	# Drop and tilt — like the unit collapsing
	tw.tween_property(_body, "rotation", deg_to_rad(80.0), 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "position:y",
			_body.position.y + 18.0, 0.45).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_body, "modulate:a", 0.55, 0.45)

# Unified floating text. Concurrent messages are stacked into vertical slots
# so they never overlap; each rises and fades, then frees its slot. This is the
# single entry point for damage numbers, combat tags, and ability/status words.
func float_text(text: String, color: Color, font_size: int = 16, emphasis: bool = false) -> void:
	var slot := _float_slot
	_float_slot += 1
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = color
	lbl.z_index  = 101 if emphasis else 100
	lbl.size = Vector2(60.0, 16.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var y0 := -34.0 - float(slot) * 18.0
	lbl.position = Vector2(-30.0, y0)
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", y0 - 22.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tw.chain().tween_callback(func() -> void:
		lbl.queue_free()
		_float_slot = maxi(0, _float_slot - 1))

func _spawn_damage_number(amount: int) -> void:
	float_text(str(amount), Color(1.0, 0.85, 0.2), 20)

# Quick red flash on the sprite (independent of the unit's acted/dead tint)
func _flash_hit() -> void:
	if not _body:
		return
	_body.modulate = Color(1.8, 0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(_body, "modulate", Color(1.0, 1.0, 1.0), 0.25)

# Floating status/ability word (e.g. "STUNNED!", "DASH!", "+35")
func show_status_popup(text: String, color: Color) -> void:
	float_text(text, color, 15)

func get_ability() -> Dictionary:
	return GameManager.UNIT_TYPES[unit_type].get("ability", {})

func _refresh_hp_bar() -> void:
	var ratio: float = float(hp) / float(max_hp)
	# Width = current bar background width (boss vs normal handled at build time)
	var full_w: float = 64.0 if _is_boss() else 52.0
	_hp_bar.size.x = full_w * ratio
	# Green → yellow → red as HP drops
	_hp_bar.color = Color(min(1.0, 2.0 * (1.0 - ratio)), min(1.0, 2.0 * ratio), 0.05)

func _is_boss() -> bool:
	var udata: Dictionary = GameManager.UNIT_TYPES.get(unit_type, {})
	return bool(udata.get("is_boss", false))

func is_alive() -> bool:
	return hp > 0

# Emphasised combat tag (e.g. "CRIT", "FLANK+COVER") shown above the unit.
func show_combat_label(text: String, color: Color) -> void:
	float_text(text, color, 14, true)

func get_move_range() -> int:
	var udata: Dictionary = GameManager.UNIT_TYPES[unit_type]
	var v: int = udata["move_range"]
	for u in upgrades:
		if u == "swift":
			v += 1
	if enraged:
		v += int(udata.get("enrage_move_bonus", 0))
	if team == 0:
		v += GameManager.relic_move_bonus()
	return v

func get_attack_range() -> int:
	var udata: Dictionary = GameManager.UNIT_TYPES[unit_type]
	var v: int = udata["attack_range"]
	for u in upgrades:
		if u == "eagle_eye":
			v += 1
	if enraged:
		v += int(udata.get("enrage_range_bonus", 0))
	return mini(v, 4)

func get_damage() -> int:
	var udata: Dictionary = GameManager.UNIT_TYPES[unit_type]
	var v: int = udata["damage"]
	var berserker_stacks: int = 0
	for u in upgrades:
		if u == "sharpshooter":
			v += 5
		elif u == "berserker":
			berserker_stacks += 1
	if berserker_stacks > 0 and max_hp > 0:
		# +5 damage per stack per 25% HP missing (rounded down)
		var missing_q: int = int(floor(float(max_hp - hp) / float(max_hp) * 4.0))
		v += 5 * berserker_stacks * missing_q
	if enraged:
		v += int(udata.get("enrage_damage_bonus", 0))
	if team == 0:
		v += GameManager.relic_damage_bonus()
	return v

# Multiplier applied to damage this unit RECEIVES. Used by combat resolution
# to honour the Ironhide upgrade (–20% per stack, capped to 60% reduction).
func get_damage_taken_mult() -> float:
	var stacks: int = 0
	for u in upgrades:
		if u == "ironhide":
			stacks += 1
	return maxf(0.40, 1.0 - 0.20 * float(stacks))

# Bonus crit chance contributed by Lucky upgrades (+15% per stack).
func get_crit_chance_bonus() -> float:
	var stacks: int = 0
	for u in upgrades:
		if u == "lucky":
			stacks += 1
	return 0.15 * float(stacks)

# Short labels for upgrades (e.g. ["VET", "SS"]) for compact UI display
func upgrade_short_labels() -> Array[String]:
	var out: Array[String] = []
	for u in upgrades:
		match u:
			"veteran":      out.append("VET")
			"sharpshooter": out.append("SS")
			"swift":        out.append("SWF")
			"eagle_eye":    out.append("EYE")
			"ironhide":     out.append("IRN")
			"lucky":        out.append("LCK")
			"berserker":    out.append("BSK")
	return out
