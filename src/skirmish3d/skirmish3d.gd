extends Node3D

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
}

const FIELD_HALF_WIDTH: float = 36.0
const FIELD_HALF_DEPTH: float = 17.4
const CAMERA_Y: float = 24.0
const AI_RETARGET_PERIOD: float = 0.6
const DRAG_THRESHOLD: float = 7.0
const PICK_SCREEN_RADIUS: float = 17.0
const PICK_RAY_RADIUS_SCALE: float = 1.8
const TERRAIN_COLS: int = 14
const TERRAIN_ROWS: int = 11
const TERRAIN_HEX_RADIUS: float = 2.3
const TERRAIN_X_SPACING: float = 3.9
const TERRAIN_Z_SPACING: float = 2.95
const TERRAIN_ORIGIN_X: float = -27.0
const TERRAIN_ORIGIN_Z: float = -14.5

var player_units: Array[SkirmishUnit3D] = []
var enemy_units: Array[SkirmishUnit3D] = []
var selected_units: Array[SkirmishUnit3D] = []
var hovered_unit: SkirmishUnit3D = null
var _ended: bool = false
var _paused: bool = true

var _drag_active: bool = false
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _drag_additive: bool = false

var _ai_retarget_timer: float = 0.0

var _waypoints: Array = []
var _biome: Dictionary = {}
var _mountains: Array[Vector2i] = []
var _forests: Array[Vector2i] = []
var _hills: Array[Vector2i] = []
var _lava: Array[Vector2i] = []

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
var _result_label: Label
var _restart_hint_label: Label
var _drag_box: ColorRect

func _ready() -> void:
	set_process_unhandled_input(true)
	_generate_terrain()
	_build_field()
	_build_ui()
	_spawn_armies()
	_set_paused(false)
	_refresh_ui()

func _generate_terrain() -> void:
	_mountains.clear()
	_forests.clear()
	_hills.clear()
	_lava.clear()
	var tier: int = clampi(GameManager.current_tier, 0, GameManager.MAP_TIERS - 1)
	_biome = GameManager.biome_for_tier(tier)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(tier * 127 + 31)
	var mtn: Vector2i = _biome.get("mtn", Vector2i(2, 3))

	var reserved: Array[Vector2i] = []
	for z in [1, 5, 9]:
		reserved.append(Vector2i(1, z))
		reserved.append(Vector2i(TERRAIN_COLS - 2, z))

	var col_lo: int = 2
	var col_hi: int = TERRAIN_COLS - 3
	var cluster_count: int = rng.randi_range(mtn.x, mtn.y) + 2
	for _c in range(cluster_count):
		var seed_cell := Vector2i(rng.randi_range(col_lo, col_hi), rng.randi_range(0, TERRAIN_ROWS - 1))
		if seed_cell not in reserved and seed_cell not in _mountains:
			_mountains.append(seed_cell)

		var growth: int = rng.randi_range(1, 3)
		for _g in range(growth):
			var candidates: Array[Vector2i] = []
			for mc: Vector2i in _mountains:
				for adj: Vector2i in Hex.neighbors(mc):
					if _valid_terrain_cell(adj) and adj.x >= col_lo and adj.x <= col_hi \
							and adj not in _mountains and adj not in reserved:
						candidates.append(adj)
			if not candidates.is_empty():
				_mountains.append(candidates[rng.randi() % candidates.size()])

	var taken: Array[Vector2i] = reserved.duplicate()
	taken.append_array(_mountains)
	_place_terrain_cells(rng, _forests, int(_biome.get("forest", 3) * 1.6), taken)
	_place_terrain_cells(rng, _hills, int(_biome.get("hill", 2) * 1.6), taken)
	_place_terrain_cells(rng, _lava, int(_biome.get("lava", 0) * 1.6), taken)

func _valid_terrain_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < TERRAIN_COLS and cell.y >= 0 and cell.y < TERRAIN_ROWS

func _place_terrain_cells(rng: RandomNumberGenerator, target: Array[Vector2i], count: int, taken: Array[Vector2i]) -> void:
	var tries: int = 0
	while target.size() < count and tries < 80:
		tries += 1
		var cell := Vector2i(rng.randi_range(1, TERRAIN_COLS - 2), rng.randi_range(0, TERRAIN_ROWS - 1))
		if cell not in taken:
			target.append(cell)
			taken.append(cell)

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

	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_HALF_WIDTH * 2.0, FIELD_HALF_DEPTH * 2.0)
	_ground.mesh = plane
	_ground.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_ground.position = Vector3(0.0, 0.0, 0.0)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ground_color: Color = _biome.get("bg", Color(0.07, 0.10, 0.07))
	gm.albedo_color = ground_color.lightened(0.05)
	_ground.material_override = gm
	world.add_child(_ground)
	_build_terrain_visuals(world)

	_ground_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FIELD_HALF_WIDTH * 2.0, 0.2, FIELD_HALF_DEPTH * 2.0)
	cs.shape = box
	_ground_body.add_child(cs)
	world.add_child(_ground_body)
	_ground_body.position = Vector3(0.0, 0.0, 0.0)

func _build_terrain_visuals(world: Node3D) -> void:
	_terrain_node = Node3D.new()
	_terrain_node.name = "ProceduralTerrain"
	world.add_child(_terrain_node)

	for row in range(TERRAIN_ROWS):
		for col in range(TERRAIN_COLS):
			var cell := Vector2i(col, row)
			var pos: Vector3 = _terrain_cell_world(cell)
			var color: Color = _terrain_cell_color(cell)
			_add_hex_patch(pos, color)
			if cell in _mountains:
				_add_mountain_cluster(pos, _cell_seed(cell))
			elif cell in _forests:
				_add_forest_cluster(pos, _cell_seed(cell))
			elif cell in _hills:
				_add_hill(pos, _cell_seed(cell))
			elif cell in _lava:
				_add_lava_pool(pos)

func _terrain_cell_world(cell: Vector2i) -> Vector3:
	var x: float = TERRAIN_ORIGIN_X + float(cell.x) * TERRAIN_X_SPACING
	if (cell.y & 1) == 1:
		x += TERRAIN_X_SPACING * 0.5
	var z: float = TERRAIN_ORIGIN_Z + float(cell.y) * TERRAIN_Z_SPACING
	return Vector3(x, 0.03, z)

# Inverse of _terrain_cell_world: nearest terrain cell to a world position.
func _terrain_cell_at_world(pos: Vector3) -> Vector2i:
	var row: int = int(round((pos.z - TERRAIN_ORIGIN_Z) / TERRAIN_Z_SPACING))
	row = clampi(row, 0, TERRAIN_ROWS - 1)
	var off: float = TERRAIN_X_SPACING * 0.5 if (row & 1) == 1 else 0.0
	var col: int = int(round((pos.x - TERRAIN_ORIGIN_X - off) / TERRAIN_X_SPACING))
	col = clampi(col, 0, TERRAIN_COLS - 1)
	return Vector2i(col, row)

const LAVA_DPS: int = 6
const FOREST_DEF_MULT: float = 0.7
const FOREST_SPEED_MULT: float = 0.7
const HILL_ATK_MULT: float = 1.25
const MOUNTAIN_SPEED_MULT: float = 0.4

# Each tick, stamp terrain effects (cover / high-ground / rough / lava) onto
# every living unit based on the cell it's standing on.
func _apply_terrain(delta: float) -> void:
	for u: SkirmishUnit3D in _all_living_units():
		var cell := _terrain_cell_at_world(u.global_position)
		u.terrain_def_mult = 1.0
		u.terrain_atk_mult = 1.0
		u.terrain_speed_mult = 1.0
		if cell in _forests:
			u.terrain_def_mult = FOREST_DEF_MULT
			u.terrain_speed_mult = FOREST_SPEED_MULT
		if cell in _hills:
			u.terrain_atk_mult = HILL_ATK_MULT
		if cell in _mountains:
			u.terrain_speed_mult = MOUNTAIN_SPEED_MULT
		if cell in _lava:
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

func _terrain_cell_color(cell: Vector2i) -> Color:
	if cell in _mountains:
		return Color(0.19, 0.17, 0.15)
	if cell in _forests:
		return Color(0.10, 0.25, 0.12)
	if cell in _hills:
		return Color(0.30, 0.25, 0.15)
	if cell in _lava:
		return Color(0.46, 0.12, 0.04)
	var bg: Color = _biome.get("bg", Color(0.07, 0.10, 0.07))
	return bg.lightened(0.14 if (cell.x + cell.y) % 2 == 0 else 0.08)

func _cell_seed(cell: Vector2i) -> int:
	return cell.x * 73856093 ^ cell.y * 19349663

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
	top.size = Vector2(1280.0, 60.0)
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

	var hint := Label.new()
	hint.text = "L-click select / drag-box  ·  Shift add  ·  R-click move/attack  ·  WASD/edge pan  ·  wheel zoom  ·  SPACE pause  ·  R restart  ·  ESC menu     (hills boost · forests shield · lava burns · routed units flee)"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.56, 0.56, 0.66)
	hint.position = Vector2(420.0, 22.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(hint)

	_selection_label = Label.new()
	_selection_label.add_theme_font_size_override("font_size", 15)
	_selection_label.modulate = Color(0.85, 0.90, 0.95)
	_selection_label.position = Vector2(20.0, 676.0)
	_selection_label.size = Vector2(1240.0, 30.0)
	_selection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_selection_label)

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

func _spawn_armies() -> void:
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
	_check_end_condition()
	_refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_set_paused(not _paused)
			KEY_R:
				if _ended:
					get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://src/title/title.tscn")

	if event is InputEventMouseMotion:
		if _drag_active:
			_drag_current = event.position
			_update_drag_box_visual()
		return

	if event is InputEventMouseButton:
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
	var enemy: SkirmishUnit3D = _pick_unit_at_screen(mouse, enemy_units, PICK_SCREEN_RADIUS)
	if enemy != null:
		for u: SkirmishUnit3D in selected_units:
			if u.is_alive():
				u.order_attack(enemy)
		_spawn_waypoint(enemy.global_position + Vector3(0.0, 0.2, 0.0), Color(1.0, 0.40, 0.40))
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
			dest += right * (u.radius * 0.014) * offset
			dest.x = clamp(dest.x, -FIELD_HALF_WIDTH, FIELD_HALF_WIDTH)
			dest.z = clamp(dest.z, -FIELD_HALF_DEPTH, FIELD_HALF_DEPTH)
		u.order_move(dest)
	_spawn_waypoint(target, Color(0.55, 0.95, 0.55))

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
	var under := _pick_unit_at_screen(mouse, player_units, PICK_SCREEN_RADIUS)
	if under == hovered_unit:
		return
	if hovered_unit != null and is_instance_valid(hovered_unit):
		hovered_unit.set_hovered(false)
	hovered_unit = under
	if hovered_unit != null:
		hovered_unit.set_hovered(true)

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
	if p_alive and e_alive:
		return
	_ended = true
	_paused = true
	if _result_label != null:
		if p_alive and not e_alive:
			_result_label.text = "VICTORY"
			_result_label.modulate = Color(0.55, 0.95, 0.55)
			Sfx.play("win")
		elif e_alive and not p_alive:
			_result_label.text = "DEFEAT"
			_result_label.modulate = Color(0.95, 0.45, 0.45)
			Sfx.play("lose")
		else:
			_result_label.text = "DRAW"
			_result_label.modulate = Color(0.88, 0.88, 0.5)
		_result_label.visible = true
	if _restart_hint_label != null:
		_restart_hint_label.visible = true
	_refresh_ui()
