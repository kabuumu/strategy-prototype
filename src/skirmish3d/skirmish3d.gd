extends Node3D

const UITheme := preload("res://src/ui/ui_theme.gd")
const SkirmishUnit3D := preload("res://src/skirmish3d/skirmish_unit_3d.gd")
const Hex := preload("res://src/battle/hex.gd")

# Core 3D skirmish constants. These are intentionally independent from
# campaign data so this mode remains a self-contained training board.
const REGIMENT_TYPES: Dictionary = {
	"soldier": {
		"name": "Infantry",
		"sprite_key": "soldier",
		"soldier_count": 12,
		"hp_per_soldier": 18,
		"damage_per_attack": 9,
		"attack_cooldown": 1.0,
		"attack_range_px": 55.0,
		"move_speed_px": 58.0,
	},
	"archer": {
		"name": "Archers",
		"sprite_key": "archer",
		"soldier_count": 8,
		"hp_per_soldier": 12,
		"damage_per_attack": 10,
		"attack_cooldown": 1.4,
		"attack_range_px": 220.0,
		"move_speed_px": 64.0,
	},
	"scout": {
		"name": "Cavalry",
		"sprite_key": "scout",
		"soldier_count": 7,
		"hp_per_soldier": 14,
		"damage_per_attack": 11,
		"attack_cooldown": 0.9,
		"attack_range_px": 55.0,
		"move_speed_px": 105.0,
	},
	"healer": {
		"name": "Spearmen",
		"sprite_key": "healer",
		"soldier_count": 10,
		"hp_per_soldier": 16,
		"damage_per_attack": 10,
		"attack_cooldown": 1.2,
		"attack_range_px": 75.0,
		"move_speed_px": 54.0,
	},
	# Bosses (final-tier campaign battles) — oversized, hard-hitting regiments.
	"warlord": {
		"name": "Warlord's Guard", "sprite_key": "soldier",
		"soldier_count": 20, "hp_per_soldier": 22, "damage_per_attack": 14,
		"attack_cooldown": 1.0, "attack_range_px": 55.0, "move_speed_px": 60.0,
	},
	"pyromancer": {
		"name": "Pyromancers", "sprite_key": "archer",
		"soldier_count": 14, "hp_per_soldier": 16, "damage_per_attack": 16,
		"attack_cooldown": 1.3, "attack_range_px": 230.0, "move_speed_px": 56.0,
	},
	"juggernaut": {
		"name": "Juggernauts", "sprite_key": "healer",
		"soldier_count": 16, "hp_per_soldier": 30, "damage_per_attack": 18,
		"attack_cooldown": 1.3, "attack_range_px": 55.0, "move_speed_px": 44.0,
	},
	# Extra regiment types — mostly enemy variety per biome.
	"pikemen": {
		"name": "Pikemen", "sprite_key": "healer",
		"soldier_count": 12, "hp_per_soldier": 20, "damage_per_attack": 11,
		"attack_cooldown": 1.1, "attack_range_px": 78.0, "move_speed_px": 50.0,
	},
	"crossbow": {
		"name": "Crossbows", "sprite_key": "archer",
		"soldier_count": 8, "hp_per_soldier": 13, "damage_per_attack": 16,
		"attack_cooldown": 1.8, "attack_range_px": 200.0, "move_speed_px": 50.0,
	},
	"berserker": {
		"name": "Berserkers", "sprite_key": "soldier",
		"soldier_count": 10, "hp_per_soldier": 13, "damage_per_attack": 15,
		"attack_cooldown": 0.8, "attack_range_px": 52.0, "move_speed_px": 92.0,
	},
	"knight": {
		"name": "Knights", "sprite_key": "scout",
		"soldier_count": 7, "hp_per_soldier": 22, "damage_per_attack": 14,
		"attack_cooldown": 1.0, "attack_range_px": 55.0, "move_speed_px": 100.0,
	},
	# Extra boss
	"necromancer": {
		"name": "Necromancer's Host", "sprite_key": "healer",
		"soldier_count": 18, "hp_per_soldier": 20, "damage_per_attack": 13,
		"attack_cooldown": 1.1, "attack_range_px": 120.0, "move_speed_px": 52.0,
	},
	# Advanced campaign recruits (mirror GameManager.UNIT_TYPES knight/mage/guardian).
	"mage": {
		"name": "Battlemages", "sprite_key": "archer",
		"soldier_count": 10, "hp_per_soldier": 15, "damage_per_attack": 16,
		"attack_cooldown": 1.4, "attack_range_px": 210.0, "move_speed_px": 56.0,
	},
	"guardian": {
		"name": "Guardians", "sprite_key": "healer",
		"soldier_count": 14, "hp_per_soldier": 30, "damage_per_attack": 14,
		"attack_cooldown": 1.3, "attack_range_px": 55.0, "move_speed_px": 42.0,
	},
}

# Enemy regiment composition by biome (campaign 3D battles). Picks count by
# tier; the final tier prepends the run's boss.
const BIOME_ENEMY_POOL: Dictionary = {
	"Grassy Plains":   ["soldier", "archer"],
	"Deep Woods":      ["archer", "scout", "pikemen"],
	"Rocky Highlands": ["pikemen", "crossbow", "soldier"],
	"Volcanic Wastes": ["berserker", "soldier", "berserker"],
	"The Citadel":     ["knight", "crossbow", "pikemen", "necromancer"],
}

const FIELD_HALF_WIDTH: float = 36.0
const FIELD_HALF_DEPTH: float = 17.4
const CAMERA_Y: float = 24.0
const AI_RETARGET_PERIOD: float = 0.6
const DRAG_THRESHOLD: float = 7.0
const PICK_SCREEN_RADIUS: float = 17.0
const PICK_RAY_RADIUS_SCALE: float = 1.8
const TERRAIN_HEX_RADIUS: float = 2.3   # base size for the feature props (trees, rocks, hills)

# Continuous ground colouring: each feature type paints the surface around it.
# (Used by _ground_color_at — the ground is one blended mesh, never hex tiles.)
const GROUND_TYPE_COLOR: Dictionary = {
	"mountain": Color(0.20, 0.18, 0.16),
	"forest":   Color(0.10, 0.24, 0.12),
	"hill":     Color(0.32, 0.27, 0.16),
	"lava":     Color(0.48, 0.13, 0.05),
}
const GROUND_GRID_COLS: int = 80
const GROUND_GRID_ROWS: int = 50

var player_units: Array[SkirmishUnit3D] = []
var enemy_units: Array[SkirmishUnit3D] = []
var selected_units: Array[SkirmishUnit3D] = []
var hovered_unit: SkirmishUnit3D = null
var _ended: bool = false
var _campaign: bool = false   # launched from the campaign map (vs standalone)
var _formation: int = 0       # 0 = line, 1 = wedge (move-order arrangement)

# Capture points — hold ALL of them for CAPTURE_WIN_TIME to win by objective.
const CAPTURE_POINTS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0), Vector3(-15.0, 0.0, -7.0), Vector3(15.0, 0.0, 7.0),
]
const CAPTURE_RADIUS: float = 6.0
const CAPTURE_WIN_TIME: float = 12.0
var _cap_points: Array = []        # [{pos, owner, ring}]
var _cap_hold: float = 0.0         # seconds one side has held them all
var _forced_winner: int = -1       # set when a side wins by capture
# Deployment phase (campaign battles): reposition your regiments before the
# fight starts. Movement runs, combat/AI are frozen until you press Enter.
var _deploying: bool = false
const DEPLOY_X_MAX: float = -3.0   # player deploy zone is the left of this
var _paused: bool = true

var _drag_active: bool = false
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _drag_additive: bool = false

var _ai_retarget_timer: float = 0.0

var _waypoints: Array = []
var _biome: Dictionary = {}
# Terrain features placed at world positions on the continuous ground.
# Each: { "pos": Vector3, "type": String, "radius": float }
var _features: Array = []

var _camera: Camera3D
var _ground: MeshInstance3D
var _ground_body: StaticBody3D
var _terrain_node: Node3D

# Camera rig — focus point on the field + zoom; pan with WASD/arrows/edge,
# zoom with the mouse wheel.
const CAM_OFFSET: Vector3 = Vector3(0.0, 24.0, 34.0)
const CAM_PAN_SPEED: float = 38.0
const CAM_EDGE_MARGIN: float = 8.0
var _cam_focus: Vector3 = Vector3.ZERO
var _cam_zoom: float = 1.0   # 0.5 (close) .. 1.8 (far)
var _combat_sfx_cd: float = 0.0   # throttles the combat hit din

# Flying arrow (ranged) or impact puff (charge / arrow landing).
func _spawn_projectile(from: Vector3, to: Vector3, charge: bool) -> void:
	if charge or from.distance_to(to) < 0.05:
		_spawn_impact_puff(to)
		return
	var p := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 0.7)
	p.mesh = bm
	p.material_override = _make_mat(Color(0.92, 0.86, 0.5), true)
	add_child(p)
	p.global_position = from + Vector3(0.0, 0.6, 0.0)
	p.look_at(to + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	var tw := create_tween()
	tw.tween_property(p, "global_position", to + Vector3(0.0, 0.5, 0.0), 0.18)
	tw.tween_callback(func() -> void:
		_spawn_impact_puff(to)
		p.queue_free())

func _spawn_impact_puff(at: Vector3) -> void:
	var puff := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	puff.mesh = s
	puff.material_override = _make_mat(Color(1.0, 0.8, 0.4), true)
	add_child(puff)
	puff.global_position = at + Vector3(0.0, 0.5, 0.0)
	puff.scale = Vector3(0.3, 0.3, 0.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(puff, "scale", Vector3(1.4, 1.4, 1.4), 0.2)
	tw.tween_property(puff, "transparency", 1.0, 0.2)
	tw.chain().tween_callback(puff.queue_free)

var _ui: CanvasLayer
var _status_label: Label
var _selection_label: Label
var _command_label: Label
var _settings_overlay: Control = null
var _info_panel: Panel
var _info_label: Label
var _result_label: Label
var _restart_hint_label: Label
var _drag_box: ColorRect

func _ready() -> void:
	set_process_unhandled_input(true)
	_campaign = GameManager.pending_skirmish
	GameManager.pending_skirmish = false   # consume the flag
	_generate_terrain()
	_build_field()
	_build_ui()
	_spawn_armies()
	_set_paused(false)
	# Campaign battles open in a deployment phase: position your regiments first.
	if _campaign:
		_deploying = true
		if _command_label != null:
			_command_label.text = "DEPLOYMENT — right-click to position your regiments, then press ENTER to begin"
	_refresh_ui()

# Feature effect radii (gameplay) by type.
const FEATURE_RADIUS: Dictionary = {
	"mountain": 4.5, "forest": 5.0, "hill": 4.5, "lava": 4.0,
}

func _generate_terrain() -> void:
	_features.clear()
	var tier: int = clampi(GameManager.current_tier, 0, GameManager.MAP_TIERS - 1)
	_biome = GameManager.biome_for_tier(tier)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(tier * 127 + 31)
	var mtn: Vector2i = _biome.get("mtn", Vector2i(2, 3))

	var want: Dictionary = {
		"mountain": rng.randi_range(mtn.x, mtn.y) + 1,
		"forest":   int(_biome.get("forest", 3) * 1.4),
		"hill":     int(_biome.get("hill", 2) * 1.4),
		"lava":     int(_biome.get("lava", 0) * 1.4),
	}
	# Place features across the central band, clear of the army spawn flanks
	# (|x| > 26) and not overlapping each other.
	for type: String in want:
		var radius: float = FEATURE_RADIUS[type]
		var placed := 0
		var tries := 0
		while placed < int(want[type]) and tries < 60:
			tries += 1
			var x := rng.randf_range(-22.0, 22.0)
			var z := rng.randf_range(-FIELD_HALF_DEPTH + 2.0, FIELD_HALF_DEPTH - 2.0)
			var pos := Vector3(x, 0.0, z)
			var ok := true
			for f: Dictionary in _features:
				if pos.distance_to(f["pos"]) < (radius + float(f["radius"])) * 0.8:
					ok = false
					break
			if ok:
				_features.append({"pos": pos, "type": type, "radius": radius})
				placed += 1

func _build_field() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	# Lighting + ambient so the low-poly unit figures read as 3D (the figures
	# use shaded materials; the ground stays flat/unshaded).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -42.0, 0.0)
	sun.light_energy = 1.15
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46, 0.49, 0.58)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, CAMERA_Y, 34.0)
	_camera.look_at_from_position(_camera.position, Vector3.ZERO, Vector3.UP)
	_camera.current = true
	world.add_child(_camera)

	# One continuous ground mesh whose vertex colours follow the procedurally
	# generated terrain — forest/hill/lava/mountain zones bleed into the biome
	# base colour as soft regions, never hex tiles. Extends past the unit clamp
	# bounds so there's no visible edge.
	_ground = MeshInstance3D.new()
	_ground.mesh = _build_ground_mesh()
	_ground.position = Vector3(0.0, 0.0, 0.0)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground.material_override = gm
	world.add_child(_ground)
	_build_terrain_visuals(world)
	_build_capture_points(world)

	_ground_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FIELD_HALF_WIDTH * 2.0, 0.2, FIELD_HALF_DEPTH * 2.0)
	cs.shape = box
	_ground_body.add_child(cs)
	world.add_child(_ground_body)
	_ground_body.position = Vector3(0.0, 0.0, 0.0)

func _build_capture_points(world: Node3D) -> void:
	_cap_points.clear()
	for p: Vector3 in CAPTURE_POINTS:
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = CAPTURE_RADIUS
		cyl.bottom_radius = CAPTURE_RADIUS
		cyl.height = 0.06
		ring.mesh = cyl
		ring.position = p + Vector3(0.0, 0.05, 0.0)
		ring.material_override = _make_mat(Color(0.7, 0.7, 0.7, 0.35), true)
		world.add_child(ring)
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.12
		pm.bottom_radius = 0.12
		pm.height = 3.0
		pole.mesh = pm
		pole.position = p + Vector3(0.0, 1.5, 0.0)
		pole.material_override = _make_mat(Color(0.7, 0.7, 0.7), true)
		world.add_child(pole)
		_cap_points.append({"pos": p, "owner": -1, "ring": ring, "pole": pole})

func _capture_owner_color(owner: int) -> Color:
	match owner:
		0: return Color(0.30, 0.55, 1.0)
		1: return Color(0.95, 0.30, 0.30)
		_: return Color(0.7, 0.7, 0.7)

# Recompute each point's owner (whichever team has units in range, uncontested)
# and the all-points hold timer; returns a winning team or -1.
func _update_capture_points(delta: float) -> int:
	if _cap_points.is_empty():
		return -1
	var all_owner := -2   # -2 = uninitialised, -1 = mixed/neutral
	for cp: Dictionary in _cap_points:
		var p0 := 0
		var p1 := 0
		for u: SkirmishUnit3D in player_units:
			if u.is_alive() and u.global_position.distance_to(cp["pos"]) <= CAPTURE_RADIUS:
				p0 += 1
		for u: SkirmishUnit3D in enemy_units:
			if u.is_alive() and u.global_position.distance_to(cp["pos"]) <= CAPTURE_RADIUS:
				p1 += 1
		if p0 > 0 and p1 == 0:
			cp["owner"] = 0
		elif p1 > 0 and p0 == 0:
			cp["owner"] = 1
		# contested or empty → keep current owner
		var col := _capture_owner_color(cp["owner"])
		cp["ring"].material_override.albedo_color = Color(col.r, col.g, col.b, 0.35)
		cp["pole"].material_override.albedo_color = col
		if all_owner == -2:
			all_owner = cp["owner"]
		elif all_owner != cp["owner"]:
			all_owner = -1
	# All points held by one real team → tick the hold timer
	if all_owner >= 0:
		_cap_hold += delta
		if _cap_hold >= CAPTURE_WIN_TIME:
			return all_owner
	else:
		_cap_hold = max(0.0, _cap_hold - delta)
	return -1

func _build_terrain_visuals(world: Node3D) -> void:
	_terrain_node = Node3D.new()
	_terrain_node.name = "ProceduralTerrain"
	world.add_child(_terrain_node)

	# The ground is one continuous plane (built in _build_field). Here we just
	# drop terrain feature props at their world positions.
	for i in range(_features.size()):
		var f: Dictionary = _features[i]
		var pos: Vector3 = f["pos"]
		var seed: int = i * 1327 + 71
		match String(f["type"]):
			"mountain":
				_add_mountain_cluster(pos, seed)
			"forest":
				_add_forest_cluster(pos, seed)
			"hill":
				_add_hill(pos, seed)
			"lava":
				_add_lava_pool(pos)

# Colour of the ground at a world (x, z): the biome base, with each nearby
# feature blended in by proximity (1 at its centre, fading to 0 at its radius).
func _ground_color_at(x: float, z: float, base: Color) -> Color:
	var col := base
	for f: Dictionary in _features:
		var fp: Vector3 = f["pos"]
		var r: float = float(f["radius"])
		var d := Vector2(x - fp.x, z - fp.z).length()
		if d >= r * 1.1:
			continue
		var t := 1.0 - clampf(d / (r * 1.1), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)   # smoothstep falloff
		var tc: Color = GROUND_TYPE_COLOR.get(String(f["type"]), base)
		var strength := 0.95 if String(f["type"]) == "lava" else 0.78
		col = col.lerp(tc, t * strength)
	return col

# Subdivided flat plane (y = 0) carrying the blended terrain colours as vertex
# colours. Collision stays the separate box in _build_field.
func _build_ground_mesh() -> ArrayMesh:
	var w := FIELD_HALF_WIDTH * 2.0 + 24.0
	var d := FIELD_HALF_DEPTH * 2.0 + 24.0
	var base: Color = _biome.get("bg", Color(0.07, 0.10, 0.07)).lightened(0.06)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(GROUND_GRID_ROWS):
		var z0 := -d * 0.5 + d * float(j) / float(GROUND_GRID_ROWS)
		var z1 := -d * 0.5 + d * float(j + 1) / float(GROUND_GRID_ROWS)
		for i in range(GROUND_GRID_COLS):
			var x0 := -w * 0.5 + w * float(i) / float(GROUND_GRID_COLS)
			var x1 := -w * 0.5 + w * float(i + 1) / float(GROUND_GRID_COLS)
			_st_ground_vertex(st, x0, z0, base)
			_st_ground_vertex(st, x1, z0, base)
			_st_ground_vertex(st, x1, z1, base)
			_st_ground_vertex(st, x0, z0, base)
			_st_ground_vertex(st, x1, z1, base)
			_st_ground_vertex(st, x0, z1, base)
	return st.commit()

func _st_ground_vertex(st: SurfaceTool, x: float, z: float, base: Color) -> void:
	st.set_color(_ground_color_at(x, z, base))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(x, 0.0, z))

const LAVA_DPS: int = 6
const FOREST_DEF_MULT: float = 0.7
const FOREST_SPEED_MULT: float = 0.7
const HILL_ATK_MULT: float = 1.25
const MOUNTAIN_SPEED_MULT: float = 0.4

# Each tick, stamp terrain effects (cover / high-ground / rough / lava) onto
# every living unit based on the cell it's standing on.
func _apply_terrain(delta: float) -> void:
	for u: SkirmishUnit3D in _all_living_units():
		u.terrain_def_mult = 1.0
		u.terrain_atk_mult = 1.0
		u.terrain_speed_mult = 1.0
		var on_lava := false
		for f: Dictionary in _features:
			if u.global_position.distance_to(f["pos"]) > float(f["radius"]):
				continue
			match String(f["type"]):
				"forest":
					u.terrain_def_mult = FOREST_DEF_MULT
					u.terrain_speed_mult = FOREST_SPEED_MULT
				"hill":
					u.terrain_atk_mult = HILL_ATK_MULT
				"mountain":
					u.terrain_speed_mult = MOUNTAIN_SPEED_MULT
				"lava":
					on_lava = true
		if on_lava:
			u._lava_accum += delta
			if u._lava_accum >= 1.0:
				u._lava_accum -= 1.0
				u.take_damage(LAVA_DPS)
		else:
			u._lava_accum = 0.0

func _all_living_units() -> Array[SkirmishUnit3D]:
	var out: Array[SkirmishUnit3D] = []
	for u: SkirmishUnit3D in player_units:
		if u.is_alive(): out.append(u)
	for u: SkirmishUnit3D in enemy_units:
		if u.is_alive(): out.append(u)
	return out


func _make_mat(color: Color, unshaded: bool = false, emission: Color = Color(0.0, 0.0, 0.0, 0.0)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 0.55
	return mat

func _add_hex_patch(pos: Vector3, color: Color) -> void:
	var tile := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = TERRAIN_HEX_RADIUS
	mesh.bottom_radius = TERRAIN_HEX_RADIUS
	mesh.height = 0.08
	mesh.radial_segments = 6
	tile.mesh = mesh
	tile.position = pos
	tile.rotation_degrees.y = 30.0
	tile.material_override = _make_mat(color.lightened(0.02), false)
	_terrain_node.add_child(tile)

func _add_mountain_cluster(pos: Vector3, seed: int) -> void:
	for i in range(3):
		var rock := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.75 + float((seed + i * 17) % 30) * 0.01
		mesh.height = 1.9 + float((seed + i * 29) % 40) * 0.025
		mesh.radial_segments = 5
		rock.mesh = mesh
		var ox: float = float(((seed + i * 41) % 100) - 50) * 0.018
		var oz: float = float(((seed + i * 53) % 100) - 50) * 0.018
		rock.position = pos + Vector3(ox, mesh.height * 0.5 + 0.07, oz)
		rock.rotation_degrees.y = float((seed + i * 37) % 90)
		rock.material_override = _make_mat(Color(0.43, 0.39, 0.33), false)
		_terrain_node.add_child(rock)

func _add_forest_cluster(pos: Vector3, seed: int) -> void:
	for i in range(5):
		var ox: float = float(((seed + i * 31) % 100) - 50) * 0.025
		var oz: float = float(((seed + i * 47) % 100) - 50) * 0.025
		_add_tree(pos + Vector3(ox, 0.0, oz), seed + i * 11)

func _add_tree(pos: Vector3, seed: int) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.08
	trunk_mesh.bottom_radius = 0.11
	trunk_mesh.height = 0.55
	trunk_mesh.radial_segments = 6
	trunk.mesh = trunk_mesh
	trunk.position = pos + Vector3(0.0, 0.32, 0.0)
	trunk.material_override = _make_mat(Color(0.28, 0.18, 0.10), false)
	_terrain_node.add_child(trunk)

	var canopy := MeshInstance3D.new()
	var canopy_mesh := CylinderMesh.new()
	canopy_mesh.top_radius = 0.0
	canopy_mesh.bottom_radius = 0.42 + float(seed % 20) * 0.006
	canopy_mesh.height = 0.95
	canopy_mesh.radial_segments = 7
	canopy.mesh = canopy_mesh
	canopy.position = pos + Vector3(0.0, 0.98, 0.0)
	canopy.material_override = _make_mat(Color(0.16, 0.42, 0.18), false)
	_terrain_node.add_child(canopy)

func _add_hill(pos: Vector3, seed: int) -> void:
	var hill := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = TERRAIN_HEX_RADIUS * 0.34
	mesh.bottom_radius = TERRAIN_HEX_RADIUS * 0.78
	mesh.height = 0.65 + float(seed % 20) * 0.01
	mesh.radial_segments = 9
	hill.mesh = mesh
	hill.position = pos + Vector3(0.0, mesh.height * 0.5 + 0.04, 0.0)
	hill.material_override = _make_mat(Color(0.52, 0.43, 0.27), false)
	_terrain_node.add_child(hill)

func _add_lava_pool(pos: Vector3) -> void:
	var lava := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = TERRAIN_HEX_RADIUS * 0.48
	mesh.bottom_radius = TERRAIN_HEX_RADIUS * 0.48
	mesh.height = 0.1
	mesh.radial_segments = 12
	lava.mesh = mesh
	lava.position = pos + Vector3(0.0, 0.08, 0.0)
	lava.material_override = _make_mat(Color(0.95, 0.34, 0.08), true, Color(1.0, 0.42, 0.05, 1.0))
	_terrain_node.add_child(lava)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	var top := ColorRect.new()
	top.color = Color(0.06, 0.08, 0.14, 0.9)
	top.position = Vector2(0.0, 0.0)
	top.size = Vector2(1280.0, 72.0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(top)

	var title := Label.new()
	title.text = "SKIRMISH 3D — Total-War style"
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(0.92, 0.85, 0.52)
	title.position = Vector2(20.0, 8.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(title)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.position = Vector2(20.0, 32.0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_status_label)

	_command_label = Label.new()
	_command_label.text = "Select regiments, then right-click ground or enemies. Terrain matters."
	_command_label.add_theme_font_size_override("font_size", 13)
	_command_label.modulate = Color(0.74, 0.78, 0.84)
	_command_label.position = Vector2(326.0, 39.0)
	_command_label.size = Vector2(510.0, 22.0)
	_command_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_command_label)

	var hint := Label.new()
	hint.text = "Drag-box select · Shift add · R-click move/attack · WASD/edge pan · wheel zoom · G shield-wall · V volley · F formation · SPACE pause"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.56, 0.56, 0.66)
	hint.position = Vector2(326.0, 16.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(hint)

	_ui.add_child(UITheme.button("Pause", Vector2(884.0, 14.0), Vector2(104.0, 40.0), Color(0.18, 0.26, 0.36), _on_pause_button, 15))
	_ui.add_child(UITheme.button("Restart", Vector2(1000.0, 14.0), Vector2(104.0, 40.0), Color(0.28, 0.22, 0.34), _on_restart_button, 15))
	_ui.add_child(UITheme.button("Menu", Vector2(1116.0, 14.0), Vector2(104.0, 40.0), Color(0.30, 0.20, 0.20), _on_menu_button, 15))

	_selection_label = Label.new()
	_selection_label.add_theme_font_size_override("font_size", 15)
	_selection_label.modulate = Color(0.85, 0.90, 0.95)
	_selection_label.position = Vector2(20.0, 676.0)
	_selection_label.size = Vector2(1240.0, 30.0)
	_selection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_selection_label)

	# Hover info card — shows stats for the unit under the cursor (any team).
	_info_panel = Panel.new()
	_info_panel.size = Vector2(280.0, 96.0)
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.visible = false
	var ips := StyleBoxFlat.new()
	ips.bg_color = Color(0.06, 0.07, 0.10, 0.92)
	for side in ["left", "right", "top", "bottom"]:
		ips.set("border_width_" + side, 2)
	ips.border_color = Color(0.5, 0.55, 0.65)
	for c in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		ips.set(c, 6)
	_info_panel.add_theme_stylebox_override("panel", ips)
	_ui.add_child(_info_panel)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.position = Vector2(10.0, 8.0)
	_info_label.size = Vector2(260.0, 80.0)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(_info_label)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 44)
	_result_label.position = Vector2(420.0, 290.0)
	_result_label.size = Vector2(440.0, 90.0)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible = false
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_result_label)

	_restart_hint_label = Label.new()
	_restart_hint_label.add_theme_font_size_override("font_size", 18)
	_restart_hint_label.modulate = Color(0.8, 0.8, 0.88)
	_restart_hint_label.position = Vector2(420.0, 372.0)
	_restart_hint_label.size = Vector2(440.0, 30.0)
	_restart_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart_hint_label.text = "Press R to refight  ·  Esc for title"
	_restart_hint_label.visible = false
	_restart_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_restart_hint_label)

	_drag_box = ColorRect.new()
	_drag_box.color = Color(0.9, 0.95, 0.55, 0.2)
	_drag_box.visible = false
	_drag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_box.z_index = 50
	_ui.add_child(_drag_box)

func _on_pause_button() -> void:
	if not _ended:
		_set_paused(not _paused)

func _on_restart_button() -> void:
	get_tree().reload_current_scene()

func _on_menu_button() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _toggle_settings_menu() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	var note := "Leaving abandons this battle. Continue resumes from the map." if _campaign else ""
	_settings_overlay = UITheme.pause_menu(_toggle_settings_menu, _on_menu_button, note)
	_ui.add_child(_settings_overlay)

func _spawn_armies() -> void:
	if _campaign:
		_spawn_campaign_armies()
		return
	var lines_player: Array = [
		{"type": "soldier", "x": -22.0, "z": -12.0},
		{"type": "archer", "x": -23.5, "z": -4.0},
		{"type": "scout", "x": -22.0, "z": 4.0},
		{"type": "healer", "x": -23.5, "z": 12.0},
	]
	var lines_enemy: Array = [
		{"type": "soldier", "x": 22.0, "z": -12.0},
		{"type": "archer", "x": 23.5, "z": -4.0},
		{"type": "scout", "x": 22.0, "z": 4.0},
		{"type": "healer", "x": 23.5, "z": 12.0},
	]
	for i in range(lines_player.size()):
		var entry: Dictionary = lines_player[i]
		var u := _spawn_regiment(String(entry["type"]), 0, Vector3(entry["x"], 0.0, entry["z"]))
		player_units.append(u)

	for i in range(lines_enemy.size()):
		var entry: Dictionary = lines_enemy[i]
		var u := _spawn_regiment(String(entry["type"]), 1, Vector3(entry["x"], 0.0, entry["z"]))
		enemy_units.append(u)

# Build both armies from campaign state: your roster vs the tier's enemy roster.
func _spawn_campaign_armies() -> void:
	var roster := GameManager.player_roster
	var pz := _line_positions(roster.size())
	for i in range(roster.size()):
		var rtype: String = roster[i].get("type", "soldier")
		var u := _spawn_regiment(rtype, 0, Vector3(-22.0, 0.0, pz[i]))
		u.roster_index = i
		u.apply_upgrades(roster[i].get("upgrades", []))
		player_units.append(u)

	var elist := _enemy_composition(GameManager.pending_battle_tier, GameManager.pending_battle_elite)
	var ez := _line_positions(elist.size())
	var hp_mult := GameManager.get_hp_multiplier(
		GameManager.pending_battle_tier, GameManager.pending_battle_elite)
	for i in range(elist.size()):
		var u := _spawn_regiment(String(elist[i]), 1, Vector3(22.0, 0.0, ez[i]))
		# Scale enemy strength with tier (more men + hp)
		u.max_hp = int(u.max_hp * hp_mult)
		u.hp = u.max_hp
		enemy_units.append(u)

# Biome-flavoured enemy regiment list for a campaign battle. Final tier leads
# with the run's boss.
func _enemy_composition(tier: int, elite: bool) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = tier * 911 + (37 if elite else 13)
	var biome_name: String = String(_biome.get("name", "Grassy Plains"))
	var pool: Array = BIOME_ENEMY_POOL.get(biome_name, ["soldier", "archer"])
	var out: Array[String] = []
	if GameManager.is_final_battle(tier, elite):
		out.append(GameManager.boss_id)   # the run's chosen boss leads
	var count: int = clampi(2 + tier + (1 if elite else 0), 2, 6)
	for _i in range(count):
		out.append(String(pool[rng.randi() % pool.size()]))
	return out

# Evenly spread N regiments across the field depth.
func _line_positions(n: int) -> Array[float]:
	var out: Array[float] = []
	if n <= 0:
		return out
	var span := FIELD_HALF_DEPTH * 1.7
	for i in range(n):
		out.append(-span * 0.5 + span * (float(i) + 0.5) / float(n))
	return out

func _spawn_regiment(type: String, team: int, pos: Vector3) -> SkirmishUnit3D:
	var u := SkirmishUnit3D.new()
	add_child(u)
	var stats: Dictionary = REGIMENT_TYPES.get(type, REGIMENT_TYPES["soldier"])
	u.setup(type, team, pos, stats)
	u.died.connect(_on_unit_died)
	return u

func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	# Keyboard / edge-scroll pan (scaled by zoom so it feels consistent)
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  pan.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): pan.x += 1.0
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport().get_visible_rect().size
	if mp.x < CAM_EDGE_MARGIN: pan.x -= 1.0
	elif mp.x > vs.x - CAM_EDGE_MARGIN: pan.x += 1.0
	if mp.y < CAM_EDGE_MARGIN: pan.y -= 1.0
	elif mp.y > vs.y - CAM_EDGE_MARGIN: pan.y += 1.0
	if pan != Vector2.ZERO:
		var step := CAM_PAN_SPEED * _cam_zoom * delta
		_cam_focus.x = clamp(_cam_focus.x + pan.x * step, -FIELD_HALF_WIDTH, FIELD_HALF_WIDTH)
		_cam_focus.z = clamp(_cam_focus.z + pan.y * step, -FIELD_HALF_DEPTH, FIELD_HALF_DEPTH)
	_camera.position = _cam_focus + CAM_OFFSET * _cam_zoom
	_camera.look_at(_cam_focus, Vector3.UP)

func _process(delta: float) -> void:
	_update_camera(delta)   # camera is always controllable, even while paused
	if _ended:
		_age_waypoints(delta)
		return
	if _paused:
		_update_hover()
		return
	if _deploying:
		_deploy_tick(delta)
		return

	var all_units: Array[SkirmishUnit3D] = []
	all_units.append_array(player_units)
	all_units.append_array(enemy_units)
	_apply_terrain(delta)   # cover / high-ground / rough / lava onto each unit
	_ai_tick(delta)
	if _combat_sfx_cd > 0.0:
		_combat_sfx_cd -= delta
	var any_hit := false
	for u: SkirmishUnit3D in all_units:
		if u.is_alive():
			var fired: Dictionary = u.tick(delta, all_units)
			if fired.get("fired", false):
				any_hit = true
				if fired.get("ranged", false):
					_spawn_projectile(fired["from"], fired["target"].global_position, false)
				elif fired.get("charge", false):
					_spawn_projectile(fired["from"], fired["target"].global_position, true)
	# Throttled combat din so many simultaneous hits don't machine-gun the SFX
	if any_hit and _combat_sfx_cd <= 0.0:
		_combat_sfx_cd = 0.18
		Sfx.play("hit", -10.0)
	# keep on field and a little above ground
	for u: SkirmishUnit3D in all_units:
		if not u.is_alive():
			continue
		u.global_position = Vector3(
			clamp(u.global_position.x, -FIELD_HALF_WIDTH, FIELD_HALF_WIDTH),
			0.0,
			clamp(u.global_position.z, -FIELD_HALF_DEPTH, FIELD_HALF_DEPTH)
		)
	_age_waypoints(delta)
	_update_hover()
	var cap_winner := _update_capture_points(delta)
	if cap_winner >= 0:
		_forced_winner = cap_winner
	_check_end_condition()
	_refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
	# Pause menu open: Esc closes it, swallow everything else.
	if _settings_overlay != null:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_toggle_settings_menu()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# When a campaign battle has ended, any of these continue the run
		if _ended and _campaign and event.keycode in [KEY_R, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			_finish_campaign_battle()
			return
		if _deploying and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_begin_battle()
			return
		match event.keycode:
			KEY_SPACE:
				if not _deploying:
					_set_paused(not _paused)
			KEY_G:
				_command_shield_wall()
			KEY_V:
				_command_volley()
			KEY_F:
				_formation = (_formation + 1) % 2
				if _command_label != null:
					_command_label.text = "Formation: " + ("Wedge ▽" if _formation == 1 else "Line ▭")
			KEY_R:
				if _ended:
					get_tree().reload_current_scene()
			KEY_ESCAPE:
				_toggle_settings_menu()

	if event is InputEventMouseMotion:
		if _drag_active:
			_drag_current = event.position
			_update_drag_box_visual()
		return

	if event is InputEventMouseButton:
		if _ended and _campaign and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_finish_campaign_battle()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_left_press(event.position, event.shift_pressed)
			else:
				_end_left_press(event.position, event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_zoom = clamp(_cam_zoom - 0.12, 0.5, 1.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_zoom = clamp(_cam_zoom + 0.12, 0.5, 1.8)

func _set_paused(v: bool) -> void:
	_paused = v
	_refresh_ui()

# During deployment only player regiments move (combat off); they're clamped to
# the deploy zone. Enemies stand frozen.
func _deploy_tick(delta: float) -> void:
	for u: SkirmishUnit3D in player_units:
		if not u.is_alive():
			continue
		u.tick(delta, player_units, false)
		u.global_position.x = clamp(u.global_position.x, -FIELD_HALF_WIDTH, DEPLOY_X_MAX)
		u.global_position.z = clamp(u.global_position.z, -FIELD_HALF_DEPTH, FIELD_HALF_DEPTH)
	_update_hover()

func _begin_battle() -> void:
	if not _deploying:
		return
	_deploying = false
	for u: SkirmishUnit3D in player_units:
		u.clear_order()
	if _command_label != null:
		_command_label.text = "Battle begins! Select regiments, then right-click to order."

# Command abilities on the current selection.
func _command_shield_wall() -> void:
	if selected_units.is_empty():
		return
	var turn_on := false
	for u: SkirmishUnit3D in selected_units:
		if not u.guarding:
			turn_on = true
	for u: SkirmishUnit3D in selected_units:
		u.set_guard(turn_on)
	if _command_label != null:
		_command_label.text = "Shield Wall " + ("RAISED — holding ground, armoured" if turn_on else "lowered")

func _command_volley() -> void:
	if selected_units.is_empty():
		return
	var any := false
	for u: SkirmishUnit3D in selected_units:
		if u.is_ranged:
			u.arm_volley()
			any = true
	if _command_label != null:
		_command_label.text = "Volley readied — next shot hits hard!" if any else "No ranged regiments selected"

func _begin_left_press(mouse: Vector2, shift: bool) -> void:
	if _ended:
		return
	_drag_active = true
	_drag_origin = mouse
	_drag_current = mouse
	_drag_additive = shift
	_update_drag_box_visual()

func _end_left_press(mouse: Vector2, _shift: bool) -> void:
	if not _drag_active:
		return
	_drag_active = false
	_drag_box.visible = false
	if _ended:
		return
	var drag_dist := mouse.distance_to(_drag_origin)
	if drag_dist >= DRAG_THRESHOLD:
		var rect := _drag_rect_normalized()
		var picked: Array[SkirmishUnit3D] = []
		for u: SkirmishUnit3D in player_units:
			if not u.is_alive():
				continue
			if not _is_in_front_of_camera(u):
				continue
			var sp := _project_to_ui(u.global_position + Vector3(0.0, 0.55, 0.0))
			if rect.has_point(sp):
				picked.append(u)
		_apply_selection(picked, _drag_additive)
	else:
		var picked := _pick_unit_at_screen(mouse, player_units, PICK_SCREEN_RADIUS)
		if picked != null:
			_apply_selection([picked], _drag_additive)
		elif not _drag_additive:
			_apply_selection([], false)
	_refresh_ui()

func _handle_right_click(mouse: Vector2) -> void:
	if _ended or selected_units.is_empty():
		return
	# Deployment: move-only, clamped to the deploy zone (no attacking yet).
	if _deploying:
		var g := _ground_hit_from_screen(mouse)
		if g == Vector3.INF:
			return
		g.x = clamp(g.x, -FIELD_HALF_WIDTH, DEPLOY_X_MAX)
		g.z = clamp(g.z, -FIELD_HALF_DEPTH, FIELD_HALF_DEPTH)
		for u: SkirmishUnit3D in selected_units:
			if u.is_alive():
				u.order_move(g)
		_spawn_waypoint(g, Color(0.55, 0.85, 0.95))
		return
	var enemy: SkirmishUnit3D = _pick_unit_at_screen(mouse, enemy_units, PICK_SCREEN_RADIUS)
	if enemy != null:
		for u: SkirmishUnit3D in selected_units:
			if u.is_alive():
				u.order_attack(enemy)
		_spawn_waypoint(enemy.global_position + Vector3(0.0, 0.2, 0.0), Color(1.0, 0.40, 0.40))
		if _command_label != null:
			_command_label.text = "Attack order: %d regiment%s focusing %s." % [
				selected_units.size(), "" if selected_units.size() == 1 else "s", enemy.unit_name
			]
		return
	var target := _ground_hit_from_screen(mouse)
	if target == Vector3.INF:
		return
	target = _clamp_to_field(target)
	var alive_sel: Array[SkirmishUnit3D] = []
	for u: SkirmishUnit3D in selected_units:
		if u.is_alive():
			alive_sel.append(u)
	var n: int = alive_sel.size()
	for i in range(n):
		var u: SkirmishUnit3D = alive_sel[i]
		var dest: Vector3 = target
		if n > 1:
			var to_t := dest - u.global_position
			if to_t.length() < 0.1:
				to_t = Vector3(1.0, 0.0, 0.0)
			var right := Vector3(-to_t.z, 0.0, to_t.x).normalized()
			var offset := float(i) - (float(n) - 1.0) * 0.5
			dest += right * 2.4 * offset
			if _formation == 1:
				dest -= to_t.normalized() * 1.9 * abs(offset)
			dest.x = clamp(dest.x, -FIELD_HALF_WIDTH, FIELD_HALF_WIDTH)
			dest.z = clamp(dest.z, -FIELD_HALF_DEPTH, FIELD_HALF_DEPTH)
		u.order_move(dest)
	_spawn_waypoint(target, Color(0.55, 0.95, 0.55))
	if _command_label != null:
		_command_label.text = "Move order: %d regiment%s to marked ground." % [
			n, "" if n == 1 else "s"
		]

func _apply_selection(units: Array[SkirmishUnit3D], additive: bool) -> void:
	if not additive:
		for u: SkirmishUnit3D in selected_units:
			if is_instance_valid(u):
				u.set_selected(false)
		selected_units.clear()
	for u: SkirmishUnit3D in units:
		if u == null or not u.is_alive():
			continue
		if not selected_units.has(u):
			selected_units.append(u)
			u.set_selected(true)

func _update_hover() -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# Hover own units first, then enemies — so you can inspect either side.
	var under := _pick_unit_at_screen(mouse, player_units, PICK_SCREEN_RADIUS)
	if under == null:
		under = _pick_unit_at_screen(mouse, enemy_units, PICK_SCREEN_RADIUS)
	if under != hovered_unit:
		if hovered_unit != null and is_instance_valid(hovered_unit):
			hovered_unit.set_hovered(false)
		hovered_unit = under
		if hovered_unit != null:
			hovered_unit.set_hovered(true)
	_update_info_panel(mouse)

func _update_info_panel(mouse: Vector2) -> void:
	if _info_panel == null:
		return
	if hovered_unit == null or not is_instance_valid(hovered_unit) or not hovered_unit.is_alive():
		_info_panel.visible = false
		return
	_info_label.text = hovered_unit.describe()
	_info_label.modulate = (Color(0.78, 0.86, 1.0) if hovered_unit.team == 0 else Color(1.0, 0.78, 0.74))
	# Follow the cursor, clamped on-screen
	var vs := get_viewport().get_visible_rect().size
	var pos := mouse + Vector2(18.0, 18.0)
	pos.x = clamp(pos.x, 0.0, vs.x - _info_panel.size.x)
	pos.y = clamp(pos.y, 0.0, vs.y - _info_panel.size.y)
	_info_panel.position = pos
	_info_panel.visible = true

func _ground_hit_from_screen(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var from: Vector3 = _camera.project_ray_origin(screen)
	var dir: Vector3 = _camera.project_ray_normal(screen)
	if abs(dir.y) < 0.0001:
		return Vector3.INF
	var t: float = -from.y / dir.y
	if t < 0.0:
		return Vector3.INF
	var hit := from + dir * t
	return hit

func _pick_unit_at_screen(screen: Vector2, pool: Array[SkirmishUnit3D], max_dist_px: float = 14.0) -> SkirmishUnit3D:
	var by_ray := _pick_unit_by_ray(screen, pool)
	if by_ray != null:
		return by_ray

	var best: SkirmishUnit3D = null
	var best_d: float = max_dist_px
	if _camera == null:
		return best
	for u: SkirmishUnit3D in pool:
		if not u.is_alive():
			continue
		if not _is_in_front_of_camera(u):
			continue
		var sp := _project_to_ui(u.global_position + Vector3(0.0, 0.55, 0.0))
		var d: float = sp.distance_to(screen)
		if d < best_d:
			best_d = d
			best = u
	return best

func _pick_unit_by_ray(screen: Vector2, pool: Array[SkirmishUnit3D], max_dist: float = 2000.0) -> SkirmishUnit3D:
	if _camera == null:
		return null
	var from: Vector3 = _camera.project_ray_origin(screen)
	var dir: Vector3 = _camera.project_ray_normal(screen)
	var best: SkirmishUnit3D = null
	var best_t: float = INF
	for u: SkirmishUnit3D in pool:
		if not u.is_alive():
			continue
		if not _is_in_front_of_camera(u):
			continue
		var hit_radius: float = u.radius * PICK_RAY_RADIUS_SCALE
		var t: float = (u.global_position - from).dot(dir)
		if t < 0.0 or t > max_dist:
			continue
		var closest: Vector3 = from + (dir * t)
		var offset: float = closest.distance_to(u.global_position)
		# Flat top-down units so use a slightly taller envelope to keep picks forgiving.
		if offset <= hit_radius:
			if t < best_t:
				best_t = t
				best = u
	return best

func _is_in_front_of_camera(unit: SkirmishUnit3D) -> bool:
	if _camera == null:
		return false
	var to_unit: Vector3 = unit.global_position - _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	return to_unit.dot(forward) > 0.0

func _project_to_ui(world: Vector3) -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.unproject_position(world)

func _clamp_to_field(p: Vector3) -> Vector3:
	return Vector3(
		clamp(p.x, -FIELD_HALF_WIDTH, FIELD_HALF_WIDTH),
		0.0,
		clamp(p.z, -FIELD_HALF_DEPTH, FIELD_HALF_DEPTH)
	)

func _drag_rect_normalized() -> Rect2:
	var x0: float = min(_drag_origin.x, _drag_current.x)
	var y0: float = min(_drag_origin.y, _drag_current.y)
	var x1: float = max(_drag_origin.x, _drag_current.x)
	var y1: float = max(_drag_origin.y, _drag_current.y)
	return Rect2(x0, y0, x1 - x0, y1 - y0)

func _update_drag_box_visual() -> void:
	if not _drag_active:
		return
	var drag_dist := _drag_origin.distance_to(_drag_current)
	if drag_dist < DRAG_THRESHOLD:
		_drag_box.visible = false
		return
	var r := _drag_rect_normalized()
	_drag_box.position = r.position
	_drag_box.size = r.size
	_drag_box.visible = true

func _ai_tick(delta: float) -> void:
	_ai_retarget_timer -= delta
	if _ai_retarget_timer > 0.0:
		return
	_ai_retarget_timer = AI_RETARGET_PERIOD
	for u: SkirmishUnit3D in enemy_units:
		if not u.is_alive():
			continue
		var needs_target: bool = (
			u.order == SkirmishUnit3D.Order.IDLE or
			(u.order == SkirmishUnit3D.Order.ATTACK and (u.attack_target == null or not u.attack_target.is_alive()))
		)
		if not needs_target:
			continue
		var nearest: SkirmishUnit3D = null
		var best_d: float = INF
		for p: SkirmishUnit3D in player_units:
			if not p.is_alive():
				continue
			var d: float = u.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				nearest = p
		if nearest != null:
			u.order_attack(nearest)

func _spawn_waypoint(pos: Vector3, color: Color) -> void:
	var marker := Node3D.new()
	var mesh := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.25
	mesh.mesh = sp
	mesh.position = pos + Vector3(0.0, 0.2, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_color.a = 0.8
	mesh.material_override = mat
	mesh.scale = Vector3(1.0, 0.16, 1.0)
	marker.add_child(mesh)
	marker.visible = true
	add_child(marker)
	var wp: Dictionary = {"node": marker, "age": 0.0, "lifetime": 0.6}
	_waypoints.append(wp)

func _age_waypoints(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for it: Dictionary in _waypoints:
		var it_node: Variant = it.get("node", null)
		var node: Node3D = null
		if it_node is Node3D:
			node = it_node
		var age: float = float(it.get("age", 0.0)) + delta
		var lt: float = float(it.get("lifetime", 0.0))
		if node == null or age > lt:
			if node != null and is_instance_valid(node):
				node.queue_free()
			continue
		it["age"] = age
		var t: float = clamp(age / max(0.1, lt), 0.0, 1.0)
		var mat: StandardMaterial3D = null
		if node.get_child_count() > 0:
			var first: Node = node.get_child(0)
			if first is MeshInstance3D:
				mat = (first as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = lerp(0.8, 0.0, t)
		alive.append(it)
	_waypoints = alive

func _refresh_ui() -> void:
	if _status_label != null:
		if _ended:
			_status_label.text = "Battle over"
			_status_label.modulate = Color(0.72, 0.72, 0.75)
		elif _paused:
			_status_label.text = "❚❚ PAUSED  (SPACE to resume)"
			_status_label.modulate = Color(1.0, 0.8, 0.36)
		else:
			_status_label.text = "▶ RUNNING  (SPACE to pause)"
			_status_label.modulate = Color(0.55, 0.95, 0.55)

	if _selection_label != null:
		var alive_sel: Array[SkirmishUnit3D] = []
		for u: SkirmishUnit3D in selected_units:
			if is_instance_valid(u) and u.is_alive():
				alive_sel.append(u)
		if alive_sel.size() != selected_units.size():
			selected_units = alive_sel
		if alive_sel.is_empty():
			_selection_label.text = "No regiment selected — left-click a blue regiment, drag-box for many, right-click for orders."
			if _command_label != null and not _ended:
				_command_label.modulate = Color(0.64, 0.68, 0.74)
		elif alive_sel.size() == 1:
			var u: SkirmishUnit3D = alive_sel[0]
			var order_txt := "idle"
			match u.order:
				SkirmishUnit3D.Order.MOVE:
					order_txt = "moving"
				SkirmishUnit3D.Order.ATTACK:
					order_txt = "attacking"
			var range_txt := "ranged" if u.is_ranged else "melee"
			_selection_label.text = (
				"%s  ·  %s  ·  %d / %d HP  ·  %d / %d soldiers  ·  %s"
				% [u.unit_name, range_txt, u.hp, u.max_hp, u.alive_soldier_count(), u.soldier_count, order_txt]
			)
			if _command_label != null:
				_command_label.modulate = Color(0.80, 0.86, 0.92)
		else:
			var total_hp := 0
			var total_max := 0
			for u: SkirmishUnit3D in alive_sel:
				total_hp += u.hp
				total_max += u.max_hp
			_selection_label.text = (
				"%d regiments selected  ·  %d / %d HP combined  ·  right-click to issue group order"
				% [alive_sel.size(), total_hp, total_max]
			)
			if _command_label != null:
				_command_label.modulate = Color(0.80, 0.86, 0.92)

	if _ended:
		_result_label.visible = true
		_restart_hint_label.visible = true

func _on_unit_died(u: SkirmishUnit3D) -> void:
	Sfx.play("death", -8.0)
	if selected_units.has(u):
		selected_units.erase(u)
	if hovered_unit == u:
		hovered_unit = null
	player_units.erase(u)
	enemy_units.erase(u)
	# keep corpses briefly for continuity
	var t := get_tree().create_timer(0.9)
	t.timeout.connect(func():
		if is_instance_valid(u):
			u.queue_free()
	)
	_check_end_condition()

func _check_end_condition() -> void:
	if _ended:
		return
	var p_alive := false
	var e_alive := false
	for u: SkirmishUnit3D in player_units:
		if u.is_alive():
			p_alive = true
			break
	for u: SkirmishUnit3D in enemy_units:
		if u.is_alive():
			e_alive = true
			break
	if _forced_winner < 0 and p_alive and e_alive:
		return
	_ended = true
	_paused = true
	var winner := _forced_winner
	if winner < 0:
		winner = 0 if (p_alive and not e_alive) else (1 if (e_alive and not p_alive) else -1)
	var by_obj := _forced_winner >= 0
	if _result_label != null:
		if winner == 0:
			_result_label.text = "VICTORY" + (" (objectives held)" if by_obj else "")
			_result_label.modulate = Color(0.55, 0.95, 0.55)
			Sfx.play("win")
		elif winner == 1:
			_result_label.text = "DEFEAT" + (" (objectives lost)" if by_obj else "")
			_result_label.modulate = Color(0.95, 0.45, 0.45)
			Sfx.play("lose")
		else:
			_result_label.text = "DRAW"
			_result_label.modulate = Color(0.88, 0.88, 0.5)
		_result_label.visible = true
	if _restart_hint_label != null:
		if _campaign:
			_restart_hint_label.text = "Click or press Enter to continue"
		_restart_hint_label.visible = true
	_refresh_ui()

# Campaign: apply the battle outcome to the run, then leave the skirmish.
func _finish_campaign_battle() -> void:
	var e_alive := false
	for u: SkirmishUnit3D in enemy_units:
		if u.is_alive():
			e_alive = true
			break
	var survivors: Array[Dictionary] = []
	for u: SkirmishUnit3D in player_units:
		if u.is_alive() and u.roster_index >= 0 and u.roster_index < GameManager.player_roster.size():
			survivors.append(GameManager.player_roster[u.roster_index])
	# Win by wiping the enemy OR by holding all capture points
	var won: bool = (_forced_winner == 0) or ((not e_alive) and survivors.size() > 0)
	GameManager.set_roster(survivors)
	if won:
		var tier := GameManager.pending_battle_tier
		var elite := GameManager.pending_battle_elite
		GameManager.add_gold(GameManager.battle_gold_reward(tier, elite))
		GameManager.register_battle_won(elite)
		if elite:
			GameManager.grant_random_relic()
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	else:
		GameManager.clear_run()   # defeat — the run ends
		get_tree().change_scene_to_file("res://src/title/title.tscn")
