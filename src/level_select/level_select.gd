extends Node2D

const UITheme := preload("res://src/ui/ui_theme.gd")

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const NODE_R: float = 26.0
const SIDE_X: float = 880.0            # right-hand HUD panel starts here
# The overworld is one continuous horizontal world: tier 0 at the left, the boss
# far right. The hero avatar walks left->right, steering into forks to pick the
# next node. The world is wider than the play viewport (left of the HUD), so a
# horizontal camera (_cam_x) follows the avatar.
const PLAY_W: float = 858.0            # world viewport width (left of the HUD)
const PLAY_TOP: float = 96.0
const PLAY_BOTTOM: float = 688.0
const TIER_DX: float = 280.0           # horizontal gap between tiers
const MARGIN_X: float = 120.0          # world x of tier 0
const LANE_GAP: float = 104.0          # vertical gap between nodes in a tier
const WALK_SPEED: float = 165.0        # px/sec the avatar travels along an edge
const CENTER_Y: float = (PLAY_TOP + PLAY_BOTTOM) * 0.5

enum Nav { AT_NODE, TRAVELING }
var _nav: int = Nav.AT_NODE
var _at_start: bool = true             # true before any node is visited (virtual start)
var _cur_tier: int = 0                 # tier of the node the avatar stands on
var _cur_index: int = 0                # index within that tier
var _targets: Array = []               # reachable next nodes [{tier,index}]
var _sel: int = 0                      # selected target in _targets
var _travel_t: float = 0.0             # 0..1 progress along the current edge
var _step_t: float = 0.0               # footstep SFX accumulator while walking
var _travel_from: Vector2 = Vector2.ZERO
var _travel_to: Vector2 = Vector2.ZERO
var _travel_target: Dictionary = {}    # {tier,index} being walked to
var _avatar: Vector2 = Vector2.ZERO    # world position of the hero
var _cam_x: float = 0.0
var _world_w: float = 0.0
# Mouse/touch pan + click-vs-drag tracking (Spec C/E).
var _cam_user_x: float = -1.0          # >=0 = manual pan; -1 = follow the avatar
var _press_pos: Vector2 = Vector2.ZERO
var _press_active: bool = false
var _drag_panning: bool = false
var _hero_tex: Texture2D = null
var _edge_pickups: Array = []          # [{t,pos,kind,amount,taken}]
var _awaiting_resolve: bool = false    # arrived; waiting for a popup to close
var _leaving: bool = false             # a node handler is changing scene
var _encounter_pending: bool = false   # encounter popup open; resume travel on close

const TYPE_COLORS: Dictionary = {
	"battle":       Color(0.80, 0.28, 0.28),
	"elite_battle": Color(0.55, 0.10, 0.65),
	"gain_unit":    Color(0.25, 0.55, 0.95),
	"shop":         Color(0.85, 0.70, 0.20),
	"heal":         Color(0.20, 0.72, 0.35),
	"event":        Color(0.30, 0.72, 0.72),
	"treasure":     Color(0.90, 0.78, 0.30)
}
const TYPE_LABELS: Dictionary = {
	"battle":       "Battle",
	"elite_battle": "Elite!",
	"gain_unit":    "+Unit",
	"shop":         "Shop",
	"heal":         "Heal",
	"event":        "?",
	"treasure":     "Loot"
}
const TYPE_DESC: Dictionary = {
	"battle":       "Standard battle",
	"elite_battle": "Harder battle, tougher enemies",
	"gain_unit":    "Choose a new unit",
	"shop":         "Spend gold on heals and units",
	"heal":         "Heal all units to full",
	"event":        "A random encounter — a choice to make",
	"treasure":     "A free relic (or gold, if you own them all)"
}

# ---------------------------------------------------------------------------
var _roster_label: Label
var _gold_label: Label
var _relics_label: Label
var _depth_label: Label
var _hero_label: Label
var _node_detail_label: Label
var _popup: Control = null
var _settings_overlay: Control = null
var _inventory_popup: Control = null
var _shop_relic_offer: String = ""
var _pending_recruit_toast: Dictionary = {}


# ---------------------------------------------------------------------------
func _ready() -> void:
	Music.play("map")
	# Consume a pending duel result before the save block so a recruit won in the
	# auto-battler is persisted with this map visit. The toast waits until the UI
	# is built (below, after _refresh).
	if GameManager.duel_outcome != -1:
		var dwin := GameManager.duel_outcome == 1
		var dtype := GameManager.duel_recruit_type
		if dwin and dtype != "" and GameManager.UNIT_TYPES.has(dtype):
			GameManager.add_unit(dtype)
		GameManager.duel_outcome = -1
		GameManager.pending_duel = false
		GameManager.duel_recruit_type = ""
		_pending_recruit_toast = {"win": dwin, "type": dtype}
	_build_world()
	_anchor_to_current()
	_build_hud()
	# Checkpoint the run between battles so it can be resumed. Once the run is
	# over (boss cleared), drop the save instead.
	if GameManager.current_tier < GameManager.MAP_TIERS:
		GameManager.save_run()
	else:
		GameManager.clear_run()
	# Small hint that Esc opens the menu
	add_child(UITheme.label("Esc — Menu", 13, UITheme.TEXT_MUTED, Vector2(1150.0, 26.0), Vector2(110.0, 20.0)))
	_refresh()
	# Surface the duel result (recruited / declined) now that the HUD exists.
	if not _pending_recruit_toast.is_empty():
		var rt := _pending_recruit_toast
		_pending_recruit_toast = {}
		var rtype: String = String(rt.get("type", ""))
		if rtype != "" and GameManager.UNIT_TYPES.has(rtype):
			var rname: String = GameManager.UNIT_TYPES[rtype]["name"]
			if bool(rt.get("win", false)):
				_show_toast("%s joined your army!" % rname, GameManager.UNIT_TYPES[rtype]["color"])
			else:
				_show_toast("%s bested you and walked away." % rname, Color(0.7, 0.6, 0.5))
	# Offer any pending post-battle rewards (hero perk pick, then upgrade card).
	call_deferred("_show_pending_rewards")

# Chains the post-battle popups so a perk pick and an upgrade reward don't both
# try to grab _popup. The hero perk popup (if any) runs first and re-invokes
# this on close; the upgrade reward is always last.
func _show_pending_rewards() -> void:
	if _popup != null:
		return
	if GameManager.pending_hero_perk and GameManager.has_hero():
		GameManager.pending_hero_perk = false
		_show_hero_perk_popup()
		return
	if GameManager.pending_upgrade_reward and not GameManager.player_roster.is_empty() \
			and GameManager.current_tier < GameManager.MAP_TIERS:
		GameManager.pending_upgrade_reward = false
		_show_reward_popup()

# ---------------------------------------------------------------------------
# Hero level-up perk pick. Mirrors the upgrade reward popup's card layout.
# ---------------------------------------------------------------------------
func _show_hero_perk_popup() -> void:
	if _popup != null:
		return
	var choices := GameManager.random_hero_perk_choices(3)
	if choices.is_empty():
		call_deferred("_show_pending_rewards")
		return
	_popup = UITheme.panel(self, Vector2(220.0, 200.0), Vector2(840.0, 300.0),
		Color(0.08, 0.10, 0.14, 0.99), Color(0.45, 0.60, 0.85))
	_popup.add_child(UITheme.label("Hero Level %d! Choose a Perk" % GameManager.hero_level,
		26, Color(0.78, 0.90, 1.0), Vector2(28.0, 18.0), Vector2(784.0, 32.0)))
	_popup.add_child(UITheme.label("Pick a perk for your hero.",
		14, UITheme.TEXT_MUTED, Vector2(28.0, 54.0), Vector2(784.0, 22.0)))
	for i in range(choices.size()):
		var id: String = choices[i]
		var data: Dictionary = GameManager.HERO_PERKS[id]
		var btn := Button.new()
		btn.position = Vector2(40.0 + i * 260.0, 92.0)
		btn.size = Vector2(240.0, 120.0)
		btn.text = "%s\n\n%s" % [String(data["name"]), String(data["desc"])]
		btn.add_theme_font_size_override("font_size", 15)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var col := Color(0.20, 0.30, 0.45)
		btn.add_theme_stylebox_override("normal",  _circle_style(col, 8))
		btn.add_theme_stylebox_override("hover",   _circle_style(col.lightened(0.18), 8))
		btn.add_theme_stylebox_override("pressed", _circle_style(col.darkened(0.2), 8))
		btn.pressed.connect(_on_hero_perk_pick.bind(id))
		_popup.add_child(btn)
	var skip := UITheme.button("Skip", Vector2(360.0, 236.0), Vector2(200.0, 44.0),
		Color(0.30, 0.30, 0.34), _on_hero_perk_pick.bind(""))
	_popup.add_child(skip)

func _on_hero_perk_pick(id: String) -> void:
	if id != "":
		GameManager.grant_hero_perk(id)
	if _popup != null:
		_popup.queue_free()
		_popup = null
	GameManager.save_run()
	if id != "":
		var data: Dictionary = GameManager.HERO_PERKS[id]
		_show_toast("%s — %s" % [String(data["name"]), String(data["desc"])], Color(0.75, 0.9, 1.0))
	_refresh()
	call_deferred("_show_pending_rewards")

# ---------------------------------------------------------------------------
# Post-battle upgrade reward (parity with the hex battle's upgrade picker).
# Step 1: pick one of 3 upgrade cards. Step 2: assign it to a surviving unit.
# ---------------------------------------------------------------------------
func _show_reward_popup() -> void:
	if _popup != null:
		return
	_popup = UITheme.panel(self, Vector2(220.0, 200.0), Vector2(840.0, 300.0),
		Color(0.10, 0.12, 0.08, 0.99), Color(0.55, 0.70, 0.40))
	_popup.add_child(UITheme.label("Victory! Choose a Reward", 26, Color(0.95, 0.95, 0.65), Vector2(28.0, 18.0), Vector2(784.0, 32.0)))
	_popup.add_child(UITheme.label("Pick an upgrade card, then assign it to a surviving unit.",
		14, UITheme.TEXT_MUTED, Vector2(28.0, 54.0), Vector2(784.0, 22.0)))
	var choices := GameManager.random_upgrade_choices(3)
	for i in range(choices.size()):
		var id: String = choices[i]
		var data: Dictionary = GameManager.UPGRADE_TYPES[id]
		var btn := Button.new()
		btn.position = Vector2(40.0 + i * 260.0, 92.0)
		btn.size = Vector2(240.0, 120.0)
		btn.text = "%s\n\n%s" % [String(data["name"]), String(data["desc"])]
		btn.add_theme_font_size_override("font_size", 15)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var col: Color = data["color"].darkened(0.35)
		btn.add_theme_stylebox_override("normal",  _circle_style(col, 8))
		btn.add_theme_stylebox_override("hover",   _circle_style(col.lightened(0.18), 8))
		btn.add_theme_stylebox_override("pressed", _circle_style(col.darkened(0.2), 8))
		btn.pressed.connect(_on_reward_card.bind(id))
		_popup.add_child(btn)
	var skip := UITheme.button("Skip", Vector2(360.0, 236.0), Vector2(200.0, 44.0), Color(0.30, 0.30, 0.34), _close_reward)
	_popup.add_child(skip)

func _on_reward_card(upgrade_id: String) -> void:
	for c in _popup.get_children():
		c.queue_free()
	var data: Dictionary = GameManager.UPGRADE_TYPES[upgrade_id]
	_popup.add_child(UITheme.label("Assign '%s' to which unit?" % String(data["name"]),
		22, Color(0.95, 0.95, 0.65), Vector2(28.0, 18.0), Vector2(784.0, 30.0)))
	var roster := GameManager.player_roster
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var udata: Dictionary = GameManager.UNIT_TYPES[entry["type"]]
		var col := i % 5
		var row := i / 5
		var btn := Button.new()
		btn.position = Vector2(36.0 + col * 158.0, 70.0 + row * 86.0)
		btn.size = Vector2(150.0, 78.0)
		btn.text = "%s\nHP %d" % [String(udata["name"]), int(entry["hp"])]
		btn.add_theme_font_size_override("font_size", 13)
		var bc: Color = udata["color"].darkened(0.2)
		btn.add_theme_stylebox_override("normal",  _circle_style(bc, 8))
		btn.add_theme_stylebox_override("hover",   _circle_style(bc.lightened(0.18), 8))
		btn.pressed.connect(_on_reward_assign.bind(i, upgrade_id))
		_popup.add_child(btn)

func _on_reward_assign(roster_index: int, upgrade_id: String) -> void:
	GameManager.apply_upgrade(roster_index, upgrade_id)
	var nm: String = GameManager.UPGRADE_TYPES[upgrade_id]["name"]
	_close_reward()
	GameManager.save_run()
	_show_toast("%s applied!" % nm, Color(0.65, 0.95, 0.55))

func _close_reward() -> void:
	if _popup != null:
		_popup.queue_free()
		_popup = null
	_refresh()

func _on_exit_to_menu() -> void:
	if GameManager.current_tier < GameManager.MAP_TIERS:
		GameManager.save_run()   # keep the run resumable
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _unhandled_input(event: InputEvent) -> void:
	# Mouse/touch: drag pans the camera; a press-release without a drag clicks a
	# reachable node (main map or minimap) to travel there (Spec C/E). Works on
	# touch via emulate_mouse_from_touch. Keyboard nav stays unchanged.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
			_press_active = true
			_drag_panning = false
		else:
			if _press_active and not _drag_panning:
				if not _try_minimap_travel(event.position):
					_try_click_travel(event.position)
			_press_active = false
		return
	if event is InputEventMouseMotion and _press_active:
		if not _drag_panning and event.position.distance_to(_press_pos) > 8.0:
			_drag_panning = true
			_cam_user_x = _cam_x
		if _drag_panning:
			_cam_user_x = clampf(_cam_user_x - event.relative.x, 0.0, maxf(0.0, _world_w - PLAY_W))
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	_cam_user_x = -1.0   # keyboard interaction recenters the follow camera
	# ↑/↓ (W/S) choose which fork to take while standing at a node.
	if not _input_blocked() and _nav == Nav.AT_NODE:
		if event.keycode == KEY_UP or event.keycode == KEY_W:
			_select_target(-1); return
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			_select_target(1); return
	if event.keycode == KEY_I:
		if _popup == null:
			_toggle_inventory()
		return
	if event.keycode == KEY_ESCAPE:
		# Esc closes the inventory or a shop/unit popup first; else the settings menu.
		if _inventory_popup != null:
			_toggle_inventory()
		elif _popup != null:
			return
		else:
			_toggle_settings_menu()

# Click/tap a reachable node to travel to it (Spec C). Hit-tests the cursor
# against each reachable target's on-screen position; on a hit, selects it and
# begins travel down that edge (reusing the keyboard travel machinery).
func _try_click_travel(screen_pos: Vector2) -> void:
	if _input_blocked() or _nav != Nav.AT_NODE:
		return
	for k in range(_targets.size()):
		var tgt: Dictionary = _targets[k]
		var sp: Vector2 = _w2s(_node_world_pos(int(tgt["tier"]), int(tgt["index"])))
		if screen_pos.distance_to(sp) <= NODE_R + 8.0:
			_sel = k
			_begin_travel()
			return

# Click/tap a reachable node on the bottom-left minimap to travel (Spec C).
# Returns true if the click was inside the minimap (consumed), so the main-map
# hit-test is skipped.
func _try_minimap_travel(pos: Vector2) -> bool:
	var rect := Rect2(14.0, 498.0, 300.0, 184.0)
	if not rect.has_point(pos):
		return false
	if _input_blocked() or _nav != Nav.AT_NODE:
		return true
	var last: int = maxi(1, GameManager.MAP_TIERS - 1)
	var inner_x: float = rect.position.x + 20.0
	var inner_w: float = rect.size.x - 32.0
	var cy: float = rect.position.y + rect.size.y * 0.58
	var lane: float = minf(16.0, (rect.size.y * 0.5 - 14.0) / 2.5)
	for k in range(_targets.size()):
		var tgt: Dictionary = _targets[k]
		var tier: int = int(tgt["tier"])
		var idx: int = int(tgt["index"])
		var count: int = GameManager.map_data[tier].size()
		var mp := Vector2(inner_x + (float(tier) / float(last)) * inner_w,
				cy + (float(idx) - float(count - 1) * 0.5) * lane)
		if pos.distance_to(mp) <= 8.0:
			_sel = k
			_begin_travel()
			return true
	return true

# Inventory & status overlay — explains every owned relic and affliction.
func _toggle_inventory() -> void:
	if _inventory_popup != null:
		_inventory_popup.queue_free()
		_inventory_popup = null
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 220
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	UITheme.panel(root, Vector2(330.0, 110.0), Vector2(620.0, 500.0), Color(0.08, 0.09, 0.14, 0.99), Color(0.45, 0.46, 0.62))
	root.add_child(UITheme.label("Inventory & Status", 26, UITheme.GOLD, Vector2(360.0, 128.0), Vector2(560.0, 32.0)))
	root.add_child(UITheme.label("Gold: %d" % GameManager.gold, 15, UITheme.GOLD, Vector2(770.0, 134.0), Vector2(160.0, 24.0)))
	var y: float = 174.0
	root.add_child(UITheme.label("RELICS (passive boons)", 14, Color(0.82, 0.86, 0.55), Vector2(360.0, y), Vector2(560.0, 22.0)))
	y += 26.0
	if GameManager.relics.is_empty():
		root.add_child(UITheme.label("  — none yet —", 13, UITheme.TEXT_MUTED, Vector2(372.0, y), Vector2(548.0, 20.0)))
		y += 26.0
	else:
		for id: String in GameManager.relics:
			var r: Dictionary = GameManager.RELICS[id]
			root.add_child(UITheme.label("%s — %s" % [String(r["name"]), String(r["desc"])],
				13, Color(0.85, 0.92, 0.98), Vector2(372.0, y), Vector2(548.0, 34.0)))
			y += 32.0
	y += 14.0
	root.add_child(UITheme.label("AFFLICTIONS (curses)", 14, Color(0.92, 0.52, 0.52), Vector2(360.0, y), Vector2(560.0, 22.0)))
	y += 26.0
	if GameManager.curses.is_empty():
		root.add_child(UITheme.label("  — none —", 13, UITheme.TEXT_MUTED, Vector2(372.0, y), Vector2(548.0, 20.0)))
		y += 26.0
	else:
		for id2: String in GameManager.curses:
			var c: Dictionary = GameManager.CURSES[id2]
			root.add_child(UITheme.label("%s — %s" % [String(c["name"]), String(c["desc"])],
				13, Color(0.98, 0.78, 0.78), Vector2(372.0, y), Vector2(548.0, 34.0)))
			y += 32.0
	y += 12.0
	root.add_child(UITheme.label("ARMY SYNERGIES (composition)", 14, Color(0.55, 0.85, 0.90), Vector2(360.0, y), Vector2(560.0, 22.0)))
	y += 26.0
	var syn := GameManager.army_synergies()
	if syn.is_empty():
		root.add_child(UITheme.label("  — none active —", 13, UITheme.TEXT_MUTED, Vector2(372.0, y), Vector2(548.0, 20.0)))
	else:
		for sid: String in syn:
			var sd: Dictionary = GameManager.SYNERGIES[sid]
			root.add_child(UITheme.label("%s — %s" % [String(sd["name"]), String(sd["desc"])],
				13, Color(0.75, 0.92, 0.96), Vector2(372.0, y), Vector2(548.0, 32.0)))
			y += 30.0
	root.add_child(UITheme.button("Close  [I / Esc]", Vector2(530.0, 556.0), Vector2(220.0, 42.0),
		Color(0.30, 0.32, 0.44), _toggle_inventory))
	add_child(root)
	_inventory_popup = root

# Pause/settings overlay opened with Esc.
func _toggle_settings_menu() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 200
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks to the map
	root.add_child(dim)
	UITheme.panel(root, Vector2(490.0, 230.0), Vector2(300.0, 260.0))
	root.add_child(UITheme.label("Menu", 26, UITheme.GOLD, Vector2(610.0, 250.0)))
	root.add_child(UITheme.button("Resume", Vector2(520.0, 300.0), Vector2(240.0, 50.0),
		Color(0.20, 0.45, 0.30), _toggle_settings_menu))
	root.add_child(UITheme.button("Exit to Main Menu", Vector2(520.0, 360.0), Vector2(240.0, 50.0),
		Color(0.45, 0.30, 0.34), _on_exit_to_menu))
	root.add_child(UITheme.label("Your run is saved — Continue resumes it.", 12,
		UITheme.TEXT_MUTED, Vector2(516.0, 428.0), Vector2(250.0, 36.0)))
	add_child(root)
	_settings_overlay = root

var _pulse_t: float = 0.0

func _process(delta: float) -> void:
	_pulse_t += delta
	_update_camera(delta)
	if not _input_blocked():
		if _nav == Nav.AT_NODE:
			if not _targets.is_empty() and (Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)):
				_begin_travel()
		elif _nav == Nav.TRAVELING:
			_update_travel(delta)
	# Once an arrived node's popup closes, set up the next fork.
	if _awaiting_resolve and _popup == null and not _leaving:
		_awaiting_resolve = false
		_anchor_to_current()
		_refresh()
	queue_redraw()

func _input_blocked() -> bool:
	# Note: _encounter_pending is deliberately NOT here — an open encounter popup
	# already blocks via _popup, and _update_travel must run once it closes to
	# clear the flag and resume walking.
	return _popup != null or _settings_overlay != null or _inventory_popup != null \
		or _awaiting_resolve or _leaving

# Camera follows the avatar horizontally, clamped to the world.
func _update_camera(delta: float) -> void:
	if _cam_user_x >= 0.0:   # manual drag-pan overrides the follow camera
		_cam_x = clampf(_cam_user_x, 0.0, maxf(0.0, _world_w - PLAY_W))
		return
	var want: float = clampf(_avatar.x - PLAY_W * 0.42, 0.0, maxf(0.0, _world_w - PLAY_W))
	_cam_x = lerp(_cam_x, want, clampf(delta * 6.0, 0.0, 1.0))

# ---------------------------------------------------------------------------
# Drawing — one continuous horizontal world, offset by the camera.
# ---------------------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), UITheme.BG)
	# Ground band the avatar walks above (screen-space, decorative).
	draw_rect(Rect2(0.0, PLAY_BOTTOM - 4.0, PLAY_W, 720.0 - PLAY_BOTTOM), Color(0.10, 0.13, 0.10, 0.6))

	var font := ThemeDB.fallback_font
	var sel_target: Dictionary = _targets[_sel] if (_nav == Nav.AT_NODE and _sel < _targets.size()) else {}

	# Connection paths.
	for tier in range(GameManager.MAP_TIERS - 1):
		for i in range(GameManager.map_data[tier].size()):
			var from := _w2s(_node_world_pos(tier, i))
			for j in GameManager.map_data[tier][i]["connections"]:
				var to := _w2s(_node_world_pos(tier + 1, int(j)))
				if (from.x < -40.0 and to.x < -40.0) or (from.x > PLAY_W + 40.0 and to.x > PLAY_W + 40.0):
					continue
				var lit: bool = not _at_start and tier == _cur_tier and i == _cur_index \
					and not sel_target.is_empty() and int(sel_target["tier"]) == tier + 1 and int(sel_target["index"]) == int(j)
				draw_line(from, to, Color(0.95, 0.85, 0.40, 0.9) if lit else Color(0.34, 0.36, 0.48, 0.55), 3.0 if lit else 2.0)

	# Path from the (virtual) start node to its targets.
	if _at_start:
		var sfrom := _w2s(_standing_pos())
		for tgt: Dictionary in _targets:
			var sto := _w2s(_node_world_pos(int(tgt["tier"]), int(tgt["index"])))
			var lit2: bool = not sel_target.is_empty() and tgt == sel_target
			draw_line(sfrom, sto, Color(0.95, 0.85, 0.40, 0.9) if lit2 else Color(0.34, 0.36, 0.48, 0.55), 3.0 if lit2 else 2.0)

	# Pickups on the current edge.
	for p: Dictionary in _edge_pickups:
		if bool(p.get("taken", false)):
			continue
		var pp := _w2s(p["pos"])
		if pp.x < -20.0 or pp.x > PLAY_W + 20.0:
			continue
		var pc: Color = Color(0.95, 0.82, 0.30) if String(p["kind"]) == "gold" else Color(0.62, 0.72, 0.98)
		draw_circle(pp, 8.0, pc)
		draw_arc(pp, 8.0, 0.0, TAU, 20, pc.darkened(0.4), 1.5)

	# Nodes.
	var reach_idx: Array = GameManager.get_reachable_indices()
	var pulse: float = 0.5 + 0.5 * sin(_pulse_t * 4.0)
	for tier in range(GameManager.MAP_TIERS):
		for i in range(GameManager.map_data[tier].size()):
			var c := _w2s(_node_world_pos(tier, i))
			if c.x < -NODE_R or c.x > PLAY_W + NODE_R:
				continue
			var nd: Dictionary = GameManager.map_data[tier][i]
			var col: Color = TYPE_COLORS.get(nd["type"], Color.GRAY)
			var is_target: bool = tier == GameManager.current_tier and i in reach_idx
			if bool(nd.get("visited", false)):
				col = col.darkened(0.55)
			elif not is_target:
				col = col.darkened(0.3)
			draw_circle(c, NODE_R, col)
			draw_arc(c, NODE_R, 0.0, TAU, 32, col.lightened(0.3), 2.0)
			if is_target:
				draw_arc(c, NODE_R + 5.0 + pulse * 4.0, 0.0, TAU, 36, Color(0.95, 0.85, 0.35, 0.35 + pulse * 0.4), 3.0)
			if not sel_target.is_empty() and int(sel_target["tier"]) == tier and int(sel_target["index"]) == i:
				draw_arc(c, NODE_R + 3.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.95), 3.0)
			var lbl: String = TYPE_LABELS.get(nd["type"], "?")
			draw_string(font, c + Vector2(-NODE_R, NODE_R + 14.0), lbl, HORIZONTAL_ALIGNMENT_CENTER, NODE_R * 2.0, 12, Color(0.85, 0.88, 0.94))

	# Avatar (hero sprite).
	var ascr := _w2s(_avatar)
	if _hero_tex != null:
		var sz := Vector2(46.0, 46.0)
		draw_texture_rect(_hero_tex, Rect2(ascr - sz * 0.5 - Vector2(0.0, 6.0), sz), false)
	else:
		draw_circle(ascr, 16.0, Color(0.9, 0.85, 0.5))

	_draw_minimap()

	# Mask the world bleeding under the right-hand HUD, then the panel backdrop.
	draw_rect(Rect2(PLAY_W, 0.0, 1280.0 - PLAY_W, 720.0), UITheme.BG)
	draw_rect(Rect2(SIDE_X - 22.0, 0.0, 422.0, 720.0), Color(0.035, 0.040, 0.060, 0.74))
	draw_line(Vector2(SIDE_X - 22.0, 0.0), Vector2(SIDE_X - 22.0, 720.0), Color(0.25, 0.27, 0.35, 0.85), 1.0)

func _w2s(world: Vector2) -> Vector2:
	return world - Vector2(_cam_x, 0.0)

# Bottom-left overview of the whole run: every node + connection scaled to fit,
# with visited/current/reachable/selected markers and a box showing where the
# camera (the slice you can see) sits along the path. Restores the route-planning
# the side-scroll view loses.
func _draw_minimap() -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(14.0, 498.0, 300.0, 184.0)
	draw_rect(rect, Color(0.06, 0.07, 0.11, 0.88))
	draw_rect(rect, Color(0.30, 0.32, 0.44, 0.9), false, 1.0)
	draw_string(font, rect.position + Vector2(8.0, 16.0), "Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.60, 0.63, 0.72))

	var last: int = maxi(1, GameManager.MAP_TIERS - 1)
	var inner_x: float = rect.position.x + 20.0
	var inner_w: float = rect.size.x - 32.0
	var cy: float = rect.position.y + rect.size.y * 0.58
	var lane: float = minf(16.0, (rect.size.y * 0.5 - 14.0) / 2.5)
	var mm := func(tier: int, idx: int) -> Vector2:
		var count: int = GameManager.map_data[tier].size()
		return Vector2(
			inner_x + (float(tier) / float(last)) * inner_w,
			cy + (float(idx) - float(count - 1) * 0.5) * lane)

	# Connections.
	for tier in range(GameManager.MAP_TIERS - 1):
		for i in range(GameManager.map_data[tier].size()):
			var a: Vector2 = mm.call(tier, i)
			for j in GameManager.map_data[tier][i]["connections"]:
				draw_line(a, mm.call(tier + 1, int(j)), Color(0.32, 0.34, 0.46, 0.5), 1.0)

	# Camera viewport indicator (which slice of the world is on screen).
	var vx0: float = inner_x + (_cam_x / maxf(1.0, _world_w)) * inner_w
	var vx1: float = inner_x + ((_cam_x + PLAY_W) / maxf(1.0, _world_w)) * inner_w
	draw_rect(Rect2(vx0, rect.position.y + 22.0, maxf(3.0, vx1 - vx0), rect.size.y - 34.0),
		Color(0.90, 0.92, 1.0, 0.07))

	# Nodes.
	var reach: Array = GameManager.get_reachable_indices()
	var pulse: float = 0.5 + 0.5 * sin(_pulse_t * 4.0)
	for tier in range(GameManager.MAP_TIERS):
		for i in range(GameManager.map_data[tier].size()):
			var nd: Dictionary = GameManager.map_data[tier][i]
			var col: Color = TYPE_COLORS.get(nd["type"], Color.GRAY)
			if bool(nd.get("visited", false)):
				col = col.darkened(0.5)
			var p: Vector2 = mm.call(tier, i)
			draw_circle(p, 3.5, col)
			if tier == GameManager.current_tier and i in reach:
				draw_arc(p, 5.0 + pulse * 2.0, 0.0, TAU, 16, Color(0.95, 0.85, 0.35, 0.6), 1.5)

	# Selected fork + current position.
	if _nav == Nav.AT_NODE and _sel < _targets.size():
		var t: Dictionary = _targets[_sel]
		draw_arc(mm.call(int(t["tier"]), int(t["index"])), 6.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.9), 1.5)
	if not _at_start:
		draw_circle(mm.call(_cur_tier, _cur_index), 4.5, Color(0.95, 0.95, 1.0))

# ---------------------------------------------------------------------------
# World layout + navigation
# ---------------------------------------------------------------------------
func _build_world() -> void:
	_world_w = MARGIN_X + float(GameManager.MAP_TIERS - 1) * TIER_DX + MARGIN_X
	var key := "soldier"
	if GameManager.has_hero():
		key = String(GameManager.hero_data().get("sprite_key", "soldier"))
	_hero_tex = load("res://assets/units/%s_player.png" % key)
	add_child(UITheme.label("Your Journey", 30, Color(0.95, 0.90, 0.65), Vector2(72.0, 20.0)))
	add_child(UITheme.label("→/D walk · ↑↓ choose the fork · I inventory · Esc menu",
		14, UITheme.TEXT_MUTED, Vector2(76.0, 58.0), Vector2(720.0, 24.0)))

func _node_world_pos(tier: int, index: int) -> Vector2:
	var count: int = GameManager.map_data[tier].size()
	var x := MARGIN_X + float(tier) * TIER_DX
	var y := CENTER_Y + (float(index) - float(count - 1) * 0.5) * LANE_GAP
	return Vector2(x, y)

func _standing_pos() -> Vector2:
	if _at_start:
		return Vector2(46.0, CENTER_Y)
	return _node_world_pos(_cur_tier, _cur_index)

# Place the avatar on the node GameManager says the run is at, and compute the
# reachable forks.
func _anchor_to_current() -> void:
	if GameManager.last_chosen_index == -1:
		_at_start = true
		_cur_tier = 0
		_cur_index = 0
	else:
		_at_start = false
		_cur_tier = GameManager.current_tier - 1
		_cur_index = GameManager.last_chosen_index
	_avatar = _standing_pos()
	_nav = Nav.AT_NODE
	_edge_pickups.clear()
	_encounter_pending = false
	_targets.clear()
	for idx in GameManager.get_reachable_indices():
		_targets.append({"tier": GameManager.current_tier, "index": int(idx)})
	_sel = clampi(_sel, 0, maxi(0, _targets.size() - 1))
	_update_node_detail()

func _select_target(dir: int) -> void:
	if _nav != Nav.AT_NODE or _targets.size() <= 1:
		return
	var prev := _sel
	_sel = wrapi(_sel + dir, 0, _targets.size())
	if _sel != prev:
		Sfx.play("select", -12.0)
	_update_node_detail()
	queue_redraw()

func _update_node_detail() -> void:
	if _node_detail_label == null or _targets.is_empty():
		return
	var t: Dictionary = _targets[_sel]
	_node_detail_label.text = _node_detail_text(int(t["tier"]), int(t["index"]))

func _begin_travel() -> void:
	if _targets.is_empty():
		return
	_cam_user_x = -1.0   # recenter: resume following the avatar
	_travel_target = _targets[_sel]
	_travel_from = _standing_pos()
	_travel_to = _node_world_pos(int(_travel_target["tier"]), int(_travel_target["index"]))
	_travel_t = 0.0
	_step_t = 0.0
	_nav = Nav.TRAVELING
	_gen_edge_content()

# Seeded pickups + a chance of an encounter for the edge being entered.
func _gen_edge_content() -> void:
	_edge_pickups.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = (_cur_tier + 1) * 7919 + _cur_index * 131 + int(_travel_target["index"]) * 17
	var n: int = rng.randi_range(0, 2)
	for _i in range(n):
		var t: float = rng.randf_range(0.28, 0.82)
		var pos := _travel_from.lerp(_travel_to, t) + Vector2(0.0, rng.randf_range(-26.0, 26.0))
		var is_gold: bool = rng.randf() < 0.7
		_edge_pickups.append({
			"t": t, "pos": pos, "taken": false,
			"kind": "gold",
			"amount": rng.randi_range(8, 15) if is_gold else rng.randi_range(4, 8),
		})
	# ~25% encounter, opened at the start of the edge (no mid-edge scene change).
	if rng.randf() < 0.25:
		_trigger_encounter(rng)

func _update_travel(delta: float) -> void:
	if _encounter_pending:
		if _popup == null:
			_encounter_pending = false   # encounter resolved — resume next frame
		return
	if not (Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)):
		return   # hold to walk; release pauses
	var dist: float = maxf(1.0, _travel_from.distance_to(_travel_to))
	_travel_t = minf(1.0, _travel_t + delta * WALK_SPEED / dist)
	_avatar = _travel_from.lerp(_travel_to, _travel_t)
	# Quiet footsteps while actually advancing (plays often, so keep it low).
	_step_t += delta
	if _step_t >= 0.32:
		_step_t -= 0.32
		Sfx.play("step", -18.0)
	for p: Dictionary in _edge_pickups:
		if not bool(p.get("taken", false)) and _travel_t >= float(p["t"]):
			_collect_pickup(p)
	if _travel_t >= 1.0:
		_arrive()

func _collect_pickup(p: Dictionary) -> void:
	p["taken"] = true
	GameManager.add_gold(int(p["amount"]))
	_show_toast("+%d gold" % int(p["amount"]), Color(0.95, 0.82, 0.30))
	Sfx.play("gold")
	_refresh()

func _arrive() -> void:
	var tgt := _travel_target
	_avatar = _travel_to
	_nav = Nav.AT_NODE
	_step_t = 0.0
	Sfx.play("capture", -10.0)   # soft "you reached a node" cue
	_trigger_node(int(tgt["tier"]), int(tgt["index"]))

# A roadside encounter: a random event, or a lone recruit (dialogue/persuasion
# only — never a duel, which would change scene mid-travel).
func _trigger_encounter(rng: RandomNumberGenerator) -> void:
	_encounter_pending = true
	if rng.randf() < 0.5:
		_build_event_popup(GameManager.random_event())
		return
	var cand := GameManager.encounter_recruit(rng.randi())
	_popup = UITheme.panel(self, Vector2(300.0, 180.0), Vector2(680.0, 360.0),
		Color(0.10, 0.10, 0.16, 0.99), Color(0.50, 0.52, 0.74))
	_popup.add_child(UITheme.label("A traveller blocks the road...", 18, UITheme.TEXT_MUTED,
		Vector2(28.0, 14.0), Vector2(624.0, 24.0)))
	if String(cand["sway"]) == "dialogue":
		_show_dialogue_resolver(cand)
	else:
		_show_persuasion_resolver(_cur_tier if not _at_start else 0, cand)

func _node_detail_text(tier: int, index: int) -> String:
	var nd: Dictionary = GameManager.map_data[tier][index]
	var type_key: String = String(nd["type"])
	var title: String = TYPE_LABELS.get(type_key, "Node")
	var lines: Array[String] = [title, TYPE_DESC.get(type_key, "")]
	if type_key in ["battle", "elite_battle"]:
		var elite := type_key == "elite_battle"
		if elite:
			var m := GameManager.elite_modifier_data(tier)
			if not m.is_empty():
				lines.append("Elite: %s — %s" % [String(m["name"]), String(m["desc"])])
		var roster: Array[String] = GameManager.get_battle_enemy_roster(tier, elite)
		var counts: Dictionary = {}
		for k: String in roster:
			counts[k] = int(counts.get(k, 0)) + 1
		lines.append("")
		lines.append("Enemy preview:")
		for k: String in counts.keys():
			var udata: Dictionary = GameManager.UNIT_TYPES[k]
			lines.append("%dx %s" % [counts[k], udata["name"]])
		var hp_mult: float = GameManager.get_hp_multiplier(tier, elite)
		if hp_mult > 1.001:
			lines.append("HP scaling x%.2f" % hp_mult)
		lines.append("Odds: %s" % GameManager.battle_odds(tier, elite, "fight"))
	elif type_key == "gain_unit":
		lines.append("")
		lines.append("Adds one recruit of your choice.")
	elif type_key == "shop":
		lines.append("")
		lines.append("Spend gold on healing, units, or a relic offer.")
	elif type_key == "heal":
		lines.append("")
		lines.append("Restores every surviving unit to full HP.")
	return "\n".join(lines)

func _circle_style(color: Color, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	var r := int(radius)
	s.corner_radius_top_left    = r
	s.corner_radius_top_right   = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	return s

func _build_hud() -> void:
	var side := UITheme.panel(self, Vector2(SIDE_X, 24.0), Vector2(328.0, 652.0), UITheme.PANEL, Color(0.34, 0.36, 0.46))
	side.add_child(UITheme.label("Run", 24, UITheme.GOLD, Vector2(18.0, 14.0)))

	_depth_label = UITheme.label("", 14, UITheme.TEXT_MUTED, Vector2(18.0, 48.0), Vector2(286.0, 22.0))
	side.add_child(_depth_label)
	_gold_label = UITheme.label("", 18, UITheme.GOLD, Vector2(18.0, 80.0), Vector2(286.0, 24.0))
	side.add_child(_gold_label)
	_hero_label = UITheme.label("", 14, Color(0.78, 0.84, 0.98), Vector2(18.0, 104.0), Vector2(286.0, 22.0))
	side.add_child(_hero_label)

	side.add_child(UITheme.label("Roster", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 130.0)))
	_roster_label = UITheme.label("", 13, Color(0.90, 0.85, 0.70), Vector2(18.0, 144.0), Vector2(292.0, 112.0))
	side.add_child(_roster_label)

	side.add_child(UITheme.label("Relics", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 272.0)))
	side.add_child(UITheme.button("Inventory  [I]", Vector2(176.0, 266.0), Vector2(140.0, 26.0),
		Color(0.28, 0.30, 0.42), _toggle_inventory, 12))
	_relics_label = UITheme.label("", 12, Color(0.75, 0.85, 0.95), Vector2(18.0, 292.0), Vector2(292.0, 82.0))
	side.add_child(_relics_label)

	side.add_child(UITheme.label("Node", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 396.0)))
	_node_detail_label = UITheme.label("", 13, UITheme.TEXT, Vector2(18.0, 418.0), Vector2(292.0, 132.0))
	side.add_child(_node_detail_label)

	side.add_child(UITheme.label("Legend", 13, Color(0.58, 0.61, 0.68), Vector2(18.0, 570.0)))
	var lx := 18.0
	var ly := 594.0
	for type_key: String in TYPE_COLORS.keys():
		UITheme.chip(side, TYPE_LABELS[type_key], Vector2(lx, ly), TYPE_COLORS[type_key], 92.0)
		lx += 100.0
		if lx > 220.0:
			lx = 18.0
			ly += 30.0

# ---------------------------------------------------------------------------
# Refresh state
# ---------------------------------------------------------------------------
# Friendly name for the run's battle style (shown in the Run panel).
func _battle_mode_name() -> String:
	return "Auto-Battler"

func _refresh() -> void:
	var cur_tier := GameManager.current_tier

	_roster_label.text = _roster_text()
	_gold_label.text   = "Gold: %d" % GameManager.gold
	if _hero_label != null:
		if GameManager.has_hero():
			_hero_label.text = "Hero: %s  ·  Tree Lv%d" % [
				String(GameManager.hero_data().get("name", "Hero")), GameManager.hero_meta_level()]
		else:
			_hero_label.text = ""
	_relics_label.text = _relics_text()
	_depth_label.text  = "%s  ·  Tier %d / %d  ·  Wins %d" % [
		_battle_mode_name(), cur_tier, GameManager.MAP_TIERS, GameManager.battles_won
	]
	_update_node_detail()

	if cur_tier >= GameManager.MAP_TIERS:
		_show_victory()

	queue_redraw()

func _relics_text() -> String:
	var lines: Array[String] = []
	if GameManager.relics.is_empty():
		lines.append("(no relics)")
	else:
		var names: Array[String] = []
		for id: String in GameManager.relics:
			names.append(GameManager.RELICS[id]["name"])
		lines.append("  ·  ".join(names))
	if not GameManager.curses.is_empty():
		var cnames: Array[String] = []
		for cid: String in GameManager.curses:
			cnames.append(GameManager.CURSES[cid]["name"])
		lines.append("Curses: " + "  ·  ".join(cnames))
	return "\n".join(lines)

func _roster_text() -> String:
	if GameManager.player_roster.is_empty():
		return "(none)"
	var parts: Array[String] = []
	for entry: Dictionary in GameManager.player_roster:
		var udata: Dictionary = GameManager.UNIT_TYPES[entry["type"]]
		var hp: int = int(entry["hp"])
		var max_hp: int = GameManager.unit_effective_max_hp(entry)
		# Flag wounded units so heal nodes read as worthwhile
		var hp_str: String = "%d/%d" % [hp, max_hp]
		if hp < max_hp:
			hp_str += "⚠"
		var ups: Array = entry.get("upgrades", [])
		var up_str: String = (" ✦%d" % ups.size()) if ups.size() > 0 else ""
		var lvl: int = GameManager.unit_level(entry)
		var lvl_str: String = (" Lv%d" % lvl) if lvl > 1 else ""
		parts.append("%s%s %s%s" % [udata["name"], lvl_str, hp_str, up_str])
	return "   ".join(parts)

# ---------------------------------------------------------------------------
# Node interaction
# ---------------------------------------------------------------------------
# Called when the avatar arrives at a node. Visits it, then runs the node's
# handler. Scene-changing nodes set _leaving; popup nodes set _awaiting_resolve
# (the next fork is set up in _process once the popup closes); instant nodes
# re-anchor immediately.
func _trigger_node(tier: int, index: int) -> void:
	var node_data: Dictionary = GameManager.map_data[tier][index]
	_leaving = false
	GameManager.visit_node(tier, index)

	match node_data["type"]:
		"battle", "elite_battle":
			var elite: bool = node_data["type"] == "elite_battle"
			if not GameManager.has_hero():
				# Defensive — campaigns always have a hero.
				_launch_autobattle(tier, elite)
			else:
				_show_prebattle_popup(tier, elite)
		"gain_unit":
			_show_recruit_popup(tier, index)
		"shop":
			_show_shop_popup()
		"heal":
			GameManager.heal_roster()
			Sfx.play("heal")
			_refresh()
			_show_toast("Party fully healed!", Color(0.20, 0.72, 0.35))
		"event":
			_show_event_popup()
		"treasure":
			var rid := GameManager.grant_random_relic()
			Sfx.play("gold")
			if rid != "":
				_show_toast("Treasure! Found %s" % String(GameManager.RELICS[rid]["name"]), Color(0.95, 0.82, 0.30))
			else:
				GameManager.add_gold(80)
				_show_toast("Treasure! +80 gold", Color(0.95, 0.82, 0.30))
			_refresh()
		_:
			_refresh()

	# Decide how the avatar resumes after this node.
	if _leaving:
		return                       # scene is changing; nothing to resume
	elif _popup != null:
		_awaiting_resolve = true     # _process re-anchors when the popup closes
	else:
		_anchor_to_current()         # instant node — offer the next fork now
		_refresh()

func _launch_autobattle(tier: int, elite: bool) -> void:
	_leaving = true
	GameManager.pending_battle_tier  = tier
	GameManager.pending_battle_elite = elite
	GameManager.pending_autobattle = true
	get_tree().change_scene_to_file("res://src/autobattler/autobattler.tscn")

# ---------------------------------------------------------------------------
# Pre-battle popup — choose the hero's role for the upcoming fight.
# Pre-battle confirmation. The hero always fights at the front of the army.
# ---------------------------------------------------------------------------
func _show_prebattle_popup(tier: int, elite: bool) -> void:
	if _popup != null:
		return
	var hero: Dictionary = GameManager.hero_data()

	_popup = UITheme.panel(self, Vector2(360.0, 180.0), Vector2(560.0, 360.0),
		Color(0.09, 0.10, 0.16, 0.99), Color(0.50, 0.52, 0.74))
	_popup.add_child(UITheme.label("Battle — Your Hero's Role", 26, UITheme.GOLD,
		Vector2(28.0, 18.0), Vector2(504.0, 32.0)))
	_popup.add_child(UITheme.label("%s — choose how %s joins this fight." % [
		String(hero.get("name", "Hero")), String(hero.get("name", "your hero"))],
		15, UITheme.TEXT_MUTED, Vector2(28.0, 54.0), Vector2(504.0, 24.0)))

	# Elite modifier note (only meaningful for elite battles), under the subtitle.
	if elite:
		var m := GameManager.elite_modifier_data(tier)
		if not m.is_empty():
			_popup.add_child(UITheme.label("Elite — %s: %s" % [String(m["name"]), String(m["desc"])],
				13, Color(0.92, 0.72, 0.98), Vector2(28.0, 76.0), Vector2(504.0, 18.0)))

	# Active army synergies (composition bonuses) under the subtitle.
	var syn_ids := GameManager.army_synergies()
	var syn_text: String
	if syn_ids.is_empty():
		syn_text = "Synergies: none"
	else:
		var syn_names: Array[String] = []
		for sid: String in syn_ids:
			syn_names.append(String(GameManager.SYNERGIES[sid]["name"]))
		syn_text = "Synergies: " + "  ·  ".join(syn_names)
	_popup.add_child(UITheme.label(syn_text, 13, Color(0.70, 0.92, 0.88),
		Vector2(28.0, 94.0), Vector2(504.0, 20.0)))

	# The hero fights as the front-most lineup unit, granting its leader aura
	# (Spec D — fight/buff mode removed).
	_popup.add_child(UITheme.label("The hero fights at the front of your army and grants its leader aura.",
		14, UITheme.TEXT, Vector2(28.0, 128.0), Vector2(504.0, 24.0)))
	_popup.add_child(UITheme.label("Odds: %s" % GameManager.battle_odds(tier, elite, "fight"),
		13, UITheme.TEXT_MUTED, Vector2(28.0, 156.0), Vector2(504.0, 20.0)))
	_popup.add_child(UITheme.button("Fight", Vector2(28.0, 188.0), Vector2(504.0, 46.0),
		UITheme.GREEN.darkened(0.1), _on_prebattle_fight.bind(tier, elite)))

	# No Cancel: entering a battle node commits the visit (visit_node already
	# advanced the tier), and Fight is always available — so the player can't
	# back out into a softlock.

func _on_prebattle_fight(tier: int, elite: bool) -> void:
	_popup.queue_free()
	_popup = null
	_launch_autobattle(tier, elite)

# ---------------------------------------------------------------------------
# Recruitment popup (Phase 2) — "meet & sway". A gain_unit node offers 2-3
# candidates, each with its own sway type (dialogue / persuasion / duel). The
# player approaches one to win them over; that commits the node either way.
# ---------------------------------------------------------------------------
const _SWAY_BADGE: Dictionary = {
	"dialogue":   {"label": "Talk",     "color": Color(0.36, 0.66, 0.92)},
	"persuasion": {"label": "Persuade", "color": Color(0.85, 0.70, 0.24)},
	"duel":       {"label": "Duel",     "color": Color(0.82, 0.32, 0.32)},
}
func _show_recruit_popup(tier: int, index: int) -> void:
	if _popup != null:
		return
	var cands := GameManager.recruit_candidates(tier, index)
	_popup = UITheme.panel(self, Vector2(130.0, 150.0), Vector2(1020.0, 420.0),
		Color(0.09, 0.09, 0.16, 0.98), Color(0.50, 0.50, 0.75))
	_popup.add_child(UITheme.label("Recruit — Win Them Over", 26, Color(0.95, 0.90, 1.0),
		Vector2(28.0, 16.0), Vector2(964.0, 32.0)))
	_popup.add_child(UITheme.label("Approach a recruit to win them over. Choosing one commits this node.",
		14, UITheme.TEXT_MUTED, Vector2(28.0, 52.0), Vector2(964.0, 22.0)))

	var n: int = cands.size()
	var card_w: float = (964.0 - float(n - 1) * 20.0) / float(n)
	for i in range(n):
		var cand: Dictionary = cands[i]
		var cx: float = 28.0 + float(i) * (card_w + 20.0)
		_build_recruit_card(tier, index, cand, Vector2(cx, 88.0), Vector2(card_w, 280.0))

func _build_recruit_card(tier: int, index: int, cand: Dictionary, pos: Vector2, size: Vector2) -> void:
	var utype: String = String(cand["type"])
	var udata: Dictionary = GameManager.UNIT_TYPES[utype]
	var sway: String = String(cand["sway"])
	var badge: Dictionary = _SWAY_BADGE.get(sway, {"label": sway, "color": Color.GRAY})
	var pers: Dictionary = GameManager.RECRUIT_PERSONALITIES[int(cand["personality"])]

	# Card backing panel
	var card := UITheme.panel(_popup, pos, size, Color(0.12, 0.12, 0.20, 0.96),
		udata["color"].lightened(0.1))
	# Personality name leads; the unit class sits beneath it as a sub-label.
	card.add_child(UITheme.label(String(pers["name"]), 20, Color(0.98, 0.92, 0.78),
		Vector2(14.0, 8.0), Vector2(size.x - 28.0, 26.0)))
	card.add_child(UITheme.label(String(udata["name"]), 13, Color(0.74, 0.80, 0.92),
		Vector2(14.0, 34.0), Vector2(size.x - 28.0, 18.0)))
	# Sway badge chip
	UITheme.chip(card, String(badge["label"]), Vector2(14.0, 54.0), badge["color"],
		size.x - 28.0)
	# Personality flavour line.
	card.add_child(UITheme.label("\"%s\"" % String(pers["line"]), 11, Color(0.78, 0.78, 0.70),
		Vector2(14.0, 80.0), Vector2(size.x - 28.0, 30.0)))

	var ability: Dictionary = udata.get("ability", {})
	var stat_txt := "HP %d   Dmg %d   Rng %d\nMove %d\nAbility: %s" % [
		int(udata["max_hp"]), int(udata["damage"]), int(udata["attack_range"]),
		int(udata["move_range"]), String(ability.get("name", "—"))]
	card.add_child(UITheme.label(stat_txt, 13, UITheme.TEXT,
		Vector2(14.0, 112.0), Vector2(size.x - 28.0, 70.0)))

	# Ask preview + the discounted cost for persuasion.
	var ask: String
	match sway:
		"dialogue":
			ask = "Win them over with words."
		"persuasion":
			var cost := GameManager.recruit_persuasion_cost(utype, tier)
			if GameManager.hero_sway_aptitude("persuasion") > 0:
				cost = int(round(cost * 0.6))
			ask = "Hire for %d gold." % cost
		"duel":
			ask = "Fight a 1v1 duel."
		_:
			ask = ""
	card.add_child(UITheme.label(ask, 13, Color(0.82, 0.86, 0.92),
		Vector2(14.0, 184.0), Vector2(size.x - 28.0, 22.0)))

	# Hero-excels marker when the hero is good at this sway type.
	if GameManager.hero_sway_aptitude(sway) > 0:
		card.add_child(UITheme.label("★ your hero excels here", 12, Color(0.98, 0.86, 0.40),
			Vector2(14.0, 208.0), Vector2(size.x - 28.0, 18.0)))

	var approach := UITheme.button("Approach", Vector2(14.0, size.y - 52.0),
		Vector2(size.x - 28.0, 40.0), udata["color"].darkened(0.1),
		_approach_candidate.bind(tier, index, cand), 16)
	card.add_child(approach)

func _approach_candidate(tier: int, index: int, cand: Dictionary) -> void:
	match String(cand["sway"]):
		"dialogue":
			_show_dialogue_resolver(cand)
		"persuasion":
			_show_persuasion_resolver(tier, cand)
		"duel":
			_leaving = true
			GameManager.pending_duel = true
			GameManager.duel_recruit_type = String(cand["type"])
			GameManager.duel_outcome = -1
			if _popup != null:
				_popup.queue_free()
				_popup = null
			get_tree().change_scene_to_file("res://src/autobattler/autobattler.tscn")

# Swap the popup body for the dialogue sub-screen (keeps the same _popup panel).
func _show_dialogue_resolver(cand: Dictionary) -> void:
	if _popup == null:
		return
	for c in _popup.get_children():
		c.queue_free()
	var utype: String = String(cand["type"])
	var udata: Dictionary = GameManager.UNIT_TYPES[utype]
	var pers: Dictionary = GameManager.RECRUIT_PERSONALITIES[int(cand["personality"])]
	var scene: Dictionary = GameManager.DIALOGUE_SCENES[int(cand["scene"])]
	var options: Array = scene["options"]
	var correct: int = int(scene["correct"])
	var hint: bool = GameManager.hero_sway_aptitude("dialogue") > 0

	_popup.add_child(UITheme.label("Win Over %s the %s" % [String(pers["name"]), String(udata["name"])], 26,
		Color(0.95, 0.90, 1.0), Vector2(28.0, 16.0), Vector2(964.0, 32.0)))
	_popup.add_child(UITheme.label("\"%s\"" % String(pers["line"]),
		14, Color(0.80, 0.82, 0.72), Vector2(28.0, 50.0), Vector2(964.0, 22.0)))
	_popup.add_child(UITheme.label(String(scene["prompt"]),
		16, UITheme.TEXT, Vector2(28.0, 76.0), Vector2(964.0, 24.0)))

	for i in range(options.size()):
		var is_hint: bool = hint and i == correct
		var txt: String = String(options[i])
		if is_hint:
			txt = "★ " + txt
		var col: Color = Color(0.30, 0.55, 0.40) if is_hint else Color(0.24, 0.28, 0.40)
		var btn := UITheme.button(txt, Vector2(28.0, 112.0 + float(i) * 84.0),
			Vector2(964.0, 70.0), col, _on_dialogue_response.bind(cand, i), 18)
		_popup.add_child(btn)

func _on_dialogue_response(cand: Dictionary, picked: int) -> void:
	var correct: int = int(GameManager.DIALOGUE_SCENES[int(cand["scene"])]["correct"])
	if picked == correct:
		_recruit_succeed(String(cand["type"]))
	else:
		_recruit_decline(String(cand["type"]))

# Swap the popup body for the persuasion sub-screen.
func _show_persuasion_resolver(tier: int, cand: Dictionary) -> void:
	if _popup == null:
		return
	for c in _popup.get_children():
		c.queue_free()
	var utype: String = String(cand["type"])
	var udata: Dictionary = GameManager.UNIT_TYPES[utype]
	var pers: Dictionary = GameManager.RECRUIT_PERSONALITIES[int(cand["personality"])]
	var cost := GameManager.recruit_persuasion_cost(utype, tier)
	if GameManager.hero_sway_aptitude("persuasion") > 0:
		cost = int(round(cost * 0.6))
	var affordable: bool = GameManager.gold >= cost

	_popup.add_child(UITheme.label("Persuade %s the %s" % [String(pers["name"]), String(udata["name"])], 26,
		UITheme.GOLD, Vector2(28.0, 16.0), Vector2(964.0, 32.0)))
	_popup.add_child(UITheme.label("\"%s\"" % String(pers["line"]),
		14, Color(0.80, 0.82, 0.72), Vector2(28.0, 50.0), Vector2(964.0, 22.0)))
	_popup.add_child(UITheme.label("Costs %d gold (you have %d)." % [cost, GameManager.gold],
		16, UITheme.TEXT, Vector2(28.0, 76.0), Vector2(964.0, 24.0)))
	if not affordable:
		_popup.add_child(UITheme.label("Not enough gold to make the offer.", 13, UITheme.RED,
			Vector2(28.0, 102.0), Vector2(964.0, 20.0)))

	var pay := UITheme.button("Pay %d" % cost, Vector2(28.0, 130.0), Vector2(964.0, 56.0),
		UITheme.GREEN.darkened(0.1), _on_persuasion_pay.bind(cand, cost), 18)
	pay.disabled = not affordable
	if not affordable:
		pay.add_theme_stylebox_override("disabled", UITheme.button_style(Color(0.20, 0.22, 0.30)))
	_popup.add_child(pay)

	_popup.add_child(UITheme.button("Walk away", Vector2(28.0, 200.0), Vector2(964.0, 56.0),
		Color(0.30, 0.30, 0.34), _recruit_decline.bind(String(cand["type"])), 18))

func _on_persuasion_pay(cand: Dictionary, cost: int) -> void:
	if GameManager.spend_gold(cost):
		_recruit_succeed(String(cand["type"]))
	else:
		_recruit_decline(String(cand["type"]))

func _recruit_succeed(type: String) -> void:
	GameManager.add_unit(type)
	if _popup != null:
		_popup.queue_free()
		_popup = null
	Sfx.play("heal")
	_show_toast("%s joined your army!" % GameManager.UNIT_TYPES[type]["name"],
		GameManager.UNIT_TYPES[type]["color"])
	_refresh()

func _recruit_decline(type: String) -> void:
	if _popup != null:
		_popup.queue_free()
		_popup = null
	_show_toast("%s decided not to join." % GameManager.UNIT_TYPES[type]["name"],
		Color(0.7, 0.6, 0.5))
	_refresh()

# ---------------------------------------------------------------------------
# Random event popup
# ---------------------------------------------------------------------------
func _show_event_popup() -> void:
	_build_event_popup(GameManager.random_event())

func _build_event_popup(ev: Dictionary) -> void:
	if _popup != null:
		for c in _popup.get_children():
			c.queue_free()
	else:
		_popup = UITheme.panel(self, Vector2(300.0, 200.0), Vector2(680.0, 320.0),
			Color(0.08, 0.13, 0.14, 0.98), Color(0.30, 0.72, 0.72))
	_popup.add_child(UITheme.label(String(ev["title"]), 26, Color(0.70, 0.95, 0.95), Vector2(28.0, 18.0), Vector2(624.0, 34.0)))
	_popup.add_child(UITheme.label(String(ev["text"]), 16, UITheme.TEXT, Vector2(28.0, 64.0), Vector2(624.0, 70.0)))
	var choices: Array = ev["choices"]
	var n: int = choices.size()
	var bw: float = 624.0 / float(n) - 12.0
	for i in range(n):
		var ch: Dictionary = choices[i]
		var cost: int = int(ch.get("cost", 0))
		var enabled: bool = GameManager.gold >= cost
		var btn := Button.new()
		btn.text = String(ch["label"])
		btn.position = Vector2(28.0 + i * (bw + 16.0), 180.0)
		btn.size = Vector2(bw, 110.0)
		btn.disabled = not enabled
		btn.add_theme_font_size_override("font_size", 15)
		var col := Color(0.22, 0.40, 0.42) if enabled else Color(0.18, 0.20, 0.22)
		btn.add_theme_stylebox_override("normal",   _circle_style(col, 8))
		btn.add_theme_stylebox_override("hover",    _circle_style(col.lightened(0.15), 8))
		btn.add_theme_stylebox_override("pressed",  _circle_style(col.darkened(0.25), 8))
		btn.add_theme_stylebox_override("disabled", _circle_style(col.darkened(0.4), 8))
		btn.pressed.connect(_on_event_choice.bind(ch))
		_popup.add_child(btn)

func _on_event_choice(choice: Dictionary) -> void:
	var msg: String = GameManager.apply_event_choice(choice)
	Sfx.play("gold")
	# A choice may chain into a follow-up event instead of closing.
	var eff: Dictionary = choice.get("effect", {})
	if eff.has("chain"):
		var nxt: Dictionary = GameManager.get_chain_event(String(eff["chain"]))
		if not nxt.is_empty():
			_build_event_popup(nxt)
			return
	if _popup != null:
		_popup.queue_free()
		_popup = null
	_show_toast(msg, Color(0.55, 0.90, 0.90))

# ---------------------------------------------------------------------------
# Shop popup — spend gold; stays open for multiple purchases until "Leave"
# ---------------------------------------------------------------------------
func _show_shop_popup() -> void:
	# Pick one relic to offer for this visit (random unowned)
	var pool := GameManager.unowned_relics()
	_shop_relic_offer = pool[0] if not pool.is_empty() else ""
	_popup = Panel.new()
	_popup.position = Vector2(130.0, 130.0)
	_popup.size = Vector2(1020.0, 460.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.05, 0.97)
	for side in ["left", "right", "top", "bottom"]:
		style.set("border_width_" + side, 2)
	style.border_color = Color(0.85, 0.70, 0.20)
	for corner in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(corner, 8)
	_popup.add_theme_stylebox_override("panel", style)
	add_child(_popup)
	_populate_shop()

func _populate_shop() -> void:
	for child in _popup.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1.0, 0.88, 0.35)
	title.position = Vector2(30.0, 16.0)
	_popup.add_child(title)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: %d" % GameManager.gold
	gold_lbl.add_theme_font_size_override("font_size", 18)
	gold_lbl.modulate = Color(0.95, 0.82, 0.25)
	gold_lbl.position = Vector2(860.0, 20.0)
	_popup.add_child(gold_lbl)

	# Heal party
	var heal_btn := _make_shop_button(
		"Heal Party to Full   (%d gold)" % GameManager.SHOP_HEAL_COST,
		Vector2(24.0, 56.0), Vector2(480.0, 70.0),
		Color(0.20, 0.55, 0.30), GameManager.gold >= GameManager.SHOP_HEAL_COST)
	heal_btn.pressed.connect(_on_shop_heal)
	_popup.add_child(heal_btn)

	# Buy a relic (one offered per visit)
	var relic_enabled := _shop_relic_offer != "" and GameManager.gold >= GameManager.SHOP_RELIC_COST
	var relic_txt: String
	if _shop_relic_offer == "":
		relic_txt = "All relics owned"
	else:
		var r: Dictionary = GameManager.RELICS[_shop_relic_offer]
		relic_txt = "Relic: %s   (%d gold)\n%s" % [r["name"], GameManager.SHOP_RELIC_COST, r["desc"]]
	var relic_btn := _make_shop_button(relic_txt,
		Vector2(516.0, 56.0), Vector2(480.0, 70.0),
		Color(0.45, 0.35, 0.62), relic_enabled)
	relic_btn.pressed.connect(_on_shop_relic)
	_popup.add_child(relic_btn)

	# Buy a unit (one button per class) — 5-column grid so it wraps cleanly.
	var keys := GameManager.recruitable_types()
	var cols := 5
	for i in range(keys.size()):
		var utype: String = keys[i]
		var udata: Dictionary = GameManager.UNIT_TYPES[utype]
		var col := i % cols
		var row := i / cols
		var can_afford := GameManager.gold >= GameManager.SHOP_UNIT_COST
		var btn := _make_shop_button(
			"Buy %s\nHP %d Mv %d\nRng %d Dmg %d\n%d gold" % [
				udata["name"], udata["max_hp"], udata["move_range"],
				udata["attack_range"], udata["damage"], GameManager.SHOP_UNIT_COST],
			Vector2(20.0 + col * 196.0, 140.0 + row * 124.0), Vector2(188.0, 116.0),
			udata["color"].darkened(0.1), can_afford)
		var ab2: Dictionary = udata.get("ability", {})
		if not ab2.is_empty():
			btn.tooltip_text = "%s: %s" % [String(ab2.get("name", "")), String(ab2.get("desc", ""))]
		btn.pressed.connect(_on_shop_buy_unit.bind(utype))
		_popup.add_child(btn)

	var leave := Button.new()
	leave.text = "Leave"
	leave.position = Vector2(24.0, 400.0)
	leave.size = Vector2(972.0, 44.0)
	leave.add_theme_font_size_override("font_size", 18)
	leave.pressed.connect(func() -> void:
		_popup.queue_free()
		_popup = null
		_refresh())
	_popup.add_child(leave)

func _make_shop_button(txt: String, pos: Vector2, sz: Vector2, color: Color, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = sz
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_stylebox_override("normal",   _circle_style(color, 8))
	btn.add_theme_stylebox_override("hover",    _circle_style(color.lightened(0.15), 8))
	btn.add_theme_stylebox_override("pressed",  _circle_style(color.darkened(0.25), 8))
	btn.add_theme_stylebox_override("disabled", _circle_style(color.darkened(0.55), 8))
	return btn

func _on_shop_heal() -> void:
	if GameManager.spend_gold(GameManager.SHOP_HEAL_COST):
		GameManager.heal_roster()
		Sfx.play("heal")
		_show_toast("Party healed!", Color(0.30, 0.85, 0.45))
		_populate_shop()

func _on_shop_buy_unit(unit_type: String) -> void:
	if GameManager.spend_gold(GameManager.SHOP_UNIT_COST):
		GameManager.add_unit(unit_type)
		Sfx.play("gold")
		var name_str: String = GameManager.UNIT_TYPES[unit_type]["name"]
		_show_toast("Bought %s!" % name_str, GameManager.UNIT_TYPES[unit_type]["color"])
		_populate_shop()

func _on_shop_relic() -> void:
	if _shop_relic_offer == "":
		return
	if GameManager.spend_gold(GameManager.SHOP_RELIC_COST):
		var id := _shop_relic_offer
		GameManager.add_relic(id)
		Sfx.play("gold")
		_show_toast("Acquired %s!" % GameManager.RELICS[id]["name"], Color(0.65, 0.55, 0.95))
		# Offer the next unowned relic (if any)
		var pool := GameManager.unowned_relics()
		_shop_relic_offer = pool[0] if not pool.is_empty() else ""
		_populate_shop()

# ---------------------------------------------------------------------------
# Toast / Victory
# ---------------------------------------------------------------------------
func _show_toast(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.modulate = color
	lbl.position = Vector2(400.0, 330.0)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(lbl.queue_free)
	tw.tween_callback(_refresh)

func _show_victory() -> void:
	var panel := Panel.new()
	panel.position = Vector2(290.0, 200.0)
	panel.size = Vector2(700.0, 320.0)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	for side in ["left", "right", "top", "bottom"]:
		s.set("border_width_" + side, 3)
	s.border_color = Color(0.9, 0.8, 0.2)
	panel.add_theme_stylebox_override("panel", s)
	add_child(panel)

	var title := Label.new()
	title.text = "You conquered the map!"
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = Color(0.95, 0.85, 0.25)
	title.position = Vector2(100.0, 60.0)
	panel.add_child(title)

	var btn := Button.new()
	btn.text = "Play Again"
	btn.position = Vector2(260.0, 200.0)
	btn.size = Vector2(180.0, 60.0)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func() -> void:
		GameManager.reset()
		get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")
	)
	panel.add_child(btn)
