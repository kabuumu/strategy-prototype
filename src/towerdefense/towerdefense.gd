extends Node2D

# Tower-defence skirmish — a self-contained battle mode reached from the title.
# Waves of enemy regiments march from the right toward your keep on the left;
# you spend gold to plant defending regiments along the lane. Defenders hold
# their ground and auto-fire on anything in range (RTUnit's idle stance); the
# enemy either smashes through a blocker or leaks to the keep and damages it.
# Survive every wave to win; the keep falling ends the run.
#
# Two entry points: a standalone skirmish from the title (no campaign state), or
# a campaign battle (battle_mode "td", GameManager.pending_td) where your roster
# auto-deploys as the starting defenders and the result reports back to the run.

const UITheme := preload("res://src/ui/ui_theme.gd")
const RTUnit := preload("res://src/rtbattle/rt_unit.gd")

# Lane the enemies walk down (centre line); buildable ground is everything in
# the field rect that isn't on the lane itself.
const FIELD_RECT: Rect2 = Rect2(40.0, 96.0, 1200.0, 540.0)
const LANE_Y: float = 366.0
const LANE_HALF: float = 52.0           # half-height of the marching corridor
const KEEP_X: float = 96.0              # enemies that pass this hit the keep
const SPAWN_X: float = 1200.0

const START_GOLD: int = 90
const START_KEEP_HP: int = 20
const ENEMY_RETARGET: float = 0.3

# Defenders the player can plant. Reuse the unit sprites; stats are tuned for a
# stationary "tower" role (no move speed needed — they hold ground).
const DEFENDER_TYPES: Dictionary = {
	"archer": {
		"name": "Archers", "sprite_key": "archer", "cost": 30,
		"soldier_count": 6, "hp_per_soldier": 12, "damage_per_attack": 9,
		"attack_cooldown": 1.1, "attack_range_px": 210.0, "move_speed_px": 0.0,
	},
	"soldier": {
		"name": "Infantry", "sprite_key": "soldier", "cost": 25,
		"soldier_count": 9, "hp_per_soldier": 18, "damage_per_attack": 9,
		"attack_cooldown": 1.0, "attack_range_px": 64.0, "move_speed_px": 0.0,
	},
	"mage": {
		"name": "Battlemages", "sprite_key": "pyromancer", "cost": 55,
		"soldier_count": 7, "hp_per_soldier": 14, "damage_per_attack": 17,
		"attack_cooldown": 1.4, "attack_range_px": 240.0, "move_speed_px": 0.0,
	},
	"guardian": {
		"name": "Guardians", "sprite_key": "juggernaut", "cost": 50,
		"soldier_count": 12, "hp_per_soldier": 30, "damage_per_attack": 12,
		"attack_cooldown": 1.2, "attack_range_px": 60.0, "move_speed_px": 0.0,
	},
}

# Enemy archetypes (they march, and fight blockers in the way).
const ENEMY_TYPES: Dictionary = {
	"runner":   {"name": "Raiders", "sprite_key": "scout", "bounty": 8,
		"soldier_count": 6, "hp_per_soldier": 12, "damage_per_attack": 8,
		"attack_cooldown": 0.9, "attack_range_px": 56.0, "move_speed_px": 64.0},
	"soldier":  {"name": "Warband", "sprite_key": "soldier", "bounty": 10,
		"soldier_count": 9, "hp_per_soldier": 18, "damage_per_attack": 9,
		"attack_cooldown": 1.0, "attack_range_px": 58.0, "move_speed_px": 42.0},
	"brute":    {"name": "Ogres", "sprite_key": "juggernaut", "bounty": 18,
		"soldier_count": 12, "hp_per_soldier": 30, "damage_per_attack": 14,
		"attack_cooldown": 1.2, "attack_range_px": 56.0, "move_speed_px": 32.0},
	"warlord":  {"name": "Warlord's Host", "sprite_key": "warlord", "bounty": 40,
		"soldier_count": 18, "hp_per_soldier": 26, "damage_per_attack": 16,
		"attack_cooldown": 1.0, "attack_range_px": 58.0, "move_speed_px": 36.0},
}

# Wave script: each wave is a list of [enemy_id, count] spawned in sequence.
const WAVES: Array = [
	[["runner", 4]],
	[["soldier", 4], ["runner", 3]],
	[["soldier", 5], ["brute", 1]],
	[["runner", 8], ["brute", 2]],
	[["brute", 4], ["soldier", 4]],
	[["soldier", 6], ["brute", 3], ["runner", 6]],
	[["warlord", 1], ["brute", 4], ["soldier", 6]],
]

var _gold: int = START_GOLD
var _keep_hp: int = START_KEEP_HP
var _wave_index: int = 0           # next wave to launch
var _wave_active: bool = false
var _paused: bool = false
var _ended: bool = false
var _won: bool = false

var _enemies: Array = []           # Array[RTUnit]
var _defenders: Array = []         # Array[RTUnit]
var _spawn_queue: Array = []       # pending [enemy_id] this wave
var _spawn_timer: float = 0.0
var _retarget_timer: float = 0.0
var _selected_type: String = "archer"
var _waves: Array = []             # active wave script (WAVES, or campaign-built)

# --- Campaign integration (battle_mode "td") -------------------------------
# Launched from the campaign map: your roster auto-deploys as the initial
# defenders, waves scale with the tier, and the result reports back to
# GameManager (survivors carried, gold + elite relic) like the other modes.
const CAMPAIGN_TD_MAP: Dictionary = {
	"soldier": "soldier", "archer": "archer", "scout": "soldier", "healer": "guardian",
	"knight": "guardian", "mage": "mage", "guardian": "guardian",
	"warlord": "guardian", "pyromancer": "mage", "juggernaut": "guardian",
}
var _campaign: bool = false
var _campaign_lost: bool = false
var _campaign_relic: String = ""
var _campaign_reward_gold: int = 0

var _ui: CanvasLayer
var _gold_label: Label
var _keep_label: Label
var _wave_label: Label
var _status_label: Label
var _settings_overlay: Control = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	set_process_unhandled_input(true)
	_waves = WAVES.duplicate(true)
	if GameManager.pending_td:
		GameManager.pending_td = false
		_campaign = true
		_setup_campaign()
	_build_ui()
	_refresh_ui()
	queue_redraw()

# Campaign setup — roster becomes the starting defenders, waves scale to tier.
func _setup_campaign() -> void:
	var tier: int = GameManager.pending_battle_tier
	var elite: bool = GameManager.pending_battle_elite
	_keep_hp = START_KEEP_HP + tier * 2
	_gold = 50 + tier * 15
	_waves = _build_campaign_waves(tier, elite)
	var roster: Array = GameManager.player_roster
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var dtype: String = String(CAMPAIGN_TD_MAP.get(String(entry["type"]), "soldier"))
		var side: float = -1.0 if (i % 2 == 0) else 1.0
		var rank: int = i / 2
		var y: float = clampf(LANE_Y + side * (LANE_HALF + 48.0 + rank * 64.0),
			FIELD_RECT.position.y + 30.0, FIELD_RECT.end.y - 30.0)
		var x: float = 300.0 + float(i % 2) * 64.0
		var u := RTUnit.new()
		add_child(u)
		u.setup(dtype, 0, Vector2(x, y), DEFENDER_TYPES[dtype])
		u.clear_order()
		u.set_meta("roster_entry", entry)
		_defenders.append(u)

func _build_campaign_waves(tier: int, elite: bool) -> Array:
	var n: int = 3 + tier
	var waves: Array = []
	for w in range(n):
		var wave: Array = [["runner", 2 + w]]
		if w >= 1:
			wave.append(["soldier", 2 + w])
		if tier >= 2 and w >= 2:
			wave.append(["brute", 1 + w / 2])
		waves.append(wave)
	if (elite or tier >= GameManager.MAP_TIERS - 1) and not waves.is_empty():
		waves[waves.size() - 1].append(["warlord", 1])
	return waves

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

	_ui.add_child(UITheme.label("TOWER DEFENCE — hold the keep", 22, UITheme.GOLD, Vector2(20.0, 10.0), Vector2(460.0, 30.0)))
	_keep_label = UITheme.label("", 17, Color(0.95, 0.55, 0.55), Vector2(20.0, 44.0), Vector2(220.0, 24.0))
	_ui.add_child(_keep_label)
	_gold_label = UITheme.label("", 17, UITheme.GOLD, Vector2(250.0, 44.0), Vector2(180.0, 24.0))
	_ui.add_child(_gold_label)
	_wave_label = UITheme.label("", 17, UITheme.TEXT, Vector2(430.0, 44.0), Vector2(240.0, 24.0))
	_ui.add_child(_wave_label)

	# Defender picker — one button per type with its cost.
	var x := 470.0
	for id: String in DEFENDER_TYPES:
		var d: Dictionary = DEFENDER_TYPES[id]
		_ui.add_child(UITheme.button("%s\n%dg" % [String(d["name"]), int(d["cost"])],
			Vector2(x, 8.0), Vector2(104.0, 46.0), Color(0.22, 0.30, 0.42),
			_on_pick_type.bind(id), 13))
		x += 110.0

	_ui.add_child(UITheme.button("Start Wave", Vector2(x + 6.0, 8.0), Vector2(120.0, 46.0), UITheme.GREEN, _on_start_wave, 15))
	_ui.add_child(UITheme.button("Menu", Vector2(1150.0, 8.0), Vector2(104.0, 40.0), UITheme.RED, _toggle_settings_menu))

	_status_label = UITheme.label("Pick a defender, click buildable ground to place it, then Start Wave.",
		14, UITheme.TEXT_MUTED, Vector2(20.0, 64.0), Vector2(900.0, 20.0))
	_ui.add_child(_status_label)

func _refresh_ui() -> void:
	_keep_label.text = "Keep HP: %d" % _keep_hp
	_gold_label.text = "Gold: %d" % _gold
	var total: int = _waves.size()
	if _ended:
		_wave_label.text = "VICTORY" if _won else "DEFEAT"
	elif _wave_active:
		_wave_label.text = "Wave %d / %d — incoming!" % [_wave_index, total]
	else:
		_wave_label.text = "Wave %d / %d ready" % [_wave_index + 1, total] if _wave_index < total else "All waves cleared"

func _on_pick_type(id: String) -> void:
	_selected_type = id
	_status_label.text = "Selected %s (%dg). Click buildable ground to deploy." % [
		String(DEFENDER_TYPES[id]["name"]), int(DEFENDER_TYPES[id]["cost"])]

func _on_start_wave() -> void:
	if _ended or _wave_active or _wave_index >= _waves.size():
		return
	_wave_active = true
	_spawn_queue.clear()
	for entry in _waves[_wave_index]:
		var id: String = String(entry[0])
		for _i in range(int(entry[1])):
			_spawn_queue.append(id)
	_spawn_queue.shuffle()
	_spawn_timer = 0.0
	_refresh_ui()

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
func _is_buildable(pos: Vector2) -> bool:
	if not FIELD_RECT.has_point(pos):
		return false
	if absf(pos.y - LANE_Y) < LANE_HALF:
		return false               # can't build on the marching lane
	if pos.x < KEEP_X + 40.0:
		return false               # keep no-build zone
	return true

func _try_place(pos: Vector2) -> void:
	if _ended:
		return
	var d: Dictionary = DEFENDER_TYPES[_selected_type]
	var cost: int = int(d["cost"])
	if _gold < cost:
		_status_label.text = "Not enough gold for %s (need %d)." % [String(d["name"]), cost]
		return
	if not _is_buildable(pos):
		_status_label.text = "Can't build there — keep clear of the lane and the keep."
		return
	# Don't stack defenders on top of each other.
	for u: RTUnit in _defenders:
		if is_instance_valid(u) and u.position.distance_to(pos) < u.radius + 20.0:
			_status_label.text = "Too close to another defender."
			return
	_gold -= cost
	var u := RTUnit.new()
	add_child(u)
	u.setup(_selected_type, 0, pos, d)
	u.clear_order()                # hold ground; idle stance auto-fires in range
	_defenders.append(u)
	Sfx.play("gold")
	_refresh_ui()

# ---------------------------------------------------------------------------
# Spawning + simulation
# ---------------------------------------------------------------------------
func _spawn_enemy(id: String) -> void:
	var stats: Dictionary = ENEMY_TYPES.get(id, ENEMY_TYPES["soldier"])
	var u := RTUnit.new()
	add_child(u)
	var y := LANE_Y + _rng.randf_range(-LANE_HALF * 0.5, LANE_HALF * 0.5)
	u.setup(id, 1, Vector2(SPAWN_X, y), stats)
	u.set_meta("bounty", int(stats.get("bounty", 8)))
	u.order_move(Vector2(KEEP_X, LANE_Y))
	u.died.connect(_on_enemy_died)
	_enemies.append(u)

func _on_enemy_died(u: RTUnit) -> void:
	if is_instance_valid(u) and u.has_meta("bounty"):
		_gold += int(u.get_meta("bounty"))
	_enemies.erase(u)
	Sfx.play("death", -12.0)
	_refresh_ui()

func _process(delta: float) -> void:
	if _paused or _ended:
		return

	# Trickle the current wave's enemies onto the field.
	if _wave_active and not _spawn_queue.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_enemy(String(_spawn_queue.pop_front()))
			_spawn_timer = 0.7

	var all_units: Array = []
	all_units.append_array(_defenders)
	all_units.append_array(_enemies)

	# Enemies periodically decide: fight a defender that's blocking, else march.
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = ENEMY_RETARGET
		for e: RTUnit in _enemies:
			if not is_instance_valid(e) or not e.is_alive():
				continue
			var blocker := _nearest_defender_in_range(e)
			if blocker != null:
				e.order_attack(blocker)
			else:
				e.order_move(Vector2(KEEP_X, LANE_Y))

	# Tick everyone (defenders auto-engage via idle stance).
	for u: RTUnit in all_units:
		if is_instance_valid(u) and u.is_alive():
			u.tick(delta, all_units)

	_check_leaks()
	_clean_dead()
	_check_wave_end()
	queue_redraw()

func _nearest_defender_in_range(e: RTUnit) -> RTUnit:
	var best: RTUnit = null
	var best_d: float = e.attack_range_px + 24.0
	for d: RTUnit in _defenders:
		if not is_instance_valid(d) or not d.is_alive():
			continue
		var dist: float = e.position.distance_to(d.position)
		if dist < best_d:
			best = d
			best_d = dist
	return best

# Enemies that reach the keep damage it by their remaining strength, then vanish.
func _check_leaks() -> void:
	for e: RTUnit in _enemies.duplicate():
		if is_instance_valid(e) and e.is_alive() and e.position.x <= KEEP_X:
			var dmg: int = maxi(1, e.alive_soldier_count())
			_keep_hp = maxi(0, _keep_hp - dmg)
			_status_label.text = "%s breached the keep! −%d HP" % [e.unit_name, dmg]
			e.died.disconnect(_on_enemy_died)
			_enemies.erase(e)
			e.queue_free()
			if _keep_hp <= 0:
				_conclude(false)
				return
	_refresh_ui()

func _clean_dead() -> void:
	_enemies = _enemies.filter(func(u): return is_instance_valid(u) and u.is_alive())
	_defenders = _defenders.filter(func(u): return is_instance_valid(u) and u.is_alive())

func _check_wave_end() -> void:
	if not _wave_active or _ended:
		return
	if _spawn_queue.is_empty() and _enemies.is_empty():
		_wave_active = false
		_wave_index += 1
		if _wave_index >= _waves.size():
			_conclude(true)
			return
		var bonus: int = 20 + _wave_index * 6
		_gold += bonus
		_status_label.text = "Wave cleared! +%d gold. Reinforce, then Start Wave." % bonus
		_refresh_ui()

func _conclude(win: bool) -> void:
	_ended = true
	_won = win
	if _campaign:
		_conclude_campaign(win)
	_status_label.text = "The keep held — victory!" if win else "The keep has fallen."
	Sfx.play("win" if win else "lose", -6.0)
	_refresh_ui()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	UITheme.panel(root, Vector2(480.0, 244.0), Vector2(320.0, 240.0))
	root.add_child(UITheme.label("VICTORY" if win else "DEFEAT", 40,
		UITheme.GOLD if win else UITheme.RED, Vector2(556.0, 266.0)))
	var sub: String
	if _campaign:
		sub = ("+%d gold%s" % [_campaign_reward_gold,
			"   ·   Relic: %s" % String(GameManager.RELICS[_campaign_relic]["name"]) if _campaign_relic != "" else ""]) if win \
			else "Your army was wiped out — the run ends here."
	else:
		sub = "You cleared every wave." if win else "The keep was overrun."
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

# Write the campaign result back to GameManager (survivors, gold, relic, save).
func _conclude_campaign(win: bool) -> void:
	var tier: int = GameManager.pending_battle_tier
	var elite: bool = GameManager.pending_battle_elite
	_campaign_lost = not win
	_campaign_relic = ""
	_campaign_reward_gold = 0
	if win:
		var survivors: Array[Dictionary] = []
		for u: RTUnit in _defenders:
			if is_instance_valid(u) and u.is_alive() and u.has_meta("roster_entry"):
				survivors.append(u.get_meta("roster_entry"))
		# A keep that holds always saves at least your hardiest regiment.
		if survivors.is_empty() and not GameManager.player_roster.is_empty():
			survivors.append(GameManager.player_roster[0])
		GameManager.set_roster(survivors)
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
			KEY_ENTER, KEY_KP_ENTER:
				_on_start_wave()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.y > FIELD_RECT.position.y:
			_try_place(event.position)

func _toggle_settings_menu() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	_settings_overlay = UITheme.pause_menu(_toggle_settings_menu,
		func() -> void: get_tree().change_scene_to_file("res://src/title/title.tscn"))
	_ui.add_child(_settings_overlay)

# ---------------------------------------------------------------------------
# Draw — field, lane, keep, buildable hint
# ---------------------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color(0.07, 0.10, 0.07))
	draw_rect(FIELD_RECT, Color(0.13, 0.17, 0.12))
	# Marching lane
	var lane := Rect2(FIELD_RECT.position.x, LANE_Y - LANE_HALF, FIELD_RECT.size.x, LANE_HALF * 2.0)
	draw_rect(lane, Color(0.22, 0.19, 0.14))
	draw_line(Vector2(FIELD_RECT.position.x, LANE_Y), Vector2(FIELD_RECT.end.x, LANE_Y),
		Color(0.40, 0.34, 0.22, 0.7), 2.0)
	# Keep
	var keep := Rect2(FIELD_RECT.position.x, LANE_Y - 70.0, KEEP_X - FIELD_RECT.position.x + 6.0, 140.0)
	draw_rect(keep, Color(0.30, 0.34, 0.45))
	draw_rect(keep, Color(0.55, 0.60, 0.75), false, 3.0)
	var frac: float = clampf(float(_keep_hp) / float(START_KEEP_HP), 0.0, 1.0)
	draw_rect(Rect2(keep.position + Vector2(8.0, 8.0), Vector2((keep.size.x - 16.0) * frac, 8.0)),
		Color(0.85, 0.30, 0.30))
	# Spawn marker
	draw_circle(Vector2(SPAWN_X, LANE_Y), 10.0, Color(0.85, 0.30, 0.30, 0.8))
