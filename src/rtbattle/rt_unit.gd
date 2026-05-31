class_name RTUnit
extends Node2D

# A "regiment" of soldiers for the real-time skirmish mode. Each regiment is
# one logical unit that the player commands; visually it's N small sprites
# arranged loosely around a centre point. As the regiment loses HP, soldier
# sprites fall and fade individually (Total War style) so morale and strength
# are visible at a glance.
#
# This class is completely independent from the turn-based `Unit` class — it
# does not depend on a grid, does not call into GameManager.UNIT_TYPES at
# runtime (the rtbattle scene passes a stats dict in), and its visuals are
# self-contained.

signal died(unit: RTUnit)

# ---------------------------------------------------------------------------
# Per-soldier visual record
# ---------------------------------------------------------------------------
class Soldier:
	var sprite: Sprite2D
	var offset: Vector2     # resting offset from the regiment centre
	var alive: bool = true

# ---------------------------------------------------------------------------
# Configuration (set via setup())
# ---------------------------------------------------------------------------
var unit_type: String = "soldier"
var team: int = 0                       # 0 = player (blue), 1 = enemy (red)
var unit_name: String = "Soldier"

var hp_per_soldier: int = 15
var soldier_count: int = 9              # max soldier sprites at full HP
var max_hp: int = 135                   # soldier_count * hp_per_soldier
var hp: int = 135

var damage_per_attack: int = 8          # damage one tick of combat deals
var attack_cooldown: float = 1.1        # seconds between attacks
var attack_range_px: float = 60.0       # melee by default
var move_speed_px: float = 60.0         # px per second
var is_ranged: bool = false             # set automatically when range > 80px

# Collision radius — derived from soldier_count so bigger regiments take up
# more ground. Used both for movement collision and combat range checks.
var radius: float = 40.0

# ---------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------
enum Order { IDLE, MOVE, ATTACK }
var order: int = Order.IDLE
var move_target: Vector2 = Vector2.ZERO
var attack_target: RTUnit = null

var _cooldown: float = 0.0
var _soldiers: Array = []               # Array[Soldier]
var _ring: ColorRect                    # selection indicator (initially hidden)
var _selected: bool = false

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------
func setup(type: String, p_team: int, world_pos: Vector2, stats: Dictionary) -> void:
	unit_type        = type
	team             = p_team
	position         = world_pos
	unit_name        = String(stats.get("name", type.capitalize()))
	soldier_count    = int(stats.get("soldier_count", 9))
	hp_per_soldier   = int(stats.get("hp_per_soldier", 15))
	max_hp           = soldier_count * hp_per_soldier
	hp               = max_hp
	damage_per_attack = int(stats.get("damage_per_attack", 8))
	attack_cooldown   = float(stats.get("attack_cooldown", 1.1))
	attack_range_px   = float(stats.get("attack_range_px", 60.0))
	move_speed_px     = float(stats.get("move_speed_px", 60.0))
	is_ranged         = attack_range_px > 80.0
	# Radius scales with soldier count so a 9-man block is wider than a 5-man.
	radius            = 18.0 + sqrt(float(soldier_count)) * 7.0
	_build_visuals(stats)

func _build_visuals(stats: Dictionary) -> void:
	# Selection ring — a hollow rounded rect drawn under the regiment. We do
	# this with a centred ColorRect and a StyleBoxFlat-equivalent border via
	# a second inner ColorRect; cheap and avoids needing _draw().
	_ring                = ColorRect.new()
	_ring.size           = Vector2(radius * 2.0 + 8.0, radius * 2.0 + 8.0)
	_ring.position       = Vector2(-(radius + 4.0), -(radius + 4.0))
	_ring.color          = Color(1.0, 1.0, 0.4, 0.18)
	_ring.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_ring.visible        = false
	add_child(_ring)

	# Team-coloured floor disc — always visible so the player can see which
	# regiment is whose at a glance. Faint so it doesn't dominate.
	var disc := ColorRect.new()
	disc.size            = Vector2(radius * 2.0, radius * 2.0)
	disc.position        = Vector2(-radius, -radius)
	disc.color           = (Color(0.20, 0.45, 0.95, 0.22) if team == 0
			else Color(0.95, 0.25, 0.25, 0.22))
	disc.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	add_child(disc)

	# Build soldier sprites in a loose grid around the centre.
	var sprite_key: String = String(stats.get("sprite_key", unit_type))
	var team_name: String  = "player" if team == 0 else "enemy"
	var tex: Texture2D     = load("res://assets/units/%s_%s.png" % [sprite_key, team_name])

	var cols: int = max(1, int(ceil(sqrt(float(soldier_count)))))
	var spacing: float = (radius * 1.6) / float(cols)
	for i in range(soldier_count):
		var s := Soldier.new()
		var col: int = i % cols
		var row: int = i / cols
		# Centre the formation around (0,0). Add a small per-soldier jitter
		# so the regiment looks like a crowd rather than a grid.
		var seed_v := Vector2(
			float(i) * 12.9898,
			float(i) * 78.233
		)
		var jitter := Vector2(
			fposmod(sin(seed_v.x) * 43758.5453, 1.0) - 0.5,
			fposmod(sin(seed_v.y) * 43758.5453, 1.0) - 0.5
		) * (spacing * 0.4)
		var ox: float = (float(col) - float(cols - 1) * 0.5) * spacing + jitter.x
		var oy: float = (float(row) - float(cols - 1) * 0.5) * spacing + jitter.y
		s.offset       = Vector2(ox, oy)
		s.sprite       = Sprite2D.new()
		s.sprite.texture        = tex
		s.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.sprite.scale          = Vector2(0.9, 0.9)
		s.sprite.position       = s.offset
		add_child(s.sprite)
		_soldiers.append(s)

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
func set_selected(v: bool) -> void:
	_selected = v
	if _ring:
		_ring.visible = v

func is_selected() -> bool:
	return _selected

# ---------------------------------------------------------------------------
# Orders
# ---------------------------------------------------------------------------
func order_move(target: Vector2) -> void:
	order          = Order.MOVE
	move_target    = target
	attack_target  = null

func order_attack(target: RTUnit) -> void:
	order         = Order.ATTACK
	attack_target = target

func clear_order() -> void:
	order         = Order.IDLE
	attack_target = null

# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------
func is_alive() -> bool:
	return hp > 0

func alive_soldier_count() -> int:
	var n := 0
	for s: Soldier in _soldiers:
		if s.alive:
			n += 1
	return n

# How many soldier sprites should currently be alive given the remaining HP.
func _expected_alive_count() -> int:
	return int(ceil(float(hp) / float(hp_per_soldier)))

func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = max(0, hp - amount)
	_spawn_damage_number(amount)
	# Cull soldier sprites down to the expected count so the regiment visibly
	# shrinks as it loses HP — the Total War effect.
	var target_alive := _expected_alive_count()
	while alive_soldier_count() > target_alive:
		# Drop the rear-most still-alive soldier (largest offset.y)
		var victim: Soldier = null
		for s: Soldier in _soldiers:
			if s.alive and (victim == null or s.offset.y > victim.offset.y):
				victim = s
		if victim == null:
			break
		_kill_soldier(victim)
	if hp <= 0:
		emit_signal("died", self)

func _kill_soldier(s: Soldier) -> void:
	s.alive = false
	if s.sprite == null:
		return
	var spr := s.sprite
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "rotation", deg_to_rad(80.0), 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position:y", spr.position.y + 14.0, 0.4) \
			.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(spr, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(spr.queue_free)

# ---------------------------------------------------------------------------
# Per-frame simulation (driven by the scene; respects pause via dt arg)
# ---------------------------------------------------------------------------
# Returns true if this unit fired an attack this tick — caller uses that to
# spawn a projectile/lunge visual at scene level.
func tick(delta: float, neighbours: Array) -> Dictionary:
	var fired: Dictionary = {"fired": false}
	if not is_alive():
		return fired

	if _cooldown > 0.0:
		_cooldown = max(0.0, _cooldown - delta)

	# 1. Resolve attack order — drop it if the target died.
	if order == Order.ATTACK and (attack_target == null or not attack_target.is_alive()):
		clear_order()

	# 2. Decide movement intent.
	var move_intent: Vector2 = Vector2.ZERO
	var want_move: bool = false
	match order:
		Order.MOVE:
			move_intent = move_target - position
			want_move = move_intent.length() > 4.0
		Order.ATTACK:
			# Close to within attack range, then stop and shoot.
			var to_t: Vector2 = attack_target.position - position
			var desired_gap: float = attack_range_px + attack_target.radius * 0.3
			if to_t.length() > desired_gap:
				move_intent = to_t
				want_move = true
			else:
				want_move = false
		Order.IDLE:
			want_move = false

	# 3. Apply movement (slow, total-war-pace; integrate against neighbours
	#    so units gently push apart instead of overlapping).
	if want_move:
		var step: Vector2 = move_intent.normalized() * move_speed_px * delta
		# Don't overshoot a move target
		if order == Order.MOVE and step.length() > move_intent.length():
			step = move_intent
		position += step
	# Soft separation from every other unit (run always, not just when moving)
	for other: RTUnit in neighbours:
		if other == self or not other.is_alive():
			continue
		var diff: Vector2 = position - other.position
		var min_dist: float = radius + other.radius
		var d: float = diff.length()
		if d < min_dist and d > 0.001:
			var push: float = (min_dist - d) * 0.5
			position += diff.normalized() * push * min(1.0, delta * 8.0)

	# 4. Try to fire if we have an attack target in range.
	if order == Order.ATTACK and attack_target != null and attack_target.is_alive():
		var dist: float = position.distance_to(attack_target.position)
		if dist <= attack_range_px + attack_target.radius and _cooldown <= 0.0:
			_cooldown = attack_cooldown
			# Damage scales with how many soldiers we still have — a battered
			# regiment hits weaker.
			var scaled: int = max(1, int(round(
				damage_per_attack
				* (float(alive_soldier_count()) / float(soldier_count))
			)))
			attack_target.take_damage(scaled)
			_play_attack_animation(attack_target)
			fired = {"fired": true, "target": attack_target, "ranged": is_ranged}

	return fired

# ---------------------------------------------------------------------------
# Visual animations
# ---------------------------------------------------------------------------
# Lunge two of the front-most alive soldiers a short distance toward the
# target, then back. Cheap and reads as "the regiment swung".
func _play_attack_animation(target: RTUnit) -> void:
	var dir: Vector2 = (target.position - position).normalized()
	var lunge: Vector2 = dir * 10.0
	var picked: int = 0
	# Sort by offset.y ascending = front-most first (relative to formation)
	var sorted: Array = _soldiers.duplicate()
	sorted.sort_custom(func(a, b): return a.offset.y < b.offset.y)
	for s: Soldier in sorted:
		if not s.alive or s.sprite == null:
			continue
		var tw := create_tween()
		tw.tween_property(s.sprite, "position", s.offset + lunge, 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s.sprite, "position", s.offset, 0.18) \
				.set_trans(Tween.TRANS_SINE)
		picked += 1
		if picked >= 2:
			break

func _spawn_damage_number(amount: int) -> void:
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.modulate = Color(1.0, 0.85, 0.20)
	lbl.position = Vector2(-10.0, -radius - 18.0)
	lbl.z_index  = 100
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 22.0, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tw.chain().tween_callback(lbl.queue_free)
