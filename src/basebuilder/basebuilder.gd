extends Node2D

# Base-building RTS skirmish — inspired by AoE2 / Red Alert 2, boiled down to the
# core loop: your Town Centre earns gold, you spend it on economy + production
# buildings, produced regiments auto-march across the field and tear down the
# enemy's base while you defend your own.
#
# WIN by razing the ENTIRE enemy base — every production building AND the Town
# Centre. LOSE if your Town Centre falls. The enemy starts with its own buildings
# (which you must destroy) and produces a scaling stream of attackers.
#
# Two entry points: standalone from the title, or a campaign battle
# (battle_mode "base", GameManager.pending_base) that reports win/loss back.
#
# Every structure is an RTUnit "garrison" (stationary, has HP) so regiments can
# attack it and the win/lose check is just "are any of that side's structures
# still standing". Combat reuses the RTUnit regiment engine.

const UITheme := preload("res://src/ui/ui_theme.gd")
const RTUnit := preload("res://src/rtbattle/rt_unit.gd")

const FIELD_RECT: Rect2 = Rect2(40.0, 96.0, 1200.0, 560.0)
const PLAYER_BUILD_MAX_X: float = 560.0     # you build left of this
const ENEMY_BUILD_MIN_X: float = 720.0
const PLAYER_TC_POS: Vector2 = Vector2(110.0, 376.0)
const ENEMY_TC_POS: Vector2 = Vector2(1170.0, 376.0)
const MAX_UNITS_PER_SIDE: int = 36          # perf cap

# Structures. tc = Town Centre (the HQ). The rest are buildable. "produces"
# spawns a regiment every "interval"s; "income" adds passive gold/sec (player);
# "dmg" > 0 makes it defend (Town Centre + tower). hp via count * per.
const STRUCTURES: Dictionary = {
	"tc":       {"name": "Town Centre",  "count": 6, "per": 150, "dmg": 12, "range": 150.0, "cd": 1.0, "color": Color(0.30, 0.40, 0.62)},
	"farm":     {"name": "Farm",          "cost": 40,  "count": 3, "per": 60,  "dmg": 0, "range": 24.0, "cd": 1.0, "income": 3,    "color": Color(0.55, 0.50, 0.20)},
	"barracks": {"name": "Barracks",      "cost": 70,  "count": 4, "per": 60,  "dmg": 0, "range": 24.0, "cd": 1.0, "produces": "infantry", "interval": 5.0, "color": Color(0.42, 0.30, 0.25)},
	"range":    {"name": "Archery Range", "cost": 90,  "count": 4, "per": 55,  "dmg": 0, "range": 24.0, "cd": 1.0, "produces": "archers",  "interval": 6.0, "color": Color(0.25, 0.42, 0.28)},
	"stable":   {"name": "Stable",        "cost": 120, "count": 4, "per": 65,  "dmg": 0, "range": 24.0, "cd": 1.0, "produces": "cavalry",  "interval": 7.5, "color": Color(0.30, 0.30, 0.48)},
	"tower":    {"name": "Watchtower",    "cost": 80,  "count": 4, "per": 50,  "dmg": 10, "range": 200.0, "cd": 1.1, "color": Color(0.34, 0.36, 0.46)},
}
const BUILDABLE: Array = ["farm", "barracks", "range", "stable", "tower"]

const UNIT_STATS: Dictionary = {
	"infantry": {"name": "Infantry", "sprite_key": "soldier",
		"soldier_count": 8, "hp_per_soldier": 16, "damage_per_attack": 9,
		"attack_cooldown": 1.0, "attack_range_px": 56.0, "move_speed_px": 70.0},
	"archers":  {"name": "Archers", "sprite_key": "archer",
		"soldier_count": 6, "hp_per_soldier": 11, "damage_per_attack": 10,
		"attack_cooldown": 1.3, "attack_range_px": 200.0, "move_speed_px": 64.0},
	"cavalry":  {"name": "Cavalry", "sprite_key": "scout",
		"soldier_count": 6, "hp_per_soldier": 16, "damage_per_attack": 12,
		"attack_cooldown": 0.9, "attack_range_px": 56.0, "move_speed_px": 120.0},
}

var _gold: float = 150.0
var _income: float = 4.0
var _selected: String = "barracks"
var _paused: bool = false
var _ended: bool = false
var _won: bool = false

var _structures: Array = []        # [{rt:RTUnit, vis:Node2D, type, team, home:Vector2, timer:float}]
var _player_units: Array = []
var _enemy_units: Array = []

var _retarget_timer: float = 0.0
var _enemy_build_timer: float = 14.0   # enemy occasionally adds a building
var _elapsed: float = 0.0

var _ui: CanvasLayer
var _gold_label: Label
var _status_label: Label
var _stat_label: Label
var _settings_overlay: Control = null
var _help_overlay: Control = null
var _rng := RandomNumberGenerator.new()

const HELP_BODY: String = "Destroy the ENTIRE enemy base — every building AND their Town Centre — to win. Lose your Town Centre and it's over.\n\nYour Town Centre earns gold over time. Spend it: pick a building from the top bar and click your half of the field (left).\n\n- Farm: more income\n- Barracks / Archery Range / Stable: auto-produce regiments that march right and assault the enemy base\n- Watchtower: stationary defender\n\nYour regiments fight what they meet, then grind through the enemy's buildings to the HQ. The enemy mirrors you with a scaling attack — defend!\n\nSPACE pause  ·  Esc menu  ·  H help"

# Campaign integration
var _campaign: bool = false
var _campaign_lost: bool = false
var _campaign_relic: String = ""
var _campaign_reward_gold: int = 0
var _enemy_strength: float = 1.0

func _ready() -> void:
	_rng.randomize()
	set_process_unhandled_input(true)
	if GameManager.pending_base:
		GameManager.pending_base = false
		_campaign = true
		var tier: int = GameManager.pending_battle_tier
		_enemy_strength = 1.0 + tier * 0.22 + (0.3 if GameManager.pending_battle_elite else 0.0)
		_gold = 150.0 + float(maxi(0, GameManager.player_roster.size() - 3)) * 25.0
	_spawn_initial_bases()
	_build_ui()
	_refresh_ui()
	queue_redraw()

func _spawn_initial_bases() -> void:
	_make_structure("tc", 0, PLAYER_TC_POS)
	_make_structure("tc", 1, ENEMY_TC_POS)
	# Enemy starts with a small base you must dismantle: barracks + range, plus a
	# stable / tower on tougher (campaign) fights.
	_make_structure("barracks", 1, ENEMY_TC_POS + Vector2(-90.0, -110.0))
	_make_structure("range", 1, ENEMY_TC_POS + Vector2(-90.0, 110.0))
	if _enemy_strength >= 1.4:
		_make_structure("stable", 1, ENEMY_TC_POS + Vector2(-150.0, 0.0))
	if _enemy_strength >= 1.7:
		_make_structure("tower", 1, ENEMY_TC_POS + Vector2(-40.0, -150.0))

func _make_structure(type: String, team: int, pos: Vector2) -> Dictionary:
	var def: Dictionary = STRUCTURES[type]
	var per: int = int(def["per"])
	if team == 1 and type == "tc":
		per = int(round(float(per) * _enemy_strength))   # enemy HQ scales with tier
	var stats: Dictionary = {
		"name": String(def["name"]),
		"sprite_key": "soldier",
		"soldier_count": int(def["count"]),
		"hp_per_soldier": per,
		"damage_per_attack": int(def.get("dmg", 0)),
		"attack_cooldown": float(def.get("cd", 1.0)),
		"attack_range_px": float(def.get("range", 24.0)),
		"move_speed_px": 0.0,
	}
	var rt := RTUnit.new()
	add_child(rt)
	rt.setup(type, team, pos, stats)
	rt.clear_order()
	var s := {
		"rt": rt, "vis": _make_structure_visual(type, team, pos), "type": type,
		"team": team, "home": pos, "timer": float(def.get("interval", 0.0)),
	}
	add_child(s["vis"])
	rt.died.connect(_on_structure_died.bind(s))
	_structures.append(s)
	return s

func _make_structure_visual(type: String, team: int, pos: Vector2) -> Node2D:
	var def: Dictionary = STRUCTURES[type]
	var n := Node2D.new()
	n.position = pos
	n.z_index = 5
	var big: bool = type == "tc"
	var sz := Vector2(70.0, 70.0) if big else Vector2(46.0, 46.0)
	var rect := ColorRect.new()
	rect.size = sz
	rect.position = -sz * 0.5
	rect.color = Color(def["color"]).lerp(Color(0.2, 0.4, 0.85) if team == 0 else Color(0.85, 0.25, 0.25), 0.18)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(rect)
	var border := ColorRect.new()   # thin top band as a faux roof/border
	border.size = Vector2(sz.x, 4.0)
	border.position = Vector2(-sz.x * 0.5, -sz.y * 0.5 - 4.0)
	border.color = (Color(0.45, 0.62, 0.95) if team == 0 else Color(0.95, 0.45, 0.45))
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(border)
	var lbl := UITheme.label(String(def["name"]).substr(0, 3).to_upper() if not big else "HQ",
		12 if not big else 15, Color(0.95, 0.96, 0.98), Vector2(-sz.x * 0.5, -8.0), Vector2(sz.x, 18.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_child(lbl)
	return n

func _on_structure_died(s: Dictionary) -> void:
	if is_instance_valid(s["vis"]):
		s["vis"].queue_free()
	Sfx.play("death", -8.0)

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

	_ui.add_child(UITheme.label("BASE BUILDING — raze the enemy base", 22, UITheme.GOLD, Vector2(20.0, 8.0), Vector2(540.0, 30.0)))
	_gold_label = UITheme.label("", 17, UITheme.GOLD, Vector2(20.0, 42.0), Vector2(260.0, 24.0))
	_ui.add_child(_gold_label)
	_stat_label = UITheme.label("", 14, UITheme.TEXT_MUTED, Vector2(280.0, 44.0), Vector2(380.0, 24.0))
	_ui.add_child(_stat_label)

	var x := 470.0
	for id: String in BUILDABLE:
		var b: Dictionary = STRUCTURES[id]
		_ui.add_child(UITheme.button("%s\n%dg" % [String(b["name"]), int(b["cost"])],
			Vector2(x, 6.0), Vector2(118.0, 48.0), Color(b["color"]).darkened(0.05),
			_on_pick.bind(id), 12))
		x += 124.0

	_ui.add_child(UITheme.button("Menu", Vector2(1158.0, 8.0), Vector2(100.0, 40.0), UITheme.RED, _toggle_settings_menu))
	_status_label = UITheme.label("Select a building, click your half of the field to place it. Destroy every enemy building AND their HQ to win.",
		14, UITheme.TEXT_MUTED, Vector2(20.0, 66.0), Vector2(1000.0, 20.0))
	_ui.add_child(_status_label)

func _refresh_ui() -> void:
	if _gold_label != null:
		_gold_label.text = "Gold: %d   (+%d/s)" % [int(_gold), int(_income)]
	if _stat_label != null:
		_stat_label.text = "Enemy buildings left: %d   ·   Army %d v %d" % [
			_alive_structures(1).size(), _player_units.size(), _enemy_units.size()]

func _on_pick(id: String) -> void:
	_selected = id
	_status_label.text = "%s selected (%dg). Click your half of the field." % [
		String(STRUCTURES[id]["name"]), int(STRUCTURES[id]["cost"])]

# ---------------------------------------------------------------------------
# Building placement
# ---------------------------------------------------------------------------
func _try_build(pos: Vector2) -> void:
	if _ended:
		return
	var b: Dictionary = STRUCTURES[_selected]
	var cost: int = int(b["cost"])
	if not FIELD_RECT.has_point(pos) or pos.x > PLAYER_BUILD_MAX_X:
		_status_label.text = "Build on your half of the field (left side)."
		return
	if pos.distance_to(PLAYER_TC_POS) < 78.0:
		_status_label.text = "Too close to your Town Centre."
		return
	for s in _structures:
		if s["team"] == 0 and is_instance_valid(s["rt"]) and Vector2(s["home"]).distance_to(pos) < 60.0:
			_status_label.text = "Too close to another building."
			return
	if _gold < float(cost):
		_status_label.text = "Not enough gold for %s." % String(b["name"])
		return
	_gold -= float(cost)
	_make_structure(_selected, 0, pos)
	Sfx.play("gold")
	_refresh_ui()

# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------
func _spawn_unit(unit_id: String, team: int, pos: Vector2) -> void:
	var pool: Array = _player_units if team == 0 else _enemy_units
	if pool.size() >= MAX_UNITS_PER_SIDE:
		return
	var u := RTUnit.new()
	add_child(u)
	u.setup(unit_id, team, pos + Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-44.0, 44.0)), UNIT_STATS[unit_id])
	if team == 0 and _campaign:
		u.damage_per_attack = maxi(1, int(round(float(u.damage_per_attack) * GameManager.rt_player_damage_mult())))
		u.max_hp = maxi(1, int(round(float(u.max_hp) * GameManager.rt_player_hp_mult())))
		u.hp = u.max_hp
	u.died.connect(_on_unit_died)
	pool.append(u)

func _on_unit_died(u: RTUnit) -> void:
	_player_units.erase(u)
	_enemy_units.erase(u)

func _alive_structures(team: int) -> Array:
	return _structures.filter(func(s): return s["team"] == team and is_instance_valid(s["rt"]) and s["rt"].is_alive())

func _player_tc_alive() -> bool:
	for s in _structures:
		if s["team"] == 0 and s["type"] == "tc" and is_instance_valid(s["rt"]) and s["rt"].is_alive():
			return true
	return false

func _process(delta: float) -> void:
	if _paused or _ended:
		return
	_elapsed += delta

	# Passive income = base + alive player farms.
	var inc := 4.0
	for s in _alive_structures(0):
		inc += float(STRUCTURES[s["type"]].get("income", 0))
	_income = inc
	_gold += _income * delta

	# Production from every alive structure that produces (both sides). The enemy
	# Town Centre also trickles infantry so it keeps pressuring after buildings fall.
	for s in _structures:
		if not is_instance_valid(s["rt"]) or not s["rt"].is_alive():
			continue
		var def: Dictionary = STRUCTURES[s["type"]]
		var produces := String(def.get("produces", ""))
		var interval := float(def.get("interval", 0.0))
		if s["team"] == 1 and s["type"] == "tc":
			produces = "infantry"
			interval = maxf(3.0, 7.0 - _elapsed * 0.02) / _enemy_strength
		if produces == "":
			continue
		if s["team"] == 1:
			interval = interval / _enemy_strength
		s["timer"] = float(s["timer"]) - delta
		if s["timer"] <= 0.0:
			s["timer"] = interval
			_spawn_unit(produces, int(s["team"]), Vector2(s["home"]))

	var all_units: Array = []
	all_units.append_array(_player_units)
	all_units.append_array(_enemy_units)
	for s in _structures:
		if is_instance_valid(s["rt"]) and s["rt"].is_alive():
			all_units.append(s["rt"])

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.4
		_assign_orders(_player_units, _enemy_units, 1)
		_assign_orders(_enemy_units, _player_units, 0)

	for u: RTUnit in all_units:
		if is_instance_valid(u) and u.is_alive():
			u.tick(delta, all_units)
	# Keep structures pinned to their footprint (separation must not shove them).
	for s in _structures:
		if is_instance_valid(s["rt"]):
			s["rt"].position = Vector2(s["home"])

	_clean_dead()
	_refresh_ui()
	queue_redraw()
	_check_end()

# Units fight the nearest enemy regiment in range; otherwise they march on the
# nearest enemy structure (buildings on the way, then the HQ) — so winning means
# grinding through the whole base.
func _assign_orders(side: Array, foe_units: Array, foe_team: int) -> void:
	var structs := _alive_structures(foe_team)
	for u: RTUnit in side:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var nearest: RTUnit = null
		var best: float = INF
		for f: RTUnit in foe_units:
			if is_instance_valid(f) and f.is_alive():
				var d: float = u.position.distance_to(f.position)
				if d > 240.0:
					continue   # only engage foes within reach
				var wounded: float = 1.0 - float(f.hp) / float(maxi(1, f.max_hp))
				var score: float = d - wounded * 120.0   # concentrate fire on the hurt
				if score < best:
					best = score
					nearest = f
		if nearest != null:
			u.order_attack(nearest)
			continue
		var ts: RTUnit = null
		var tbest: float = INF
		for s in structs:
			var d2: float = u.position.distance_to(Vector2(s["home"]))
			if d2 < tbest:
				tbest = d2
				ts = s["rt"]
		if ts != null:
			u.order_attack(ts)

func _enemy_hq_alive() -> bool:
	for s in _structures:
		if s["team"] == 1 and s["type"] == "tc" and is_instance_valid(s["rt"]) and s["rt"].is_alive():
			return true
	return false

func _clean_dead() -> void:
	_player_units = _player_units.filter(func(u): return is_instance_valid(u) and u.is_alive())
	_enemy_units = _enemy_units.filter(func(u): return is_instance_valid(u) and u.is_alive())

func _check_end() -> void:
	if _ended:
		return
	if _alive_structures(1).is_empty():
		_conclude(true)
	elif not _player_tc_alive():
		_conclude(false)

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
			else "Your Town Centre has fallen — the run ends here."
	else:
		sub = "The enemy base is rubble." if win else "Your Town Centre has fallen."
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
		GameManager.pending_upgrade_reward = true
		if elite:
			_campaign_relic = GameManager.grant_random_relic()
		GameManager.save_run()
	else:
		GameManager.clear_run()

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _help_overlay != null:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_H, KEY_ESCAPE]:
			_toggle_help()
		return
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
			KEY_H:
				_toggle_help()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.y > FIELD_RECT.position.y:
			_try_build(event.position)

func _toggle_help() -> void:
	if _help_overlay != null:
		_help_overlay.queue_free()
		_help_overlay = null
		return
	_help_overlay = UITheme.help_overlay("Base Building — Help", HELP_BODY, _toggle_help)
	_ui.add_child(_help_overlay)

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
	draw_rect(Rect2(FIELD_RECT.position, Vector2(PLAYER_BUILD_MAX_X - FIELD_RECT.position.x, FIELD_RECT.size.y)),
		Color(0.18, 0.24, 0.30, 0.22))
	draw_rect(Rect2(Vector2(ENEMY_BUILD_MIN_X, FIELD_RECT.position.y), Vector2(FIELD_RECT.end.x - ENEMY_BUILD_MIN_X, FIELD_RECT.size.y)),
		Color(0.30, 0.18, 0.18, 0.20))
	# Health pip under each living structure.
	for s in _structures:
		if not is_instance_valid(s["rt"]) or not s["rt"].is_alive():
			continue
		var rt: RTUnit = s["rt"]
		var big: bool = s["type"] == "tc"
		var w: float = 64.0 if big else 42.0
		var home: Vector2 = Vector2(s["home"])
		var frac: float = clampf(float(rt.hp) / float(rt.max_hp), 0.0, 1.0)
		var top := home + Vector2(-w * 0.5, (44.0 if big else 30.0))
		draw_rect(Rect2(top, Vector2(w, 5.0)), Color(0.12, 0.12, 0.14))
		draw_rect(Rect2(top, Vector2(w * frac, 5.0)),
			Color(0.30, 0.85, 0.30) if frac > 0.3 else Color(0.9, 0.3, 0.3))
