extends Node3D

const SkirmishUnit3D := preload("res://src/skirmish3d/skirmish_unit_3d.gd")

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

var _camera: Camera3D
var _ground: MeshInstance3D
var _ground_body: StaticBody3D

var _ui: CanvasLayer
var _status_label: Label
var _selection_label: Label
var _result_label: Label
var _restart_hint_label: Label
var _drag_box: ColorRect

func _ready() -> void:
	set_process_unhandled_input(true)
	_build_field()
	_build_ui()
	_spawn_armies()
	_set_paused(false)
	_refresh_ui()

func _build_field() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, CAMERA_Y, 34.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
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
	gm.albedo_color = Color(0.16, 0.22, 0.17)
	_ground.material_override = gm
	world.add_child(_ground)

	_ground_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FIELD_HALF_WIDTH * 2.0, 0.2, FIELD_HALF_DEPTH * 2.0)
	cs.shape = box
	_ground_body.add_child(cs)
	world.add_child(_ground_body)
	_ground_body.position = Vector3(0.0, 0.0, 0.0)

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
	hint.text = "L-click select / drag-box  ·  Shift = additive  ·  R-click move/attack  ·  SPACE pause  ·  R restart  ·  ESC menu"
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

func _process(delta: float) -> void:
	if _ended:
		_age_waypoints(delta)
		return
	if _paused:
		_update_hover()
		return

	var all_units: Array = []
	all_units.append_array(player_units)
	all_units.append_array(enemy_units)
	_ai_tick(delta)
	for u: SkirmishUnit3D in all_units:
		if u.is_alive():
			u.tick(delta, all_units)
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
		var d := sp.distance_to(screen)
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
		var closest: Vector3 = from + dir * t
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
	var x0 := min(_drag_origin.x, _drag_current.x)
	var y0 := min(_drag_origin.y, _drag_current.y)
	var x1 := max(_drag_origin.x, _drag_current.x)
	var y1 := max(_drag_origin.y, _drag_current.y)
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
		var needs_target := (
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
	_waypoints.append({"node": marker, "age": 0.0, "lifetime": 0.6})

func _age_waypoints(delta: float) -> void:
	var alive: Array = []
	for it: Dictionary in _waypoints:
		var node := it.get("node", null)
		var age: float = float(it.get("age", 0.0)) + delta
		var lt := float(it.get("lifetime", 0.0))
		if node == null or age > lt:
			if node != null and is_instance_valid(node):
				node.queue_free()
			continue
		it["age"] = age
		var t := clamp(age / max(0.1, lt), 0.0, 1.0)
		var mat := null
		if node.get_child_count() > 0:
			var first := node.get_child(0)
			if first != null and first is MeshInstance3D:
				mat = (first.material_override as StandardMaterial3D)
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
		elif e_alive and not p_alive:
			_result_label.text = "DEFEAT"
			_result_label.modulate = Color(0.95, 0.45, 0.45)
		else:
			_result_label.text = "DRAW"
			_result_label.modulate = Color(0.88, 0.88, 0.5)
		_result_label.visible = true
	if _restart_hint_label != null:
		_restart_hint_label.visible = true
	_refresh_ui()
