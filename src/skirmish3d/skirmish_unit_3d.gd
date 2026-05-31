class_name SkirmishUnit3D
extends CharacterBody3D

signal died(unit)

const WORLD_SCALE: float = 0.06

class Soldier:
	var mesh: MeshInstance3D
	var active: bool = true

# ---------------------------------------------------------------------------
# Per-type data (copied from real-time skirmish baseline and simplified)
# ---------------------------------------------------------------------------
var unit_type: String = "soldier"
var team: int = 0   # 0 = player, 1 = enemy
var unit_name: String = "Soldier"

var hp_per_soldier: int = 15
var soldier_count: int = 9
var max_hp: int = 135
var hp: int = 135

var damage_per_attack: int = 8
var attack_cooldown: float = 1.1
var attack_range_px: float = 60.0
var move_speed_px: float = 60.0
var move_speed_world: float = 60.0 * WORLD_SCALE
var is_ranged: bool = false
var attack_range_world: float = 60.0 * WORLD_SCALE

var radius: float = 32.0

# ---------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------
enum Order { IDLE, MOVE, ATTACK }
var order: int = Order.IDLE
var move_target: Vector3 = Vector3.ZERO
var attack_target: CharacterBody3D = null

var _cooldown: float = 0.0
var _selected: bool = false
var engage_radius_world: float = 100.0 * WORLD_SCALE

var _body: MeshInstance3D
var _select_ring: MeshInstance3D
var _hover_ring: MeshInstance3D
var _hp_bg: MeshInstance3D
var _hp_fill: MeshInstance3D
var _soldiers: Array[Soldier] = []

const HIT_FLASH_TIME: float = 0.24

func setup(type: String, p_team: int, world_pos: Vector3, stats: Dictionary) -> void:
	unit_type      = type
	team           = p_team
	global_position = world_pos
	unit_name      = String(stats.get("name", type.capitalize()))

	soldier_count  = int(stats.get("soldier_count", 9))
	hp_per_soldier = int(stats.get("hp_per_soldier", 15))
	max_hp         = soldier_count * hp_per_soldier
	hp             = max_hp

	damage_per_attack = int(stats.get("damage_per_attack", 8))
	attack_cooldown   = float(stats.get("attack_cooldown", 1.1))
	attack_range_px   = float(stats.get("attack_range_px", 60.0))
	move_speed_px     = float(stats.get("move_speed_px", 60.0))
	attack_range_world = attack_range_px * WORLD_SCALE
	move_speed_world  = move_speed_px * WORLD_SCALE
	is_ranged         = attack_range_px > 80.0

	radius = (18.0 + sqrt(float(soldier_count)) * 7.0) * WORLD_SCALE
	engage_radius_world = (attack_range_px + 40.0) * WORLD_SCALE
	_build_visuals()

func _solid_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

var team_color: Color:
	get: return Color(0.30, 0.53, 1.0) if team == 0 else Color(0.95, 0.28, 0.28)

# Build a small low-poly humanoid figure rooted at `root` (its torso), with a
# head, two legs and a class weapon. Used both for the regiment's lead figure
# and (smaller) for the squad markers.
func _build_figure(root: MeshInstance3D, scale_mul: float, with_weapon: bool) -> void:
	var torso := BoxMesh.new()
	torso.size = Vector3(0.62, 0.74, 0.36) * scale_mul
	root.mesh = torso
	root.material_override = _solid_mat(team_color)

	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.24 * scale_mul
	hs.height = 0.48 * scale_mul
	head.mesh = hs
	head.position = Vector3(0.0, 0.6 * scale_mul, 0.0)
	head.material_override = _solid_mat(Color(0.87, 0.72, 0.55))
	root.add_child(head)

	for lx: float in [-0.16, 0.16]:
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.2, 0.62, 0.28) * scale_mul
		leg.mesh = lb
		leg.position = Vector3(lx * scale_mul, -0.66 * scale_mul, 0.0)
		leg.material_override = _solid_mat(team_color.darkened(0.35))
		root.add_child(leg)

	if with_weapon:
		var wpn := MeshInstance3D.new()
		if is_ranged:
			var bow := TorusMesh.new()
			bow.inner_radius = 0.20 * scale_mul
			bow.outer_radius = 0.30 * scale_mul
			wpn.mesh = bow
			wpn.position = Vector3(0.42 * scale_mul, 0.18 * scale_mul, 0.0)
			wpn.material_override = _solid_mat(Color(0.55, 0.40, 0.22))
		else:
			var shaft := BoxMesh.new()
			shaft.size = Vector3(0.07, 1.35, 0.07) * scale_mul
			wpn.mesh = shaft
			wpn.position = Vector3(0.42 * scale_mul, 0.30 * scale_mul, 0.0)
			wpn.rotation_degrees = Vector3(0.0, 0.0, 12.0)
			wpn.material_override = _solid_mat(Color(0.72, 0.74, 0.80))
		root.add_child(wpn)

# Optional external 3D models. These files are NOT committed (gitignored —
# see assets/models/README.md). If present they're used for the regiment's
# lead figure; otherwise we fall back to the procedural low-poly figure so the
# mode always works.
const MODEL_DIR: String = "res://assets/models/"
const MODEL_FILES: Dictionary = {
	"soldier": "infantry.glb",
	"archer":  "archer.glb",
	"scout":   "cavalry.glb",
	"healer":  "spearman.glb",
}

func _try_load_model(scale_mul: float) -> Node3D:
	var fname: String = MODEL_FILES.get(unit_type, "")
	if fname == "":
		return null
	var path := MODEL_DIR + fname
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	inst.scale = Vector3.ONE * scale_mul
	return inst

func _build_visuals() -> void:
	# Body root. _body is the torso (hit-flash target) for the procedural figure;
	# with an external model it just hosts the model + a team-coloured base.
	_body = MeshInstance3D.new()
	_body.position = Vector3(0.0, 0.95, 0.0)
	add_child(_body)

	var model := _try_load_model(1.0)
	if model != null:
		_body.add_child(model)
		# Face inward and add a team-coloured base disc so sides read clearly
		_body.rotation_degrees = Vector3(0.0, 90.0 if team == 0 else -90.0, 0.0)
		var base := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.08
		base.mesh = disc
		base.position = Vector3(0.0, -0.9, 0.0)
		base.material_override = _solid_mat(team_color)
		_body.add_child(base)
	else:
		_build_figure(_body, 1.0, true)

	# Selection rings (top-down flat quads would be better, but cylinders keep
	# this implementation stable across Godot versions.
	_select_ring = MeshInstance3D.new()
	var sr := CylinderMesh.new()
	sr.top_radius = radius + 0.16
	sr.bottom_radius = radius + 0.16
	sr.height = 0.04
	_select_ring.mesh = sr
	_select_ring.position = Vector3(0.0, 0.72, 0.0)
	var sr_mat := StandardMaterial3D.new()
	sr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sr_mat.albedo_color = Color(1.0, 1.0, 0.35, 0.70)
	_select_ring.material_override = sr_mat
	_select_ring.visible = false
	add_child(_select_ring)

	_hover_ring = MeshInstance3D.new()
	var hr := CylinderMesh.new()
	hr.top_radius = radius + 0.10
	hr.bottom_radius = radius + 0.10
	hr.height = 0.03
	_hover_ring.mesh = hr
	_hover_ring.position = Vector3(0.0, 0.73, 0.0)
	var hr_mat := StandardMaterial3D.new()
	hr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hr_mat.albedo_color = Color(0.65, 0.88, 1.0, 0.55)
	_hover_ring.material_override = hr_mat
	_hover_ring.visible = false
	add_child(_hover_ring)

	# Health bar: two skinny boxes over the unit.
	_hp_bg = MeshInstance3D.new()
	var bg := BoxMesh.new()
	bg.size = Vector3(1.45, 0.12, 0.12)
	_hp_bg.mesh = bg
	_hp_bg.position = Vector3(0.0, 1.02, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.12, 0.12, 0.12)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_bg.material_override = bg_mat
	add_child(_hp_bg)

	_hp_fill = MeshInstance3D.new()
	var fg := BoxMesh.new()
	fg.size = Vector3(1.45, 0.12, 0.12)
	_hp_fill.mesh = fg
	_hp_fill.position = Vector3(0.0, 1.02, 0.0)
	_refresh_hp_bar()
	var fg_mat := StandardMaterial3D.new()
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill.material_override = fg_mat
	add_child(_hp_fill)

	# Squad markers — tiny low-poly figures arranged in a formation grid around
	# the lead figure, so losses are visible as troopers vanish.
	var cols: int = max(1, int(ceil(sqrt(float(soldier_count)))))
	var spacing: float = 0.62
	for i in range(soldier_count):
		var s := Soldier.new()
		var col: int = i % cols
		var row: int = i / cols
		var ox := (float(col) - float(cols - 1) * 0.5) * spacing
		var oz := (float(row) - float(cols - 1) * 0.5) * spacing * 0.85 + 0.9
		s.mesh = MeshInstance3D.new()
		_build_figure(s.mesh, 0.42, false)   # small, no weapon
		s.mesh.position = Vector3(ox, 0.32, oz)
		add_child(s.mesh)
		_soldiers.append(s)

func _refresh_hp_bar() -> void:
	if _hp_fill == null:
		return
	var frac: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	_hp_fill.position.x = (frac - 1.0) * 0.725
	_hp_fill.scale.x = frac
	var m: StandardMaterial3D = _hp_fill.material_override
	if m != null:
		if frac > 0.6:
			m.albedo_color = Color(0.30, 0.85, 0.30)
		elif frac > 0.3:
			m.albedo_color = Color(0.95, 0.80, 0.25)
		else:
			m.albedo_color = Color(0.95, 0.30, 0.25)

func set_selected(v: bool) -> void:
	_selected = v
	_select_ring.visible = v

func is_selected() -> bool:
	return _selected

func set_hovered(v: bool) -> void:
	_hover_ring.visible = v

func order_move(target: Vector3) -> void:
	order = Order.MOVE
	move_target = target
	attack_target = null

func order_attack(target: CharacterBody3D) -> void:
	order = Order.ATTACK
	attack_target = target

func clear_order() -> void:
	order = Order.IDLE
	attack_target = null

func is_alive() -> bool:
	return hp > 0

func alive_soldier_count() -> int:
	var n := 0
	for s: Soldier in _soldiers:
		if s.active:
			n += 1
	return n

func _expected_alive_count() -> int:
	return int(ceil(float(hp) / float(hp_per_soldier)))

func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = max(0, hp - amount)
	_refresh_hp_bar()
	_flash_hit()
	var target_alive := _expected_alive_count()
	while alive_soldier_count() > target_alive:
		for i in range(_soldiers.size() - 1, -1, -1):
			var s: Soldier = _soldiers[i]
			if s.active:
				_kill_soldier(i)
				break
	if hp <= 0:
		emit_signal("died", self)

func _kill_soldier(idx: int) -> void:
	if idx < 0 or idx >= _soldiers.size():
		return
	var s: Soldier = _soldiers[idx]
	if not s.active:
		return
	s.active = false
	if s.mesh:
		s.mesh.visible = false

func _flash_hit() -> void:
	if _body == null:
		return
	var mat := _body.material_override as StandardMaterial3D
	if mat == null:
		return
	var old := mat.albedo_color
	mat.albedo_color = Color(1.8, 0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", old, HIT_FLASH_TIME)

func tick(delta: float, neighbours: Array) -> Dictionary:
	var fired: Dictionary = {"fired": false}
	if not is_alive():
		return fired

	if _cooldown > 0.0:
		_cooldown = max(0.0, _cooldown - delta)

	# Keep alive orders in sync with battlefield state.
	if order == Order.ATTACK and (attack_target == null or not attack_target.is_alive()):
		clear_order()
	if order == Order.MOVE and global_position.distance_to(move_target) <= 0.35:
		order = Order.IDLE

	# Hold-ground auto-stance.
	if order == Order.IDLE:
		attack_target = _find_nearest_enemy_in_radius(neighbours, engage_radius_world)

	var move_intent := Vector3.ZERO
	var want_move := false
	match order:
		Order.MOVE:
			move_intent = (move_target - global_position)
			move_intent.y = 0.0
			want_move = true
		Order.ATTACK:
			if attack_target != null and attack_target.is_alive():
				var to_t := attack_target.global_position - global_position
				to_t.y = 0.0
				var desired_gap: float = attack_range_world + attack_target.radius
				if to_t.length() > desired_gap:
					move_intent = to_t
					want_move = true
		Order.IDLE:
			pass

	if want_move:
		var step: Vector3 = move_intent.normalized() * move_speed_world * delta
		if order == Order.MOVE and step.length() > move_intent.length():
			step = move_intent
		global_position += step

	# Soft unit separation (2D, x/z only)
	for other: CharacterBody3D in neighbours:
		if other == self or not other.is_alive():
			continue
		var diff := global_position - other.global_position
		diff.y = 0.0
		var min_dist: float = radius * 1.12 + other.radius * 1.12
		var d: float = diff.length()
		if d > 0.001 and d < min_dist:
			var push := (min_dist - d) * 0.5
			global_position += diff.normalized() * push * min(1.0, delta * 8.0)

	if attack_target != null and attack_target.is_alive():
		var dist: float = global_position.distance_to(attack_target.global_position)
		var target_gap: float = attack_range_world + attack_target.radius
		if dist <= target_gap and _cooldown <= 0.0:
			_cooldown = attack_cooldown
			var scaled: int = max(1, int(round(
				damage_per_attack * (float(alive_soldier_count()) / float(soldier_count))
			)))
			attack_target.take_damage(scaled)
			_play_attack_animation()
			fired = {"fired": true, "target": attack_target, "ranged": is_ranged}
	return fired

func _play_attack_animation() -> void:
	if _body == null:
		return
	var tw := create_tween()
	tw.tween_property(_body, "position:y", 0.45, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _find_nearest_enemy_in_radius(neighbours: Array, radius_world: float) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d: float = radius_world
	for other: CharacterBody3D in neighbours:
		if other == self or not other.is_alive() or other.team == team:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_d:
			best = other
			best_d = d
	return best
