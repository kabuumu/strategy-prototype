extends Node2D

# Base-building RTS skirmish — inspired by AoE2 / Red Alert 2, boiled down to the
# core loop: your Keep earns gold, you spend it on economy + production
# buildings, produced regiments auto-march across the field and smash the enemy
# Keep while defending your own. Destroy the enemy Keep to win; lose yours and
# it's over. The enemy mirrors you with a scaling production AI.
#
# Two entry points: standalone from the title, or a campaign battle
# (battle_mode "base", GameManager.pending_base) that reports win/loss back.
#
# Combat reuses RTUnit (regiments). Keeps are RTUnits too, so units can attack
# them and the win/lose check is just "is that Keep still alive".

const UITheme := preload("res://src/ui/ui_theme.gd")
const RTUnit := preload("res://src/rtbattle/rt_unit.gd")

const FIELD_RECT: Rect2 = Rect2(40.0, 96.0, 1200.0, 560.0)
const PLAYER_BUILD_MAX_X: float = 600.0     # you build left of this
const PLAYER_KEEP_POS: Vector2 = Vector2(120.0, 376.0)
const ENEMY_KEEP_POS: Vector2 = Vector2(1160.0, 376.0)
const MAX_UNITS_PER_SIDE: int = 40          # perf cap

# Keep stats (an RTUnit that mostly stands and defends).
const KEEP_STATS: Dictionary = {
	"name": "Keep", "sprite_key": "soldier",
	"soldier_count": 16, "hp_per_soldier": 60, "damage_per_attack": 10,
	"attack_cooldown": 1.0, "attack_range_px": 150.0, "move_speed_px": 0.0,
}

# Buildings you can place. "produces" spawns a unit every "interval" seconds;
# "income" adds passive gold/sec. Towers are stationary defensive RTUnits.
const BUILDING_TYPES: Dictionary = {
	"farm":     {"name": "Farm",         "cost": 40,  "income": 3,  "color": Color(0.55, 0.50, 0.20)},
	"barracks": {"name": "Barracks",     "cost": 70,  "produces": "infantry", "interval": 5.0, "color": Color(0.40, 0.30, 0.25)},
	"range":    {"name": "Archery Range","cost": 90,  "produces": "archers",  "interval": 6.0, "color": Color(0.25, 0.42, 0.28)},
	"stable":   {"name": "Stable",       "cost": 120, "produces": "cavalry",  "interval": 7.5, "color": Color(0.30, 0.30, 0.48)},
	"tower":    {"name": "Watchtower",   "cost": 80,  "tower": "archers",     "color": Color(0.34, 0.36, 0.46)},
}

# Regiment stats for produced units (RTUnit stat dicts).
const UNIT_STATS: Dictionary = {
	"infantry": {"name": "Infantry", "sprite_key": "soldier",
		"soldier_count": 8, "hp_per_soldier": 16, "damage_per_attack": 8,
		"attack_cooldown": 1.0, "attack_range_px": 56.0, "move_speed_px": 70.0},
	"archers":  {"name": "Archers", "sprite_key": "archer",
		"soldier_count": 6, "hp_per_soldier": 11, "damage_per_attack": 9,
		"attack_cooldown": 1.3, "attack_range_px": 200.0, "move_speed_px": 64.0},
	"cavalry":  {"name": "Cavalry", "sprite_key": "scout",
		"soldier_count": 6, "hp_per_soldier": 16, "damage_per_attack": 11,
		"attack_cooldown": 0.9, "attack_range_px": 56.0, "move_speed_px": 120.0},
}

var _gold: float = 150.0
var _income: float = 4.0           # passive gold/sec (Keep + farms)
var _selected: String = "barracks"
var _paused: bool = false
var _ended: bool = false
var _won: bool = false

var _player_base: RTUnit
var _enemy_base: RTUnit
var _player_units: Array = []
var _enemy_units: Array = []
var _buildings: Array = []         # [{node, type, timer, interval, produces}]

var _retarget_timer: float = 0.0
var _enemy_spawn_timer: float = 6.0
var _enemy_income_accum: float = 0.0
var _elapsed: float = 0.0

var _ui: CanvasLayer
var _gold_label: Label
var _status_label: Label
var _stat_label: Label
var _settings_overlay: Control = null
var _rng := RandomNumberGenerator.new()

# Campaign integration
var _campaign: bool = false
var _campaign_lost: bool = false
var _campaign_relic: String = ""
var _campaign_reward_gold: int = 0
var _enemy_strength: float = 1.0   # scales enemy HP / spawn cadence (tier)

func _ready() -> void:
	_rng.randomize()
	set_process_unhandled_input(true)
	if GameManager.pending_base:
		GameManager.pending_base = false
		_campaign = true
		var tier: int = GameManager.pending_battle_tier
		_enemy_strength = 1.0 + tier * 0.25 + (0.3 if GameManager.pending_battle_elite else 0.0)
		_gold = 150.0 + float(maxi(0, GameManager.player_roster.size() - 3)) * 25.0
	_spawn_bases()
	_build_ui()
	_refresh_ui()
	queue_redraw()

func _spawn_bases() -> void:
	_player_base = RTUnit.new()
	add_child(_player_base)
	_player_base.setup("keep", 0, PLAYER_KEEP_POS, KEEP_STATS)
	_player_base.clear_order()
	_player_base.died.connect(func(_u): _conclude(false))

	_enemy_base = RTUnit.new()
	add_child(_enemy_base)
	var estats := KEEP_STATS.duplicate(true)
	estats["hp_per_soldier"] = int(round(float(KEEP_STATS["hp_per_soldier"]) * _enemy_strength))
	_enemy_base.setup("keep", 1, ENEMY_KEEP_POS, estats)
	_enemy_base.clear_order()
	_enemy_base.died.connect(func(_u): _conclude(true))

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var top := ColorRect.new()
	top.color = Color(0.07, 0.09, 0.13, 0.93)
	top.size = Vector2(1280.0, 88.0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(top)

	_ui.add_child(UITheme.label("BASE BUILDING — raze the enemy keep", 22, UITheme.GOLD, Vector2(20.0, 8.0), Vector2(520.0, 30.0)))
	_gold_label = UITheme.label("", 17, UITheme.GOLD, Vector2(20.0, 42.0), Vector2(260.0, 24.0))
	_ui.add_child(_gold_label)
	_stat_label = UITheme.label("", 14, UITheme.TEXT_MUTED, Vector2(280.0, 44.0), Vector2(360.0, 24.0))
	_ui.add_child(_stat_label)

	var x := 470.0
	for id: String in BUILDING_TYPES:
		var b: Dictionary = BUILDING_TYPES[id]
		_ui.add_child(UITheme.button("%s\n%dg" % [String(b["name"]), int(b["cost"])],
			Vector2(x, 6.0), Vector2(118.0, 48.0), Color(b["color"]).darkened(0.05),
			_on_pick.bind(id), 12))
		x += 124.0

	_ui.add_child(UITheme.button("Menu", Vector2(1158.0, 8.0), Vector2(100.0, 40.0), UITheme.RED, _toggle_settings_menu))
	_status_label = UITheme.label("Select a building, click your half of the field to place it.",
		14, UITheme.TEXT_MUTED, Vector2(20.0, 66.0), Vector2(900.0, 20.0))
	_ui.add_child(_status_label)

func _refresh_ui() -> void:
	if _gold_label != null:
		_gold_label.text = "Gold: %d   (+%d/s)" % [int(_gold), int(_income)]
	if _stat_label != null and is_instance_valid(_player_base) and is_instance_valid(_enemy_base):
		_stat_label.text = "Your Keep %d   ·   Enemy Keep %d   ·   Army %d v %d" % [
			_player_base.hp, _enemy_base.hp, _player_units.size(), _enemy_units.size()]

func _on_pick(id: String) -> void:
	_selected = id
	_status_label.text = "%s selected (%dg). Click your half of the field." % [
		String(BUILDING_TYPES[id]["name"]), int(BUILDING_TYPES[id]["cost"])]

# ---------------------------------------------------------------------------
# Building placement
# ---------------------------------------------------------------------------
func _try_build(pos: Vector2) -> void:
	if _ended:
		return
	var b: Dictionary = BUILDING_TYPES[_selected]
	var cost: int = int(b["cost"])
	if not FIELD_RECT.has_point(pos) or pos.x > PLAYER_BUILD_MAX_X:
		_status_label.text = "Build on your half of the field (left side)."
		return
	if pos.distance_to(PLAYER_KEEP_POS) < 70.0:
		_status_label.text = "Too close to your Keep."
		return
	for e in _buildings:
		var n: Node2D = e["node"]
		if is_instance_valid(n) and n.position.distance_to(pos) < 64.0:
			_status_label.text = "Too close to another building."
			return
	if _gold < float(cost):
		_status_label.text = "Not enough gold for %s." % String(b["name"])
		return
	_gold -= float(cost)
	if b.has("income"):
		_income += float(b["income"])
	if b.has("tower"):
		var t := RTUnit.new()
		add_child(t)
		t.setup("tower", 0, pos, UNIT_STATS[String(b["tower"])])
		t.clear_order()
		_player_units.append(t)   # a stationary defender (move_speed kept; we never order it to move)
	var node := _make_building_node(pos, b)
	add_child(node)
	_buildings.append({
		"node": node, "type": _selected,
		"timer": float(b.get("interval", 0.0)),
		"interval": float(b.get("interval", 0.0)),
		"produces": String(b.get("produces", "")),
	})
	Sfx.play("gold")
	_refresh_ui()

func _make_building_node(pos: Vector2, b: Dictionary) -> Node2D:
	var n := Node2D.new()
	n.position = pos
	var rect := ColorRect.new()
	rect.size = Vector2(48.0, 48.0)
	rect.position = Vector2(-24.0, -24.0)
	rect.color = Color(b["color"])
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(rect)
	var lbl := UITheme.label(String(b["name"]).substr(0, 3), 12, Color(0.9, 0.92, 0.95), Vector2(-22.0, -8.0), Vector2(44.0, 16.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_child(lbl)
	return n

# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------
func _spawn_unit(unit_id: String, team: int, pos: Vector2) -> void:
	var pool: Array = _player_units if team == 0 else _enemy_units
	if pool.size() >= MAX_UNITS_PER_SIDE:
		return
	var u := RTUnit.new()
	add_child(u)
	u.setup(unit_id, team, pos + Vector2(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-40.0, 40.0)), UNIT_STATS[unit_id])
	u.died.connect(_on_unit_died)
	pool.append(u)

func _on_unit_died(u: RTUnit) -> void:
	_player_units.erase(u)
	_enemy_units.erase(u)

func _process(delta: float) -> void:
	if _paused or _ended:
		return
	_elapsed += delta
	_gold += _income * delta

	# Player production buildings
	for e in _buildings:
		if String(e["produces"]) == "":
			continue
		e["timer"] = float(e["timer"]) - delta
		if e["timer"] <= 0.0:
			e["timer"] = float(e["interval"])
			var n: Node2D = e["node"]
			if is_instance_valid(n):
				_spawn_unit(String(e["produces"]), 0, n.position)

	# Enemy production AI — cadence quickens and composition hardens over time.
	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0.0:
		_enemy_spawn_timer = maxf(2.0, 6.0 - _elapsed * 0.03) / _enemy_strength
		_spawn_unit(_enemy_pick(), 1, ENEMY_KEEP_POS)

	var all_units: Array = []
	all_units.append_array(_player_units)
	all_units.append_array(_enemy_units)
	if is_instance_valid(_player_base):
		all_units.append(_player_base)
	if is_instance_valid(_enemy_base):
		all_units.append(_enemy_base)

	# Retarget: fight a nearby enemy, otherwise advance on the enemy Keep.
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.4
		_assign_orders(_player_units, _enemy_units, _enemy_base)
		_assign_orders(_enemy_units, _player_units, _player_base)

	for u: RTUnit in all_units:
		if is_instance_valid(u) and u.is_alive():
			u.tick(delta, all_units)

	_clean_dead()
	_refresh_ui()
	queue_redraw()

func _assign_orders(side: Array, foes: Array, foe_base: RTUnit) -> void:
	for u: RTUnit in side:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var nearest: RTUnit = null
		var best: float = 260.0
		for f: RTUnit in foes:
			if is_instance_valid(f) and f.is_alive():
				var d: float = u.position.distance_to(f.position)
				if d < best:
					best = d
					nearest = f
		if nearest != null:
			u.order_attack(nearest)
		elif is_instance_valid(foe_base) and foe_base.is_alive():
			u.order_attack(foe_base)

func _enemy_pick() -> String:
	var roll := _rng.randf()
	if _elapsed > 40.0 and roll < 0.3:
		return "cavalry"
	if roll < 0.4:
		return "archers"
	return "infantry"

func _clean_dead() -> void:
	_player_units = _player_units.filter(func(u): return is_instance_valid(u) and u.is_alive())
	_enemy_units = _enemy_units.filter(func(u): return is_instance_valid(u) and u.is_alive())

# ---------------------------------------------------------------------------
# Win / loss
# ---------------------------------------------------------------------------
func _conclude(win: bool) -> void:
	if _ended:
		return
	_ended = true
	_won = win
	if _campaign:
		_conclude_campaign(win)
	Sfx.play("win" if win else "lose", -6.0)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	UITheme.panel(root, Vector2(480.0, 244.0), Vector2(320.0, 234.0))
	root.add_child(UITheme.label("VICTORY" if win else "DEFEAT", 40,
		UITheme.GOLD if win else UITheme.RED, Vector2(556.0, 266.0)))
	var sub: String
	if _campaign:
		sub = ("+%d gold%s" % [_campaign_reward_gold,
			"   ·   Relic: %s" % String(GameManager.RELICS[_campaign_relic]["name"]) if _campaign_relic != "" else ""]) if win \
			else "Your keep has fallen — the run ends here."
	else:
		sub = "The enemy keep is rubble." if win else "Your keep has fallen."
	root.add_child(UITheme.label(sub, 15, UITheme.TEXT_MUTED, Vector2(500.0, 322.0), Vector2(280.0, 40.0)))
	if _campaign and win:
		root.add_child(UITheme.button("Continue", Vector2(512.0, 372.0), Vector2(256.0, 46.0),
			UITheme.GREEN, func() -> void: get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")))
	elif _campaign and not win:
		root.add_child(UITheme.button("To Title", Vector2(512.0, 372.0), Vector2(256.0, 46.0),
			Color(0.45, 0.30, 0.34), func() -> void: get_tree().change_scene_to_file("res://src/title/title.tscn")))
	else:
		root.add_child(UITheme.button("Play Again", Vector2(512.0, 372.0), Vector2(256.0, 44.0),
			UITheme.GREEN, func() -> void: get_tree().reload_current_scene()))
		root.add_child(UITheme.button("To Title", Vector2(512.0, 424.0), Vector2(256.0, 40.0),
			Color(0.45, 0.30, 0.34), func() -> void: get_tree().change_scene_to_file("res://src/title/title.tscn")))
	_ui.add_child(root)

func _conclude_campaign(win: bool) -> void:
	var tier: int = GameManager.pending_battle_tier
	var elite: bool = GameManager.pending_battle_elite
	_campaign_lost = not win
	if win:
		# Base-building doesn't consume the roster — your army returns intact.
		_campaign_reward_gold = GameManager.battle_gold_reward(tier, elite)
		GameManager.add_gold(_campaign_reward_gold)
		GameManager.register_battle_won(elite)
		if elite:
			_campaign_relic = GameManager.grant_random_relic()
		GameManager.save_run()
	else:
		GameManager.clear_run()

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _settings_overlay != null:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_toggle_settings_menu()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_paused = not _paused
				_status_label.text = "Paused." if _paused else "Resumed."
			KEY_ESCAPE:
				_toggle_settings_menu()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.y > FIELD_RECT.position.y:
			_try_build(event.position)

func _toggle_settings_menu() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	_settings_overlay = UITheme.pause_menu(_toggle_settings_menu,
		func() -> void: get_tree().change_scene_to_file("res://src/title/title.tscn"))
	_ui.add_child(_settings_overlay)

# ---------------------------------------------------------------------------
# Draw
# ---------------------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color(0.07, 0.10, 0.07))
	draw_rect(FIELD_RECT, Color(0.13, 0.18, 0.13))
	# Your buildable half tint
	draw_rect(Rect2(FIELD_RECT.position, Vector2(PLAYER_BUILD_MAX_X - FIELD_RECT.position.x, FIELD_RECT.size.y)),
		Color(0.18, 0.24, 0.30, 0.25))
	draw_line(Vector2(PLAYER_BUILD_MAX_X, FIELD_RECT.position.y), Vector2(PLAYER_BUILD_MAX_X, FIELD_RECT.end.y),
		Color(0.40, 0.45, 0.55, 0.5), 1.0)
	_draw_keep(PLAYER_KEEP_POS, _player_base, Color(0.30, 0.45, 0.75))
	_draw_keep(ENEMY_KEEP_POS, _enemy_base, Color(0.75, 0.30, 0.30))

func _draw_keep(pos: Vector2, base: RTUnit, color: Color) -> void:
	var r := Rect2(pos - Vector2(34.0, 44.0), Vector2(68.0, 88.0))
	draw_rect(r, color.darkened(0.2))
	draw_rect(r, color.lightened(0.2), false, 3.0)
	if is_instance_valid(base):
		var frac: float = clampf(float(base.hp) / float(base.max_hp), 0.0, 1.0)
		draw_rect(Rect2(r.position + Vector2(6.0, -14.0), Vector2((r.size.x - 12.0) * frac, 7.0)),
			Color(0.30, 0.85, 0.30) if frac > 0.3 else Color(0.9, 0.3, 0.3))
