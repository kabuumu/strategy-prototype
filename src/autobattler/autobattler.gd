extends Node2D

const UITheme := preload("res://src/ui/ui_theme.gd")
const RTUnit := preload("res://src/rtbattle/rt_unit.gd")

const FIELD_RECT: Rect2 = Rect2(40.0, 72.0, 1200.0, 410.0)
const TEAM_SIZE: int = 5
const SHOP_SIZE: int = 3
const BUY_COST: int = 3
const ROLL_COST: int = 1
const SELL_REFUND: int = 1
const GOLD_PER_ROUND: int = 10
const MAX_WINS: int = 5
const START_HEARTS: int = 3
const AI_RETARGET_PERIOD: float = 0.45
const MAX_LEVEL: int = 3
const FIGHT_INTRO_SECONDS: float = 0.75
const FEEDBACK_LIFETIME: float = 0.55

enum Phase { SHOP, PREP, FIGHT, RESULT, REWARD, GAME_OVER }

# Traps set during the campaign PREP phase, fired on combat events (Spec B).
var _armed_traps: Array = []
var _below50_triggered: bool = false   # troop_below_50 traps fire once per fight
var _card_reward_offer: Array = []     # 3-card draft shown on a campaign win (Spec B)
var _upgrade_offer: Array = []         # 3 unit-upgrade choices on a campaign win
var _upgrade_pick: String = ""         # chosen upgrade awaiting unit assignment ("" = none)
var _reward_taken: bool = false        # a campaign-win reward (card OR upgrade) was claimed
# Campaign PREP (#10): step 0 = pick + ORDER a troop lineup; step 1 = draw 3, play 1.
const LINEUP_CAP: int = 5
var _prep_step: int = 0
var _pool: Array = []                  # [{card, entry}] — roster troops (NOT the hero)
var _lineup_sel: Array = []            # bool per pool index (deployed?); pool order = deploy order
var _prep_sel: int = -1                # pool index selected for reorder/bench in PREP step 0
var _hero_unit: RTUnit = null          # the deployed hero (campaign); its death ends the run
var _prep_draw: Array = []             # up to 3 drawn card ids for the play step
var _prep_equip_id: String = ""        # a drawn Equip card awaiting a unit tap

const UNIT_TYPES: Dictionary = {
	"soldier": {
		"name": "Infantry",
		"role": "Steady front line",
		"sprite_key": "soldier",
		"soldier_count": 9,
		"hp_per_soldier": 16,
		"damage_per_attack": 8,
		"attack_cooldown": 1.0,
		"attack_range_px": 58.0,
		"move_speed_px": 58.0,
	},
	"archer": {
		"name": "Archers",
		"role": "Long range damage",
		"sprite_key": "archer",
		"soldier_count": 6,
		"hp_per_soldier": 12,
		"damage_per_attack": 9,
		"attack_cooldown": 1.35,
		"attack_range_px": 210.0,
		"move_speed_px": 60.0,
	},
	"scout": {
		"name": "Cavalry",
		"role": "Fast flanker",
		"sprite_key": "scout",
		"soldier_count": 5,
		"hp_per_soldier": 14,
		"damage_per_attack": 10,
		"attack_cooldown": 0.9,
		"attack_range_px": 58.0,
		"move_speed_px": 96.0,
	},
	"healer": {
		"name": "Spearmen",
		"role": "Reach and bulk",
		"sprite_key": "healer",
		"soldier_count": 8,
		"hp_per_soldier": 15,
		"damage_per_attack": 9,
		"attack_cooldown": 1.1,
		"attack_range_px": 82.0,
		"move_speed_px": 54.0,
	},
}

const ITEM_TYPES: Dictionary = {
	"banner": {"name": "Banner", "short": "BNR", "damage": 1, "hp": 14, "role": "team standard"},
	"armor": {"name": "Armor", "short": "ARM", "damage": 0, "hp": 36, "role": "frontline bulk"},
	"bow": {"name": "Bow", "short": "BOW", "damage": 4, "hp": 0, "role": "extra damage"},
	"drum": {"name": "War Drum", "short": "DRM", "damage": 2, "hp": 12, "role": "tempo boost"},
}

var phase: int = Phase.SHOP
var round_no: int = 1
var wins: int = 0
var hearts: int = START_HEARTS
var gold: int = GOLD_PER_ROUND

var team: Array = []       # Array[Dictionary]
var shop: Array = []       # Array[Dictionary]
var selected_shop: int = -1
var selected_slot: int = -1
var player_units: Array = []
var enemy_units: Array = []

var _ui_nodes: Array = []
var _ai_timer: float = 0.0
var _fight_intro_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _result_text: String = ""
var _shop_message: String = "Click a shop unit to buy it into your hotbar."
var _fight_label: Label
var _freeze_mode: bool = false
var _enemy_preview: Array = []
var _reward_choices: Array = []
var _reroll_discount_next: bool = false
var _speed_scale: float = 2.0   # 2x by default — 1x standard felt too slow
var _start_abilities_applied: bool = false
var _unit_state: Dictionary = {}
var _feedback: Array = []
var _last_recap: Dictionary = {}
var _help_overlay: Control = null

const HELP_BODY: String = "Auto-battler: build a team, then watch it fight on its own (Super-Auto-Pets style).\n\nSHOP phase:\n- Click a shop unit to buy it into your hotbar (costs gold)\n- Buy a duplicate onto a unit to level it up (stronger)\n- Move </ > to reorder — slot 1 deploys at the front\n- Sell, Freeze the shop, or Roll for new units\n- Press Fight when ready\n\nFIGHT phase: units auto-target and battle. Win to bank a win; lose a heart. Win enough to take the run; lose your hearts and it's over.\n\n(In a campaign battle the shop is skipped — your roster fights directly.)\n\nH help  ·  Esc / Menu to leave"

# --- Campaign integration (battle_mode "auto") -----------------------------
# Launched from the campaign map, the auto-battler runs a SINGLE fight — the
# player's roster vs the tier's enemy roster — then reports the result back to
# GameManager and returns to the map, mirroring the 2D/3D battle contract.
# Campaign unit types are mapped onto the four auto-battler archetypes; the
# advanced recruits / bosses fight as higher-level (stronger) cards.
const CAMPAIGN_CARD_MAP: Dictionary = {
	"soldier": "soldier", "archer": "archer", "scout": "scout", "healer": "healer",
	"knight": "soldier", "guardian": "healer", "mage": "archer",
	"warlord": "soldier", "pyromancer": "archer", "juggernaut": "healer",
}
const CAMPAIGN_CARD_LEVEL: Dictionary = {
	"knight": 2, "guardian": 2, "mage": 2,
	"warlord": 3, "pyromancer": 3, "juggernaut": 3,
}
var _campaign: bool = false
var _campaign_lost: bool = false
var _campaign_relic: String = ""
var _campaign_gold: int = 0
var _duel: bool = false

func _ready() -> void:
	# Music is set per phase: pre-fight phases (quick-battle SHOP, campaign PREP)
	# loop the "Ceramic War Rite" intro; FIGHT swaps to the full battle track.
	# Duels skip prep, so they go straight to the battle track.
	_rng.randomize()
	if GameManager.pending_duel:
		GameManager.pending_duel = false
		_duel = true
		_start_duel_fight()
		return
	if GameManager.pending_autobattle:
		GameManager.pending_autobattle = false
		_campaign = true
		_start_campaign_fight()
		return
	Music.play("prebattle")   # quick-battle shop is a pre-fight build phase
	for _i in range(TEAM_SIZE):
		team.append({})
	_roll_shop(true)
	_refresh_enemy_preview()
	_rebuild_ui()

var _hover_unit: RTUnit = null   # unit under the cursor (stat tooltip in PREP/FIGHT)
var _villain_unit: RTUnit = null # the lurking/boss villain in a campaign battle
var _villain_boss: bool = false  # final-tier node: the villain fights for real
var _villain_taunt_timer: float = 0.0
var _villain_taunt_idx: int = 0

func _process(delta: float) -> void:
	_age_feedback(delta)
	if phase == Phase.PREP or phase == Phase.FIGHT:
		_update_hover()
	if phase != Phase.FIGHT:
		queue_redraw()
		return
	if _fight_intro_timer > 0.0:
		_fight_intro_timer = max(0.0, _fight_intro_timer - delta)
		if _fight_label != null and is_instance_valid(_fight_label):
			_fight_label.text = "AUTO FIGHT starts in %.1fs" % _fight_intro_timer
		queue_redraw()
		return
	if _fight_label != null and is_instance_valid(_fight_label):
		_fight_label.text = "AUTO FIGHT"
	if not _start_abilities_applied:
		_apply_start_abilities()
		_start_abilities_applied = true
	var all_units: Array = []
	all_units.append_array(player_units)
	all_units.append_array(enemy_units)
	var steps: int = max(1, int(round(_speed_scale)))
	var step_delta := delta
	for _step in range(steps):
		_check_villain_escape()
		_auto_target(step_delta)
		for u: RTUnit in all_units:
			if u.is_alive() and not u.is_escaping:
				_tick_unit(u, step_delta, all_units)
				u.position.x = clamp(u.position.x, FIELD_RECT.position.x + u.radius, FIELD_RECT.end.x - u.radius)
				u.position.y = clamp(u.position.y, FIELD_RECT.position.y + u.radius, FIELD_RECT.end.y - u.radius)
		if _check_fight_end():
			break
	_check_below50_traps()
	_villain_lurk_taunt(delta)
	queue_redraw()

# Fire troop_below_50 traps once, when any player Troop first drops below half HP.
func _check_below50_traps() -> void:
	if _below50_triggered or _armed_traps.is_empty():
		return
	for u: RTUnit in player_units:
		if is_instance_valid(u) and u.is_alive() and float(u.hp) / float(maxi(1, u.max_hp)) < 0.5:
			var rest: Array = []
			for trap in _armed_traps:
				if String(trap.get("trigger", "")) == "troop_below_50":
					_fire_trap(trap)
				else:
					rest.append(trap)
			_armed_traps = rest
			_below50_triggered = true
			return

# --- Villain (recurring boss) ----------------------------------------------
# A unit the player can't target in a normal battle (only the boss villain is
# fightable).
func _untargetable(u: RTUnit) -> bool:
	return u.is_villain and not _villain_boss

# The villain bails when it would be fought (it's the frontmost-alive enemy), but
# only in a normal battle; on the boss node it stands and fights.
func _check_villain_escape() -> void:
	if _villain_boss or _villain_unit == null:
		return
	if not (is_instance_valid(_villain_unit) and _villain_unit.is_alive()) or _villain_unit.is_escaping:
		return
	if _frontmost_alive(enemy_units) == _villain_unit:
		_villain_do_escape()

func _villain_do_escape() -> void:
	var v := _villain_unit
	_villain_unit = null
	enemy_units.erase(v)
	_unit_state.erase(v.get_instance_id())
	_add_feedback(v.position + Vector2(0.0, -36.0), v.position + Vector2(0.0, -78.0),
			Color(0.86, 0.52, 0.96), _villain_taunt(false))
	if v.has_method("escape"):
		v.escape()
	else:
		v.queue_free()

# A periodic bark while the villain lurks at the back (normal battles only).
func _villain_lurk_taunt(delta: float) -> void:
	if _villain_boss or _villain_unit == null:
		return
	if not (is_instance_valid(_villain_unit) and _villain_unit.is_alive()) or _villain_unit.is_escaping:
		return
	_villain_taunt_timer -= delta
	if _villain_taunt_timer <= 0.0:
		_villain_taunt_timer = 6.0
		var v := _villain_unit
		_add_feedback(v.position + Vector2(0.0, -36.0), v.position + Vector2(0.0, -60.0),
				Color(0.82, 0.55, 0.95), _villain_taunt(false))

# Next taunt line (cycles); boss=true uses the showdown lines.
func _villain_taunt(boss: bool) -> String:
	var lines: Array = GameManager.VILLAIN.get("boss_taunts" if boss else "taunts", [])
	if lines.is_empty():
		return "..."
	var s := String(lines[_villain_taunt_idx % lines.size()])
	_villain_taunt_idx += 1
	return s

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color(0.055, 0.065, 0.090))
	draw_rect(FIELD_RECT, Color(0.15, 0.20, 0.16))
	draw_line(Vector2(FIELD_RECT.get_center().x, FIELD_RECT.position.y),
			Vector2(FIELD_RECT.get_center().x, FIELD_RECT.end.y), Color(0.90, 0.85, 0.45, 0.22), 2.0)
	if phase == Phase.FIGHT and _fight_intro_timer > 0.0:
		draw_rect(FIELD_RECT, Color(0.02, 0.03, 0.04, 0.22))
	# The hotbar + shop slot outlines belong to the quick-battle SHOP only — drawing
	# them in PREP/RESULT/REWARD leaves empty boxes bleeding under those screens.
	if phase == Phase.SHOP:
		for i in range(TEAM_SIZE):
			var slot_rect := Rect2(_slot_pos(i), _slot_size())
			var slot_color := Color(0.10, 0.12, 0.16)
			if selected_slot == i:
				slot_color = Color(0.26, 0.36, 0.30)
			draw_rect(slot_rect, slot_color, false, 2.0)
		for i in range(SHOP_SIZE):
			var shop_rect := Rect2(_shop_pos(i), _shop_size())
			var shop_color := Color(0.14, 0.12, 0.16)
			if selected_shop == i:
				shop_color = Color(0.26, 0.22, 0.34)
			draw_rect(shop_rect, shop_color, false, 2.0)
	for fx: Dictionary in _feedback:
		var t: float = clamp(1.0 - float(fx.get("age", 0.0)) / float(fx.get("life", FEEDBACK_LIFETIME)), 0.0, 1.0)
		var color: Color = fx.get("color", UITheme.GOLD)
		color.a *= t
		var from: Vector2 = fx.get("from", Vector2.ZERO)
		var to: Vector2 = fx.get("to", from)
		if from != to:
			draw_line(from, to, color, 3.0, true)
		draw_circle(to, 8.0 + (1.0 - t) * 8.0, Color(color.r, color.g, color.b, color.a * 0.25))
	if (phase == Phase.PREP or phase == Phase.FIGHT) \
			and _hover_unit != null and is_instance_valid(_hover_unit) and _hover_unit.is_alive():
		_draw_unit_tooltip(_hover_unit)

# Track the unit under the cursor so PREP/FIGHT can show its stats on hover.
func _update_hover() -> void:
	var m := get_global_mouse_position()
	var best: RTUnit = null
	var best_d := 54.0
	for u: RTUnit in player_units + enemy_units:
		if not (is_instance_valid(u) and u.is_alive()):
			continue
		var d := m.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	if best != _hover_unit:
		_hover_unit = best
		queue_redraw()

# A small stats card above the hovered unit (enemy = red border, ally = blue).
func _draw_unit_tooltip(u: RTUnit) -> void:
	var font := ThemeDB.fallback_font
	var is_enemy := enemy_units.has(u)
	var lines: Array = [
		u.unit_name,
		"HP   %d / %d" % [maxi(0, u.hp), u.max_hp],
		"ATK  %d  ·  every %.1fs" % [u.damage_per_attack, u.attack_cooldown],
	]
	var w := 150.0
	for l: String in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22.0)
	var h := 16.0 + float(lines.size()) * 19.0
	# Place the card to the side of the regiment (toward open mid-field) so it does
	# not sit under the unit's own sprites, which render above this canvas draw.
	var anchor: Vector2
	if is_enemy:
		anchor = Vector2(u.position.x - w - 58.0, u.position.y - h * 0.5)
	else:
		anchor = Vector2(u.position.x + 58.0, u.position.y - h * 0.5)
	anchor.x = clampf(anchor.x, 6.0, 1280.0 - w - 6.0)
	anchor.y = clampf(anchor.y, 70.0, 720.0 - h - 6.0)
	var border := Color(0.86, 0.36, 0.36) if is_enemy else Color(0.46, 0.70, 0.96)
	draw_rect(Rect2(anchor, Vector2(w, h)), Color(0.05, 0.06, 0.09, 0.96))
	draw_rect(Rect2(anchor, Vector2(w, h)), border, false, 1.5)
	draw_string(font, anchor + Vector2(11.0, 17.0), String(lines[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.99, 0.82, 0.82) if is_enemy else Color(0.86, 0.92, 1.0))
	draw_string(font, anchor + Vector2(11.0, 36.0), String(lines[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.92, 0.86))
	draw_string(font, anchor + Vector2(11.0, 55.0), String(lines[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.84, 0.88, 0.92))

func _rebuild_ui() -> void:
	for n: Node in _ui_nodes:
		_free_node(n)
	_ui_nodes.clear()

	_add_label("AUTO BATTLER", 28, UITheme.GOLD, Vector2(28.0, 14.0), Vector2(250.0, 36.0))
	if _campaign:
		var et: String = "  ·  Elite" if GameManager.pending_battle_elite else ""
		var odds: String = GameManager.battle_odds(
			GameManager.pending_battle_tier, GameManager.pending_battle_elite, "fight")
		var mod_text: String = ""
		if GameManager.pending_battle_elite:
			mod_text = "   ·   %s" % String(GameManager.elite_modifier_data(GameManager.pending_battle_tier).get("name", ""))
		_add_label("Campaign Battle — Tier %d%s   ·   Odds: %s%s" % [
				GameManager.pending_battle_tier + 1, et, odds, mod_text],
				17, UITheme.TEXT, Vector2(300.0, 20.0), Vector2(760.0, 26.0))
	else:
		_add_label("Round %d   Gold %d   Wins %d/%d   Hearts %d" % [round_no, gold, wins, MAX_WINS, hearts],
				17, UITheme.TEXT, Vector2(300.0, 20.0), Vector2(470.0, 26.0))
	_add_button("Help", Vector2(1010.0, 16.0), Vector2(100.0, 38.0), Color(0.28, 0.30, 0.44), _toggle_help)
	_add_button("Menu", Vector2(1120.0, 16.0), Vector2(104.0, 38.0), UITheme.RED, _on_menu)

	if phase == Phase.SHOP:
		_add_label(_shop_message, 14, UITheme.TEXT_MUTED, Vector2(300.0, 46.0), Vector2(650.0, 22.0))
		_add_label("HOTBAR", 15, UITheme.TEXT_MUTED, Vector2(170.0, 505.0), Vector2(260.0, 22.0))
		_add_label("SHOP", 15, UITheme.TEXT_MUTED, Vector2(705.0, 505.0), Vector2(260.0, 22.0))
		_add_label("NEXT ENEMY", 13, UITheme.TEXT_MUTED, Vector2(1040.0, 92.0), Vector2(160.0, 18.0))
		_add_preview_cards()
		_add_synergy_summary()
		_add_label("Slot 1 deploys at the front. Select a hotbar unit, then move or swap it.",
				13, UITheme.TEXT_MUTED, Vector2(170.0, 626.0), Vector2(450.0, 18.0))
		for i in range(TEAM_SIZE):
			_add_slot_button(i)
		for i in range(SHOP_SIZE):
			_add_shop_button(i)
		_add_button("Move <", Vector2(342.0, 640.0), Vector2(92.0, 42.0), Color(0.22, 0.28, 0.40), _on_move_left)
		_add_button("Move >", Vector2(448.0, 640.0), Vector2(92.0, 42.0), Color(0.22, 0.28, 0.40), _on_move_right)
		_add_button("Sell +1", Vector2(554.0, 640.0), Vector2(92.0, 42.0), Color(0.34, 0.25, 0.22), _on_sell)
		_add_button("Freeze", Vector2(660.0, 640.0), Vector2(92.0, 42.0), Color(0.22, 0.32, 0.42), _on_freeze)
		_add_button("Roll -%d" % _current_roll_cost(), Vector2(766.0, 640.0), Vector2(104.0, 42.0), Color(0.24, 0.30, 0.42), _on_roll)
		_add_button("Fight", Vector2(946.0, 640.0), Vector2(130.0, 42.0), UITheme.GREEN, _on_fight)
	elif phase == Phase.PREP:
		if _prep_step == 0:
			var count := 0
			for s in _lineup_sel:
				if bool(s):
					count += 1
			_add_label("PREP — set lineup & order  (%d / %d troops)" % [count, LINEUP_CAP], 18, UITheme.GOLD,
					Vector2(300.0, 46.0), Vector2(700.0, 24.0))
			_add_label("Tap a troop to select · ◀ ▶ orders them (left = front) · In/Out benches · the hero deploys at the back. Then Deploy.",
					13, UITheme.TEXT_MUTED, Vector2(40.0, 494.0), Vector2(1100.0, 20.0))
			_add_label("FRONT →", 12, UITheme.GOLD.darkened(0.1), Vector2(46.0, 540.0), Vector2(90.0, 18.0))
			for i in range(_pool.size()):
				var bx: float = 138.0 + float(i) * 128.0
				if bx > 1180.0:
					break
				var pcard: Dictionary = _pool[i]["card"]
				var inlineup: bool = bool(_lineup_sel[i])
				var selected: bool = (i == _prep_sel)
				var bc: Color = UITheme.GREEN.darkened(0.1) if inlineup else Color(0.20, 0.22, 0.28)
				if selected:
					bc = bc.lightened(0.30)
				_add_button("%s%s\nLv%d · %s" % ["▸ " if selected else "", _unit_name(_card_id(pcard)),
						int(pcard.get("level", 1)), "in" if inlineup else "bench"],
						Vector2(bx, 516.0), Vector2(120.0, 72.0), bc, Callable(self, "_on_prep_select").bind(i), 12)
			_add_button("◀", Vector2(560.0, 600.0), Vector2(58.0, 42.0), Color(0.22, 0.28, 0.40), _on_prep_reorder.bind(-1))
			_add_button("▶", Vector2(624.0, 600.0), Vector2(58.0, 42.0), Color(0.22, 0.28, 0.40), _on_prep_reorder.bind(1))
			_add_button("In / Out", Vector2(690.0, 600.0), Vector2(112.0, 42.0), Color(0.30, 0.34, 0.28), _on_prep_toggle)
			_add_button("Deploy", Vector2(946.0, 600.0), Vector2(130.0, 42.0), UITheme.GREEN, _on_deploy)
		else:
			var hint := "Drew 3 — play one. Equip → tap a unit · Spell → front enemy · Trap arms. Or Fight to skip."
			if _prep_equip_id != "":
				hint = "Now tap a unit on the field to equip it."
			_add_label("PREP — play a card, then Fight", 18, UITheme.GOLD, Vector2(300.0, 46.0), Vector2(700.0, 24.0))
			_add_label(hint, 13, UITheme.TEXT_MUTED, Vector2(40.0, 552.0), Vector2(900.0, 20.0))
			for j in range(_prep_draw.size()):
				var cdef: Dictionary = GameManager.card_def(String(_prep_draw[j]))
				var cat: String = String(cdef.get("category", ""))
				var pc: Color = Color(0.30, 0.36, 0.28)
				match cat:
					"trap": pc = Color(0.42, 0.26, 0.26)
					"spell": pc = Color(0.36, 0.30, 0.44)
					"aftermath": pc = Color(0.22, 0.26, 0.34)
				_add_button("%s\n[%s]" % [String(cdef.get("name", _prep_draw[j])), cat],
						Vector2(40.0 + float(j) * 200.0, 574.0), Vector2(180.0, 72.0), pc, Callable(self, "_on_prep_draw").bind(j), 13)
			_add_button("Fight", Vector2(946.0, 640.0), Vector2(130.0, 42.0), UITheme.GREEN, _on_prep_fight)
	elif phase == Phase.FIGHT:
		var fight_text := "AUTO FIGHT"
		if _fight_intro_timer > 0.0:
			fight_text = "AUTO FIGHT starts in %.1fs" % _fight_intro_timer
		_fight_label = _add_label(fight_text, 26, UITheme.GOLD, Vector2(500.0, 505.0), Vector2(300.0, 36.0))
		_add_label("Speed %.0fx" % _speed_scale, 15, UITheme.TEXT_MUTED, Vector2(514.0, 542.0), Vector2(120.0, 24.0))
		_add_button("1x", Vector2(446.0, 590.0), Vector2(70.0, 38.0), Color(0.22, 0.28, 0.40), _on_speed_1)
		_add_button("2x", Vector2(526.0, 590.0), Vector2(70.0, 38.0), Color(0.22, 0.28, 0.40), _on_speed_2)
		_add_button("Skip", Vector2(606.0, 590.0), Vector2(92.0, 38.0), Color(0.34, 0.25, 0.22), _on_skip_fight)
	elif phase == Phase.RESULT:
		if _campaign and not _campaign_lost:
			# One consolidated VICTORY screen: gold/relic + deck card + unit upgrade.
			_build_campaign_victory_ui()
		else:
			_add_label(_result_text, 42, UITheme.GOLD, Vector2(360.0, 520.0), Vector2(560.0, 56.0))
			if _duel:
				var recruit_name := _unit_name(GameManager.duel_recruit_type) if UNIT_TYPES.has(GameManager.duel_recruit_type) else String(GameManager.duel_recruit_type).capitalize()
				if GameManager.duel_outcome == 1:
					_add_label("%s joins your army!" % recruit_name, 16, UITheme.TEXT_MUTED, Vector2(360.0, 592.0), Vector2(560.0, 24.0))
					_add_button("Continue", Vector2(560.0, 628.0), Vector2(160.0, 46.0), UITheme.GREEN, _on_duel_continue)
				else:
					# Hero fell — the run is over (cleared in _conclude_duel).
					_add_label("Your hero fell in the duel — the run ends here.", 16, UITheme.TEXT_MUTED, Vector2(360.0, 592.0), Vector2(560.0, 24.0))
					_add_button("To Title", Vector2(560.0, 628.0), Vector2(160.0, 46.0), UITheme.RED, _on_menu)
			elif _campaign:
				# Campaign loss — permadeath, the run ends here.
				_add_label("Your army was wiped out — the run ends here.", 16, UITheme.TEXT_MUTED,
						Vector2(360.0, 592.0), Vector2(560.0, 24.0))
				_add_button("To Title", Vector2(560.0, 628.0), Vector2(160.0, 46.0), UITheme.RED, _on_menu)
			else:
				_add_recap_panel()
				_add_button("Next Shop", Vector2(560.0, 628.0), Vector2(160.0, 46.0), UITheme.BLUE, _on_next_shop)
	elif phase == Phase.REWARD:
		_add_label("PICK A REWARD", 34, UITheme.GOLD, Vector2(420.0, 505.0), Vector2(440.0, 46.0))
		_add_recap_panel(Vector2(330.0, 552.0))
		for i in range(_reward_choices.size()):
			var reward: Dictionary = _reward_choices[i]
			_add_button(_reward_text(reward), Vector2(356.0 + float(i) * 196.0, 620.0),
					Vector2(178.0, 52.0), Color(0.25, 0.34, 0.30), Callable(self, "_on_reward").bind(i), 13)
	elif phase == Phase.GAME_OVER:
		_add_label(_result_text, 42, UITheme.GOLD, Vector2(300.0, 530.0), Vector2(680.0, 56.0))
		_add_button("Restart", Vector2(500.0, 610.0), Vector2(130.0, 46.0), UITheme.GREEN, _on_restart)
		_add_button("Menu", Vector2(650.0, 610.0), Vector2(130.0, 46.0), UITheme.RED, _on_menu)

func _add_label(text: String, font_size: int, color: Color, pos: Vector2, size: Vector2) -> Label:
	var label := UITheme.label(text, font_size, color, pos, size)
	add_child(label)
	_ui_nodes.append(label)
	return label

func _add_button(text: String, pos: Vector2, size: Vector2, color: Color, cb: Callable, font_size: int = 15) -> Button:
	var btn := UITheme.button(text, pos, size, color, cb, font_size)
	add_child(btn)
	_ui_nodes.append(btn)
	return btn

func _add_preview_cards() -> void:
	for i in range(min(3, _enemy_preview.size())):
		var bg := ColorRect.new()
		bg.position = Vector2(1038.0 + float(i) * 66.0, 116.0)
		bg.size = Vector2(58.0, 64.0)
		bg.color = Color(0.18, 0.10, 0.12, 0.92)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		_ui_nodes.append(bg)
		var card: Dictionary = _enemy_preview[i]
		_add_unit_portrait(bg, card, Vector2(6.0, 6.0), Vector2(46.0, 38.0), 1)
		var label := _add_card_label(bg, "L%d" % int(card.get("level", 1)), Vector2(0.0, 44.0), Vector2(58.0, 16.0),
				10, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		_ui_nodes.append(label)

func _add_synergy_summary() -> void:
	var parts := _active_synergy_names()
	var text := "Synergies: none"
	if not parts.is_empty():
		text = "Synergies: " + "  ".join(parts)
	_add_label(text, 12, UITheme.TEXT_MUTED, Vector2(705.0, 494.0), Vector2(500.0, 18.0))

func _add_recap_panel(pos: Vector2 = Vector2(382.0, 582.0)) -> void:
	var mvp := String(_last_recap.get("mvp", "MVP: none"))
	var summary := String(_last_recap.get("summary", "No recap yet."))
	var survivors := String(_last_recap.get("survivors", ""))
	_add_label(summary, 15, UITheme.TEXT, pos, Vector2(520.0, 22.0))
	_add_label(mvp, 14, UITheme.GOLD, pos + Vector2(0.0, 22.0), Vector2(520.0, 22.0))
	_add_label(survivors, 13, UITheme.TEXT_MUTED, pos + Vector2(0.0, 43.0), Vector2(520.0, 22.0))

func _slot_pos(index: int) -> Vector2:
	return Vector2(160.0 + float(index) * 108.0, 528.0)

func _slot_size() -> Vector2:
	return Vector2(96.0, 96.0)

func _shop_pos(index: int) -> Vector2:
	return Vector2(700.0 + float(index) * 138.0, 520.0)

func _shop_size() -> Vector2:
	return Vector2(126.0, 112.0)

func _decorate_unit_card(card_button: Button, card: Dictionary, is_shop_card: bool, index: int) -> void:
	card_button.clip_contents = true
	var size := card_button.size
	if _is_empty_card(card):
		_add_card_label(card_button, "EMPTY", Vector2(0.0, 30.0), size, 13, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_add_card_label(card_button, "SLOT %d" % (index + 1), Vector2(0.0, 52.0), size, 10, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		return

	var unit_id := _card_id(card)
	var stats := _card_stats(card)
	_add_unit_portrait(card_button, card, Vector2((size.x - 56.0) * 0.5, 8.0), Vector2(56.0, 48.0))
	_add_card_label(card_button, _unit_name(unit_id), Vector2(6.0, 56.0), Vector2(size.x - 12.0, 18.0),
			12, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_add_badge(card_button, "L%d" % int(card.get("level", 1)), Vector2(6.0, 7.0),
			Vector2(30.0, 18.0), UITheme.GOLD.darkened(0.25), UITheme.GOLD)
	var item_id := String(card.get("item", ""))
	if ITEM_TYPES.has(item_id):
		_add_badge(card_button, String(ITEM_TYPES[item_id].get("short", "ITM")), Vector2(size.x - 38.0, 7.0),
				Vector2(30.0, 18.0), Color(0.12, 0.20, 0.34), Color(0.64, 0.82, 1.0))
	_add_badge(card_button, "ATK %d" % int(stats["damage"]), Vector2(8.0, size.y - 25.0),
			Vector2(size.x * 0.45, 18.0), Color(0.36, 0.16, 0.16), Color(1.0, 0.66, 0.48))
	_add_badge(card_button, "HP %d" % int(stats["hp"]), Vector2(size.x * 0.52, size.y - 25.0),
			Vector2(size.x * 0.40, 18.0), Color(0.14, 0.27, 0.18), Color(0.60, 1.0, 0.68))

	if is_shop_card:
		_add_badge(card_button, "%dG" % BUY_COST, Vector2(size.x - 38.0, 7.0),
				Vector2(30.0, 18.0), Color(0.30, 0.22, 0.08), UITheme.GOLD)
		if _matching_slot_for_card(card) >= 0:
			_add_badge(card_button, "MERGE", Vector2(8.0, 30.0),
					Vector2(50.0, 18.0), Color(0.30, 0.20, 0.06), UITheme.GOLD)
		if bool(card.get("frozen", false)):
			_add_badge(card_button, "FROZEN", Vector2(8.0, 50.0),
					Vector2(52.0, 18.0), Color(0.08, 0.22, 0.32), Color(0.62, 0.90, 1.0))

func _add_unit_portrait(parent: Control, card: Dictionary, pos: Vector2, size: Vector2, team_id: int = 0) -> void:
	var tex := _unit_texture(card, team_id)
	if tex == null:
		return
	var portrait_bg := ColorRect.new()
	portrait_bg.position = pos
	portrait_bg.size = size
	portrait_bg.color = Color(0.04, 0.05, 0.07, 0.38)
	portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(portrait_bg)

	var image := TextureRect.new()
	image.texture = tex
	image.position = pos
	image.size = size
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)

func _add_badge(parent: Control, text: String, pos: Vector2, size: Vector2, bg_color: Color, text_color: Color) -> void:
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = size
	bg.color = bg_color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	_add_card_label(parent, text, pos + Vector2(2.0, 2.0), size - Vector2(4.0, 2.0), 10, text_color, HORIZONTAL_ALIGNMENT_CENTER)

func _add_card_label(
		parent: Control,
		text: String,
		pos: Vector2,
		size: Vector2,
		font_size: int,
		color: Color,
		align: HorizontalAlignment
) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _unit_texture(card: Dictionary, team_id: int) -> Texture2D:
	if _is_empty_card(card):
		return null
	var unit_id := _card_id(card)
	var stats: Dictionary = UNIT_TYPES[unit_id]
	var sprite_key := String(stats.get("sprite_key", unit_id))
	var team_name := "player" if team_id == 0 else "enemy"
	return load("res://assets/units/%s_%s.png" % [sprite_key, team_name])

func _add_slot_button(index: int) -> void:
	var color := Color(0.18, 0.22, 0.30)
	var card: Dictionary = team[index]
	if not _is_empty_card(card):
		color = Color(0.20, 0.36, 0.46)
	if selected_slot == index:
		color = color.lightened(0.18)
	var btn := _add_button("", _slot_pos(index), _slot_size(),
			color, Callable(self, "_on_slot").bind(index), 12)
	_decorate_unit_card(btn, card, false, index)

func _add_shop_button(index: int) -> void:
	var card: Dictionary = shop[index]
	var color := Color(0.28, 0.24, 0.34)
	if bool(card.get("frozen", false)):
		color = Color(0.22, 0.34, 0.42)
	if selected_shop == index:
		color = color.lightened(0.18)
	var btn := _add_button("", _shop_pos(index), _shop_size(),
			color, Callable(self, "_on_shop").bind(index), 12)
	_decorate_unit_card(btn, card, true, index)

func _on_shop(index: int) -> void:
	if _freeze_mode:
		selected_shop = index
		_toggle_freeze(index)
		_freeze_mode = false
		_rebuild_ui()
		return
	var target_slot := _find_buy_slot(index)
	if target_slot < 0:
		_shop_message = "No hotbar room. Sell a unit, or click a duplicate to merge."
	else:
		_try_buy_shop_to_slot(index, target_slot)
	_rebuild_ui()

func _on_slot(index: int) -> void:
	var slot_card: Dictionary = team[index]
	if not _is_empty_card(slot_card):
		if selected_slot >= 0 and selected_slot != index and not _is_empty_card(team[selected_slot]):
			var tmp: Dictionary = team[selected_slot]
			team[selected_slot] = team[index]
			team[index] = tmp
			_shop_message = "Team order changed."
		selected_slot = index
		selected_shop = -1
		_shop_message = "%s selected. Click another unit to swap, or sell it." % _unit_name(_card_id(team[index]))
	elif selected_slot >= 0 and selected_slot != index and not _is_empty_card(team[selected_slot]):
		team[index] = team[selected_slot]
		team[selected_slot] = {}
		selected_slot = index
		_shop_message = "Moved unit to an empty slot."
	_rebuild_ui()

func _on_sell() -> void:
	if selected_slot < 0 or selected_slot >= TEAM_SIZE or _is_empty_card(team[selected_slot]):
		_shop_message = "Select a hotbar unit to sell."
		_rebuild_ui()
		return
	var refund := SELL_REFUND + int(team[selected_slot].get("level", 1)) - 1
	_shop_message = "Sold %s for %d gold." % [_unit_name(_card_id(team[selected_slot])), refund]
	team[selected_slot] = {}
	gold += refund
	selected_slot = -1
	_rebuild_ui()

func _on_freeze() -> void:
	if selected_shop >= 0 and selected_shop < shop.size():
		_toggle_freeze(selected_shop)
		_rebuild_ui()
		return
	_freeze_mode = true
	_shop_message = "Freeze mode: click a shop unit to freeze or unfreeze it."
	_rebuild_ui()

func _toggle_freeze(index: int) -> void:
	if index < 0 or index >= shop.size():
		return
	shop[index]["frozen"] = not bool(shop[index].get("frozen", false))
	_shop_message = "%s %s." % [
		_unit_name(_card_id(shop[index])),
		"frozen" if bool(shop[index].get("frozen", false)) else "unfrozen"
	]

func _on_move_left() -> void:
	_move_selected_slot(-1)

func _on_move_right() -> void:
	_move_selected_slot(1)

func _move_selected_slot(direction: int) -> void:
	if selected_slot < 0 or selected_slot >= TEAM_SIZE or _is_empty_card(team[selected_slot]):
		_shop_message = "Select a hotbar unit to reorder."
		_rebuild_ui()
		return
	var target := selected_slot + direction
	if target < 0 or target >= TEAM_SIZE:
		_shop_message = "That unit is already at the edge of the hotbar."
		_rebuild_ui()
		return
	var tmp: Dictionary = team[target]
	team[target] = team[selected_slot]
	team[selected_slot] = tmp
	selected_slot = target
	_shop_message = "Hotbar order changed."
	_rebuild_ui()

func _on_roll() -> void:
	var cost := _current_roll_cost()
	if gold < cost:
		_shop_message = "Not enough gold to roll."
		_rebuild_ui()
		return
	gold -= cost
	_reroll_discount_next = false
	_roll_shop(false)
	selected_shop = -1
	_freeze_mode = false
	_shop_message = "Shop rolled. Frozen units stayed."
	_rebuild_ui()

func _on_fight() -> void:
	if not _has_team():
		_shop_message = "Buy at least one unit before fighting."
		_rebuild_ui()
		return
	phase = Phase.FIGHT
	Music.play("battle")
	selected_shop = -1
	selected_slot = -1
	_spawn_fight()
	_rebuild_ui()

func _on_speed_1() -> void:
	_speed_scale = 1.0
	_rebuild_ui()

func _on_speed_2() -> void:
	_speed_scale = 2.0
	_rebuild_ui()

func _on_skip_fight() -> void:
	if phase != Phase.FIGHT:
		return
	_fight_intro_timer = 0.0
	for _i in range(600):
		if phase != Phase.FIGHT:
			return
		_process(1.0 / 30.0)

func _on_next_shop() -> void:
	_open_next_shop("New shop. Build around your leveled units.")

func _open_next_shop(message: String) -> void:
	_clear_units()
	round_no += 1
	gold = GOLD_PER_ROUND
	_roll_shop(false)
	_refresh_enemy_preview()
	phase = Phase.SHOP
	Music.play("prebattle")   # back to the build phase between rounds
	_shop_message = message
	_rebuild_ui()

func _on_reward(index: int) -> void:
	if index < 0 or index >= _reward_choices.size():
		return
	var reward: Dictionary = _reward_choices[index]
	match String(reward.get("type", "")):
		"unit":
			var slot := _first_empty_slot()
			if slot >= 0:
				team[slot] = _make_shop_card(String(reward.get("unit", "soldier")))
				_shop_message = "Reward unit added to hotbar."
			else:
				gold += BUY_COST
				_shop_message = "Hotbar full. Reward converted to gold."
		"item":
			var slot := _first_occupied_slot()
			if selected_slot >= 0 and selected_slot < TEAM_SIZE and not _is_empty_card(team[selected_slot]):
				slot = selected_slot
			if slot >= 0:
				team[slot]["item"] = String(reward.get("item", "banner"))
				_shop_message = "%s equipped." % String(ITEM_TYPES[String(reward.get("item", "banner"))].get("name", "Item"))
			else:
				gold += 2
				_shop_message = "No unit to equip. Item converted to gold."
		"gold":
			gold += int(reward.get("amount", 3))
			_shop_message = "+%d gold." % int(reward.get("amount", 3))
		"discount":
			_reroll_discount_next = true
			_shop_message = "Next roll is free."
	var message := _shop_message
	_reward_choices.clear()
	_open_next_shop(message)

func _on_restart() -> void:
	get_tree().reload_current_scene()

func _on_menu() -> void:
	get_tree().change_scene_to_file("res://src/title/title.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_toggle_help()
	# PREP: after picking an Equip card, tap a unit on the field to equip it.
	if phase == Phase.PREP and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_prep_click(event.position)

# Apply a pending (drawn) Equip card to the tapped player unit (single-target).
func _prep_click(pos: Vector2) -> void:
	if _prep_equip_id == "":
		return
	var hit: RTUnit = null
	for u: RTUnit in player_units:
		if is_instance_valid(u) and u.is_alive() and pos.distance_to(u.position) <= u.radius + 14.0:
			hit = u
			break
	if hit == null:
		return
	hit.apply_effect(GameManager.card_def(_prep_equip_id).get("effect", {}))
	_consume_drawn(_prep_equip_id)
	_rebuild_ui()

func _toggle_help() -> void:
	if _help_overlay != null:
		_help_overlay.queue_free()
		_help_overlay = null
		return
	_help_overlay = UITheme.help_overlay("Auto-Battler — Help", HELP_BODY, _toggle_help)
	add_child(_help_overlay)

func _roll_shop(_initial: bool) -> void:
	var previous := shop.duplicate(true)
	shop.clear()
	for i in range(SHOP_SIZE):
		if not _initial and i < previous.size() and bool(previous[i].get("frozen", false)):
			shop.append(previous[i])
		else:
			shop.append(_make_shop_card(_random_unit_id()))

func _current_roll_cost() -> int:
	return 0 if _reroll_discount_next else ROLL_COST

func _refresh_enemy_preview() -> void:
	_enemy_preview = _enemy_roster(max(1, _filled_slots()))

func _generate_reward_choices() -> void:
	_reward_choices = [
		{"type": "unit", "unit": _random_unit_id()},
		{"type": "item", "item": _random_item_id()},
		{"type": "gold", "amount": 3 + int(round_no / 2)},
	]
	if _rng.randi_range(0, 1) == 0:
		_reward_choices[2] = {"type": "discount"}

func _reward_text(reward: Dictionary) -> String:
	match String(reward.get("type", "")):
		"unit":
			return "Free\n%s" % _unit_name(String(reward.get("unit", "soldier")))
		"item":
			var item_id := String(reward.get("item", "banner"))
			return "Equip\n%s" % String(ITEM_TYPES[item_id].get("name", "Item"))
		"gold":
			return "+%d\nGold" % int(reward.get("amount", 3))
		"discount":
			return "Free\nNext Roll"
	return "Reward"

func _random_item_id() -> String:
	var keys := ITEM_TYPES.keys()
	return String(keys[_rng.randi_range(0, keys.size() - 1)])

func _filled_slots() -> int:
	var count := 0
	for card: Dictionary in team:
		if not _is_empty_card(card):
			count += 1
	return count

func _first_empty_slot() -> int:
	for i in range(TEAM_SIZE):
		if _is_empty_card(team[i]):
			return i
	return -1

func _first_occupied_slot() -> int:
	for i in range(TEAM_SIZE):
		if not _is_empty_card(team[i]):
			return i
	return -1

func _try_buy_shop_to_slot(shop_index: int, slot_index: int) -> bool:
	if shop_index < 0 or shop_index >= shop.size() or slot_index < 0 or slot_index >= TEAM_SIZE:
		return false
	if gold < BUY_COST:
		_shop_message = "Not enough gold."
		return false
	var shop_card: Dictionary = shop[shop_index]
	var slot_card: Dictionary = team[slot_index]
	if _is_empty_card(slot_card):
		team[slot_index] = _copy_card(shop_card)
		gold -= BUY_COST
		_after_shop_card_bought(shop_index)
		selected_shop = -1
		selected_slot = slot_index
		_shop_message = "Bought %s into hotbar slot %d." % [_unit_name(_card_id(shop_card)), slot_index + 1]
		return true
	if _card_id(slot_card) == _card_id(shop_card) and int(slot_card.get("level", 1)) < MAX_LEVEL:
		gold -= BUY_COST
		var new_level := _level_up_slot(slot_index)
		_after_shop_card_bought(shop_index)
		selected_shop = -1
		selected_slot = slot_index
		_shop_message = "%s leveled up to L%d." % [
			_unit_name(_card_id(slot_card)),
			new_level
		]
		return true
	_shop_message = "That slot is occupied. Pick an empty slot, or merge into the same unit."
	return false

func _find_buy_slot(shop_index: int) -> int:
	if shop_index < 0 or shop_index >= shop.size():
		return -1
	var shop_id := _card_id(shop[shop_index])
	if selected_slot >= 0 and selected_slot < TEAM_SIZE:
		var selected_card: Dictionary = team[selected_slot]
		if _is_empty_card(selected_card):
			return selected_slot
		if _card_id(selected_card) == shop_id and int(selected_card.get("level", 1)) < MAX_LEVEL:
			return selected_slot
	for i in range(TEAM_SIZE):
		var card: Dictionary = team[i]
		if not _is_empty_card(card) and _card_id(card) == shop_id and int(card.get("level", 1)) < MAX_LEVEL:
			return i
	for i in range(TEAM_SIZE):
		if _is_empty_card(team[i]):
			return i
	return -1

func _matching_slot_for_card(shop_card: Dictionary) -> int:
	var shop_id := _card_id(shop_card)
	for i in range(TEAM_SIZE):
		var card: Dictionary = team[i]
		if not _is_empty_card(card) and _card_id(card) == shop_id and int(card.get("level", 1)) < MAX_LEVEL:
			return i
	return -1

func _unit_counts(cards: Array) -> Dictionary:
	var counts := {}
	for card: Dictionary in cards:
		if _is_empty_card(card):
			continue
		var unit_id := _card_id(card)
		counts[unit_id] = int(counts.get(unit_id, 0)) + 1
	return counts

func _active_synergy_names() -> Array:
	var counts := _unit_counts(team)
	var out: Array = []
	if int(counts.get("soldier", 0)) >= 2:
		out.append("2 Infantry: team armor")
	if int(counts.get("archer", 0)) >= 2:
		out.append("2 Archers: ranged damage")
	if int(counts.get("scout", 0)) >= 2:
		out.append("2 Cavalry: charge damage")
	if int(counts.get("healer", 0)) >= 2:
		out.append("2 Spearmen: team grit")
	return out

func _has_team() -> bool:
	for card: Dictionary in team:
		if not _is_empty_card(card):
			return true
	return false

func _unit_name(unit_id: String) -> String:
	return String(UNIT_TYPES[unit_id].get("name", unit_id.capitalize()))

func _random_unit_id() -> String:
	var keys := UNIT_TYPES.keys()
	return String(keys[_rng.randi_range(0, keys.size() - 1)])

func _make_shop_card(unit_id: String) -> Dictionary:
	return {"id": unit_id, "level": 1, "xp": 0, "frozen": false}

func _copy_card(card: Dictionary) -> Dictionary:
	var out := {
		"id": _card_id(card),
		"level": int(card.get("level", 1)),
		"xp": int(card.get("xp", 0)),
	}
	if String(card.get("item", "")) != "":
		out["item"] = String(card.get("item", ""))
	return out

func _is_empty_card(card: Dictionary) -> bool:
	return card.is_empty() or not card.has("id") or String(card.get("id", "")) == ""

func _card_id(card: Dictionary) -> String:
	return String(card.get("id", "soldier"))

func _card_stats(card: Dictionary, synergy_counts: Dictionary = {}) -> Dictionary:
	var unit_id := _card_id(card)
	var stats: Dictionary = UNIT_TYPES[unit_id]
	var level := int(card.get("level", 1))
	var soldier_count := int(stats.get("soldier_count", 1))
	var hp_per_soldier := int(stats.get("hp_per_soldier", 1))
	var base_hp := soldier_count * hp_per_soldier
	var base_damage := int(stats.get("damage_per_attack", 1))
	var hp := base_hp + (level - 1) * 36
	var damage := base_damage + (level - 1) * 4
	var item_id := String(card.get("item", ""))
	if ITEM_TYPES.has(item_id):
		var item: Dictionary = ITEM_TYPES[item_id]
		hp += int(item.get("hp", 0))
		damage += int(item.get("damage", 0))
	if synergy_counts.get("soldier", 0) >= 2:
		hp += 18
	if synergy_counts.get("archer", 0) >= 2 and unit_id == "archer":
		damage += 3
	if synergy_counts.get("scout", 0) >= 2 and unit_id == "scout":
		damage += 2
	if synergy_counts.get("healer", 0) >= 2:
		hp += 10
	return {
		"hp": hp,
		"damage": damage,
	}

func _after_shop_card_bought(index: int) -> void:
	shop[index] = _make_shop_card(_random_unit_id())

func _level_up_slot(index: int) -> int:
	var card: Dictionary = team[index]
	if _is_empty_card(card):
		return 1
	var level := int(card.get("level", 1))
	level = min(MAX_LEVEL, level + 1)
	card["level"] = level
	card["xp"] = 0
	team[index] = card
	return level

func _spawn_fight() -> void:
	_clear_units()
	_unit_state.clear()
	_feedback.clear()
	_last_recap.clear()
	var player_roster: Array = []
	for card: Dictionary in team:
		if not _is_empty_card(card):
			player_roster.append(_copy_card(card))
	var player_counts := _unit_counts(player_roster)
	var enemy_roster := _enemy_preview.duplicate(true)
	if enemy_roster.is_empty():
		enemy_roster = _enemy_roster(player_roster.size())
	var enemy_counts := _unit_counts(enemy_roster)
	var player_positions := _formation_positions(player_roster.size(), 0)
	for i in range(player_roster.size()):
		player_units.append(_spawn_unit(player_roster[i], 0, player_positions[i], 1.0, player_counts))
	var enemy_positions := _formation_positions(enemy_roster.size(), 1)
	for i in range(enemy_roster.size()):
		enemy_units.append(_spawn_unit(enemy_roster[i], 1, enemy_positions[i], 1.0 + float(round_no - 1) * 0.06, enemy_counts))
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0
	_start_abilities_applied = false
	_speed_scale = 2.0

# ---------------------------------------------------------------------------
# Campaign single-fight (battle_mode "auto")
# ---------------------------------------------------------------------------
func _campaign_card(unit_type: String) -> Dictionary:
	return {
		"id": String(CAMPAIGN_CARD_MAP.get(unit_type, "soldier")),
		"level": int(CAMPAIGN_CARD_LEVEL.get(unit_type, 1)),
		"xp": 0,
	}

func _start_campaign_fight() -> void:
	_clear_units()
	_unit_state.clear()
	_feedback.clear()
	_last_recap.clear()
	var tier: int = GameManager.pending_battle_tier
	var elite: bool = GameManager.pending_battle_elite
	# Build the player POOL (hero + roster). The hero is always available; the
	# player chooses a lineup (hotbar) from this pool in PREP (#10).
	# The POOL is the roster troops only. The hero always deploys on TOP of the
	# chosen lineup (it is not one of the selectable slots), so picking N troops
	# fields N troops + the hero. Pool order = front-to-back deploy order.
	_hero_unit = null
	_prep_sel = -1
	_pool = []
	for entry: Dictionary in GameManager.player_roster:
		_pool.append({"card": _campaign_card(String(entry["type"])), "entry": entry})
	# Default lineup: the first LINEUP_CAP troops.
	_lineup_sel = []
	for i in range(_pool.size()):
		_lineup_sel.append(i < LINEUP_CAP)

	# Enemy team — spawned now so it's visible during PREP.
	var e_types: Array = GameManager.get_battle_enemy_roster(tier, elite)
	var hp_mult: float = GameManager.get_hp_multiplier(tier, elite)
	var e_cards: Array = []
	for t in e_types:
		e_cards.append(_campaign_card(String(t)))
	var e_counts := _unit_counts(e_cards)
	var e_pos := _formation_positions(e_cards.size(), 1)
	for i in range(e_cards.size()):
		enemy_units.append(_spawn_unit(e_cards[i], 1, e_pos[i], hp_mult, e_counts))
	if elite:
		var m := GameManager.elite_modifier_data(tier)
		for u: RTUnit in enemy_units:
			u.max_hp = maxi(1, int(round(float(u.max_hp) * float(m.get("hp", 1.0)))))
			u.hp = u.max_hp
			u.damage_per_attack = maxi(1, int(round(float(u.damage_per_attack) * float(m.get("dmg", 1.0)))))
			u.move_speed_px = float(u.move_speed_px) * float(m.get("speed", 1.0))
			if u.has_method("_refresh_hp_bar"):
				u.call("_refresh_hp_bar")

	# The recurring villain joins every campaign battle. On the final tier it IS the
	# boss and fights to the death; on every other node it lurks at the back and
	# teleports away (with a taunt) the moment it would be fought.
	_villain_unit = null
	_villain_taunt_idx = 0
	_villain_taunt_timer = 3.5
	_villain_boss = (tier >= GameManager.MAP_TIERS - 1)
	var v_card := {
		"id": String(GameManager.VILLAIN.get("archetype", "warlord")),
		"sprite_key": "villain", "villain": true,
		"level": 2 + tier / 2, "xp": 0,
	}
	var v_pos := Vector2(FIELD_RECT.end.x - 80.0, FIELD_RECT.position.y + FIELD_RECT.size.y * 0.5)
	var vu := _spawn_unit(v_card, 1, v_pos, hp_mult)
	vu.unit_name = String(GameManager.VILLAIN.get("name", "Vex"))
	if _villain_boss:
		vu.max_hp = maxi(1, int(round(float(vu.max_hp) * 4.0)))
		vu.hp = vu.max_hp
		vu.damage_per_attack = maxi(1, int(round(float(vu.damage_per_attack) * 1.6)))
		if vu.has_method("_refresh_hp_bar"):
			vu.call("_refresh_hp_bar")
	enemy_units.append(vu)   # appended last = back of the enemy line
	_villain_unit = vu
	_add_feedback(v_pos + Vector2(0.0, -42.0), v_pos + Vector2(0.0, -72.0),
			Color(0.86, 0.52, 0.96), _villain_taunt(_villain_boss))

	_armed_traps = []
	_prep_draw = []
	_prep_equip_id = ""
	_prep_step = 0
	phase = Phase.PREP
	Music.play("prebattle")   # campaign pre-fight: loop the intro until fight starts
	_rebuild_ui()

# The hero's combat card (archetype + level, scaled by the skill tree).
func _build_hero_card() -> Dictionary:
	var hd := GameManager.hero_data()
	return {
		"id": String(hd["fight_archetype"]),
		"sprite_key": String(hd.get("sprite_key", hd["fight_archetype"])),
		"level": int(hd["fight_level"]) + GameManager.hero_tree_bonus_level(),
		"xp": 0, "hero": true,
	}

# Spawn the chosen lineup (hero + chosen troops), apply mults + aura, then draw 3
# cards for the play step.
func _deploy_lineup() -> void:
	# Chosen troops in player order (pool order), then the hero appended LAST so it
	# engages last (front-vs-front steps up by array order) — the general fights
	# only once its screen of troops has fallen.
	var deploy_cards: Array = []
	var deploy_entries: Array = []
	for i in range(_pool.size()):
		if bool(_lineup_sel[i]):
			deploy_cards.append(_pool[i]["card"])
			deploy_entries.append(_pool[i]["entry"])
	var troop_count := deploy_cards.size()
	if GameManager.has_hero():
		deploy_cards.append(_build_hero_card())
		deploy_entries.append(null)
	if deploy_cards.is_empty():
		return
	# Defensive formation: troops form a forward wedge, the hero sits centred behind
	# them like a general.
	var pos := _player_deploy_positions(troop_count, GameManager.has_hero())
	var p_counts := _unit_counts(deploy_cards)
	for i in range(deploy_cards.size()):
		var u := _spawn_unit(deploy_cards[i], 0, pos[i], 1.0, p_counts)
		_unit_state[u.get_instance_id()]["roster_entry"] = deploy_entries[i]
		u.damage_per_attack = maxi(1, int(round(float(u.damage_per_attack) * GameManager.rt_player_damage_mult())))
		u.max_hp = maxi(1, int(round(float(u.max_hp) * GameManager.rt_player_hp_mult())))
		u.hp = u.max_hp
		if bool(deploy_cards[i].get("hero", false)):
			u.max_hp = maxi(1, int(round(float(u.max_hp) * GameManager.hero_hp_mult_tree())))
			u.hp = u.max_hp
			u.damage_per_attack = maxi(1, int(round(float(u.damage_per_attack) * GameManager.hero_damage_mult_tree())))
			u.attack_cooldown = maxf(0.2, u.attack_cooldown * GameManager.hero_attack_cooldown_mult())
			_hero_unit = u
		player_units.append(u)
	if GameManager.has_hero():
		_apply_hero_aura()
	_prep_draw = GameManager.cards_draw(3)
	_prep_step = 1
	_rebuild_ui()

# Player team start positions: `troop_count` troops in a forward defensive wedge
# (front-of-order troop is the spearhead), then the hero centred well behind them.
# Returns one Vector2 per deployed unit, troops first then the hero (if any).
func _player_deploy_positions(troop_count: int, has_hero: bool) -> Array:
	var cy := FIELD_RECT.position.y + FIELD_RECT.size.y * 0.5
	var front_x := 500.0
	var out: Array = []
	for i in range(troop_count):
		# lane: 0, +1, -1, +2, -2, … — front-of-order troop spearheads, flanks recede.
		var lane := int((i + 1) / 2)
		if i % 2 == 0:
			lane = -lane
		out.append(Vector2(front_x - absf(float(lane)) * 36.0, cy + float(lane) * 80.0))
	if has_hero:
		out.append(Vector2(front_x - 140.0, cy))   # general, centred behind the screen
	return out

# Start the actual fight (after PREP, or directly when there's nothing to play).
func _begin_fight() -> void:
	# Fire combat-start traps set during prep.
	var rest: Array = []
	for trap in _armed_traps:
		if String(trap.get("trigger", "")) == "combat_start":
			_fire_trap(trap)
		else:
			rest.append(trap)
	_armed_traps = rest
	_below50_triggered = false
	_prep_equip_id = ""
	phase = Phase.FIGHT
	Music.play("battle")
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0
	_start_abilities_applied = false
	_speed_scale = 2.0
	_rebuild_ui()

func _on_prep_select(i: int) -> void:
	if _prep_step != 0 or i < 0 or i >= _pool.size():
		return
	_prep_sel = i
	_rebuild_ui()

func _on_prep_toggle() -> void:
	if _prep_step != 0 or _prep_sel < 0 or _prep_sel >= _lineup_sel.size():
		return
	if not bool(_lineup_sel[_prep_sel]):
		var count := 0
		for s in _lineup_sel:
			if bool(s):
				count += 1
		if count >= LINEUP_CAP:
			return   # lineup is full
	_lineup_sel[_prep_sel] = not bool(_lineup_sel[_prep_sel])
	_rebuild_ui()

# Move the selected troop one slot toward the front (dir -1) or back (dir +1).
# Reorders the pool AND its parallel selection so deploy order follows.
func _on_prep_reorder(dir: int) -> void:
	if _prep_step != 0 or _prep_sel < 0:
		return
	var j := _prep_sel + dir
	if j < 0 or j >= _pool.size():
		return
	var tmp_card = _pool[_prep_sel]
	_pool[_prep_sel] = _pool[j]
	_pool[j] = tmp_card
	var tmp_sel = _lineup_sel[_prep_sel]
	_lineup_sel[_prep_sel] = _lineup_sel[j]
	_lineup_sel[j] = tmp_sel
	_prep_sel = j
	_rebuild_ui()

func _on_deploy() -> void:
	if _prep_step == 0:
		_deploy_lineup()

# Play one of the 3 drawn cards (#10). Equip waits for a unit tap; Spell hits the
# front enemy; Trap arms. The other two drawn cards return to the deck.
func _on_prep_draw(j: int) -> void:
	if _prep_step != 1 or j < 0 or j >= _prep_draw.size():
		return
	var cdef: Dictionary = GameManager.card_def(String(_prep_draw[j]))
	match String(cdef.get("category", "")):
		"equip":
			_prep_equip_id = String(_prep_draw[j])
			_rebuild_ui()
			return
		"spell":
			var e := _frontmost_alive(enemy_units)
			if e != null:
				e.apply_effect(cdef.get("effect", {}))
		"trap":
			_armed_traps.append(cdef)
		_:
			pass   # aftermath has no prep target — just discards
	_consume_drawn(String(_prep_draw[j]))
	_rebuild_ui()

func _consume_drawn(played_id: String) -> void:
	GameManager.card_graveyard.append(played_id)
	for id in _prep_draw:
		if String(id) != played_id:
			GameManager.card_deck.append(String(id))
	_prep_draw = []
	_prep_equip_id = ""
	GameManager.save_run()

func _on_prep_fight() -> void:
	GameManager.cards_return(_prep_draw)   # unplayed cards go back to the deck
	_prep_draw = []
	_prep_equip_id = ""
	GameManager.save_run()
	_begin_fight()

# Resolve a trap's effect against the right target.
func _fire_trap(trap: Dictionary) -> void:
	var effect: Dictionary = trap.get("effect", {})
	match String(effect.get("kind", "")):
		"damage":
			var e := _frontmost_alive(enemy_units)
			if e != null:
				e.apply_effect(effect)
		"heal_pct", "heal_full":
			var a := _frontmost_alive(player_units)
			if a != null:
				a.apply_effect(effect)
		"team_damage_pct":
			for u: RTUnit in player_units:
				if is_instance_valid(u) and u.is_alive():
					u.apply_effect({"kind": "damage_pct", "value": float(effect.get("value", 0.0))})

# Draft the chosen reward card into the deck (Spec B) on the result screen.
func _on_pick_reward_card(i: int) -> void:
	if i < 0 or i >= _card_reward_offer.size():
		return
	GameManager.card_take_reward(String(_card_reward_offer[i]))
	GameManager.save_run()
	# Reward claimed — the upgrade option is spent too (one reward per win).
	_card_reward_offer = []
	_upgrade_offer = []
	_upgrade_pick = ""
	_reward_taken = true
	_rebuild_ui()

# One consolidated VICTORY screen for a campaign win: result + gold/relic + recap,
# then the player claims ONE reward — a deck card OR a unit upgrade — then Continue.
# Replaces the old in-battle screen plus the separate map reward popup.
func _build_campaign_victory_ui() -> void:
	var bg := ColorRect.new()
	bg.position = Vector2(220.0, 70.0)
	bg.size = Vector2(840.0, 628.0)
	bg.color = Color(0.07, 0.09, 0.07, 0.97)
	add_child(bg)
	_ui_nodes.append(bg)
	var accent := ColorRect.new()
	accent.position = Vector2(220.0, 70.0)
	accent.size = Vector2(840.0, 3.0)
	accent.color = Color(0.55, 0.70, 0.40)
	add_child(accent)
	_ui_nodes.append(accent)

	_center_label("VICTORY", 44, UITheme.GOLD, 92.0)
	var sub := "+%d gold" % _campaign_gold
	if _campaign_relic != "":
		sub += "   ·   Relic found: %s" % String(GameManager.RELICS[_campaign_relic]["name"])
	_center_label(sub, 17, Color(0.85, 0.88, 0.72), 152.0)
	var survivors := String(_last_recap.get("survivors", ""))
	if survivors != "":
		_center_label(survivors, 13, UITheme.TEXT_MUTED, 180.0)

	if _reward_taken:
		_center_label("✓ reward claimed", 18, UITheme.GREEN, 350.0)
	elif _upgrade_pick != "":
		# Upgrade chosen — assign it to a surviving unit (or go Back).
		var uname := String(GameManager.UPGRADE_TYPES[_upgrade_pick]["name"])
		_center_label("Assign '%s' to a unit" % uname, 20, Color(0.92, 0.86, 0.66), 232.0)
		var roster: Array = GameManager.player_roster
		var first_row: int = mini(5, roster.size())
		var start_x: float = (1280.0 - (float(first_row) * 150.0 - 10.0)) * 0.5
		for i in range(roster.size()):
			var entry: Dictionary = roster[i]
			var udata: Dictionary = GameManager.UNIT_TYPES[entry["type"]]
			_add_button("%s\nHP %d" % [String(udata["name"]), int(entry["hp"])],
					Vector2(start_x + float(i % 5) * 150.0, 296.0 + float(i / 5) * 76.0), Vector2(140.0, 66.0),
					Color(udata["color"]).darkened(0.2), Callable(self, "_on_assign_upgrade").bind(i), 12)
		_add_button("← Back", Vector2(560.0, 556.0), Vector2(160.0, 38.0),
				Color(0.30, 0.30, 0.34), _on_skip_upgrade, 14)
	else:
		# The choice — claim ONE reward.
		_center_label("Choose one reward", 19, UITheme.TEXT, 222.0)
		# Option A — a deck card (Spec B).
		_add_label("Add a card to your deck", 15, Color(0.70, 0.84, 0.72), Vector2(270.0, 258.0), Vector2(540.0, 20.0))
		for ci in range(_card_reward_offer.size()):
			var cd: Dictionary = GameManager.card_def(String(_card_reward_offer[ci]))
			_add_button(String(cd.get("name", _card_reward_offer[ci])),
					Vector2(270.0 + float(ci) * 246.0, 284.0), Vector2(228.0, 54.0),
					Color(0.25, 0.34, 0.30), Callable(self, "_on_pick_reward_card").bind(ci), 13)
		# Option B — a unit upgrade (pick, then assign). Only offered when troops
		# survived; the hero isn't a roster unit, so a hero-only survival has nothing
		# to upgrade and the card becomes the only reward.
		var can_upgrade: bool = not GameManager.player_roster.is_empty()
		_add_label("Upgrade a unit", 15, Color(0.84, 0.78, 0.62), Vector2(270.0, 384.0), Vector2(540.0, 20.0))
		if can_upgrade:
			_center_label("— or —", 14, UITheme.TEXT_MUTED, 354.0)
			for i in range(_upgrade_offer.size()):
				var uid := String(_upgrade_offer[i])
				var data: Dictionary = GameManager.UPGRADE_TYPES[uid]
				var ub := _add_button("%s\n%s" % [String(data["name"]), String(data["desc"])],
						Vector2(270.0 + float(i) * 246.0, 410.0), Vector2(228.0, 92.0),
						Color(data["color"]).darkened(0.35), Callable(self, "_on_pick_upgrade").bind(i), 13)
				ub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			_add_label("(no surviving troops to upgrade — take the card)", 13, UITheme.TEXT_MUTED,
					Vector2(270.0, 412.0), Vector2(540.0, 20.0))

	_add_button("Continue", Vector2(560.0, 638.0), Vector2(160.0, 46.0), UITheme.GREEN, _on_campaign_continue, 18)

# Centred label across the victory panel (220..1060).
func _center_label(text: String, fs: int, color: Color, y: float) -> void:
	var l := _add_label(text, fs, color, Vector2(220.0, y), Vector2(840.0, float(fs) + 10.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _on_pick_upgrade(i: int) -> void:
	if i < 0 or i >= _upgrade_offer.size():
		return
	_upgrade_pick = String(_upgrade_offer[i])
	_rebuild_ui()

func _on_assign_upgrade(roster_index: int) -> void:
	if _upgrade_pick == "" or roster_index < 0 or roster_index >= GameManager.player_roster.size():
		return
	GameManager.apply_upgrade(roster_index, _upgrade_pick)
	GameManager.save_run()
	# Reward claimed — the deck-card option is spent too (one reward per win).
	_card_reward_offer = []
	_upgrade_offer = []
	_upgrade_pick = ""
	_reward_taken = true
	_rebuild_ui()

# Back out of the upgrade-assign step to the reward choice (nothing claimed yet).
func _on_skip_upgrade() -> void:
	_upgrade_pick = ""
	_rebuild_ui()

# Command leader aura (Spec A): when the hero fights in the lineup it buffs the
# whole team at battle start, scaled by the Command tree (hero_aura_mult_tree).
# The aura family is the hero's own buff id (aegis=+HP, march=+dmg, warchest=heal).
func _apply_hero_aura() -> void:
	if not GameManager.has_hero():
		return
	var buff: Dictionary = GameManager.hero_data().get("buff", {})
	var buff_id := String(buff.get("id", ""))
	var am: float = GameManager.hero_aura_mult_tree()   # hero is in the lineup -> 100%
	for u: RTUnit in player_units:
		if not is_instance_valid(u):
			continue
		match buff_id:
			"aegis":
				u.max_hp = maxi(1, int(round(float(u.max_hp) * (1.0 + 0.15 * am))))
				u.hp = u.max_hp
				if u.has_method("_refresh_hp_bar"):
					u.call("_refresh_hp_bar")
			"march":
				u.damage_per_attack = maxi(1, int(round(float(u.damage_per_attack) * (1.0 + 0.15 * am))))
			"warchest":
				u.hp = mini(u.max_hp, u.hp + int(round(float(u.max_hp) * 0.25 * am)))
				if u.has_method("_refresh_hp_bar"):
					u.call("_refresh_hp_bar")

func _conclude_campaign(win: bool) -> void:
	var tier: int = GameManager.pending_battle_tier
	var elite: bool = GameManager.pending_battle_elite
	_campaign_lost = not win
	_campaign_relic = ""
	_campaign_gold = 0
	if win:
		# Survivors carry forward (permadeath drops the fallen regiments).
		var survivors: Array[Dictionary] = []
		for u: RTUnit in player_units:
			if is_instance_valid(u) and u.is_alive():
				var st: Dictionary = _unit_state.get(u.get_instance_id(), {})
				var entry = st.get("roster_entry", null)
				if entry != null:
					survivors.append(entry)
		# Aftermath cards in hand auto-resolve on the survivors (Spec B): a
		# "level" card promotes a survivor's roster entry. (v1 auto; a chooser
		# is a later refinement.)
		if GameManager.has_hero():
			for hi in range(GameManager.card_hand.size() - 1, -1, -1):
				var acd: Dictionary = GameManager.card_def(String(GameManager.card_hand[hi]))
				if String(acd.get("category", "")) != "aftermath" or survivors.is_empty():
					continue
				var eff: Dictionary = acd.get("effect", {})
				if String(eff.get("kind", "")) == "level":
					survivors[0]["level"] = int(survivors[0].get("level", 1)) + int(eff.get("value", 1))
				GameManager.card_play(hi)
		GameManager.set_roster(survivors)
		_campaign_gold = GameManager.battle_gold_reward(tier, elite)
		GameManager.add_gold(_campaign_gold)
		GameManager.register_battle_won(elite)
		# One VICTORY screen; the player claims ONE reward — a deck card OR a unit
		# upgrade (no map popup).
		_upgrade_offer = GameManager.random_upgrade_choices(3)
		_upgrade_pick = ""
		_reward_taken = false
		if elite:
			_campaign_relic = GameManager.grant_random_relic()
		_card_reward_offer = GameManager.card_reward_choices(3) if GameManager.has_hero() else []
		GameManager.save_run()
		_result_text = "VICTORY"
		Sfx.play("win", -7.0)
	else:
		GameManager.clear_run()   # permadeath — the run is over
		_result_text = "DEFEAT"
		Sfx.play("lose", -7.0)
	phase = Phase.RESULT
	_rebuild_ui()

func _on_campaign_continue() -> void:
	get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

# ---------------------------------------------------------------------------
# Duel (sway recruiting — battle_mode "auto", pending_duel)
# ---------------------------------------------------------------------------
# A 1v1: the hero (team 0) vs a single recruit candidate (team 1). On
# resolution the outcome is reported via GameManager.duel_outcome and the map
# (level_select) recruits the unit on a win.
func _start_duel_fight() -> void:
	_clear_units()
	_unit_state.clear()
	_feedback.clear()
	_last_recap.clear()
	var hero_card: Dictionary
	if GameManager.has_hero():
		hero_card = _build_hero_card()
	else:
		hero_card = {"id": "soldier", "level": 1 + GameManager.hero_tree_bonus_level(), "xp": 0, "hero": true}
	var recruit_card := _campaign_card(GameManager.duel_recruit_type)
	var hero_pos := _formation_positions(1, 0)
	var hero_unit := _spawn_unit(hero_card, 0, hero_pos[0], 1.0)
	if GameManager.hero_sway_aptitude("duel") > 0:
		hero_unit.max_hp = maxi(1, int(round(hero_unit.max_hp * 1.25)))
		hero_unit.hp = hero_unit.max_hp
		hero_unit.damage_per_attack = maxi(1, int(round(hero_unit.damage_per_attack * 1.25)))
		if hero_unit.has_method("_refresh_hp_bar"):
			hero_unit.call("_refresh_hp_bar")
	hero_unit.max_hp = maxi(1, int(round(float(hero_unit.max_hp) * GameManager.hero_hp_mult_tree())))
	hero_unit.hp = hero_unit.max_hp
	hero_unit.damage_per_attack = maxi(1, int(round(float(hero_unit.damage_per_attack) * GameManager.hero_damage_mult_tree())))
	hero_unit.attack_cooldown = maxf(0.2, hero_unit.attack_cooldown * GameManager.hero_attack_cooldown_mult())
	if hero_unit.has_method("_refresh_hp_bar"):
		hero_unit.call("_refresh_hp_bar")
	player_units.append(hero_unit)
	var recruit_pos := _formation_positions(1, 1)
	enemy_units.append(_spawn_unit(recruit_card, 1, recruit_pos[0], 1.0))
	phase = Phase.FIGHT
	Music.play("battle")   # duels skip prep — straight to combat track
	_fight_intro_timer = FIGHT_INTRO_SECONDS
	_ai_timer = 0.0
	_start_abilities_applied = false
	_speed_scale = 2.0
	_rebuild_ui()

func _conclude_duel(win: bool) -> void:
	GameManager.duel_outcome = 1 if win else 0
	if win:
		_result_text = "DUEL WON"
	else:
		# The hero is the only fighter in a duel — losing means the hero fell, and a
		# fallen hero ends the run (same rule as a campaign battle).
		_result_text = "DEFEAT"
		GameManager.clear_run()
	phase = Phase.RESULT
	Sfx.play("win" if win else "lose", -7.0)
	_rebuild_ui()

func _on_duel_continue() -> void:
	get_tree().change_scene_to_file("res://src/level_select/level_select.tscn")

func _spawn_unit(card: Dictionary, team_id: int, pos: Vector2, hp_mult: float, synergy_counts: Dictionary = {}) -> RTUnit:
	var u: RTUnit = RTUnit.new()
	add_child(u)
	var unit_id := _card_id(card)
	var stats: Dictionary = UNIT_TYPES[unit_id].duplicate(true)
	if card.has("sprite_key"):
		stats["sprite_key"] = String(card["sprite_key"])   # hero uses its own sprite
	var card_stats := _card_stats(card, synergy_counts)
	stats["damage_per_attack"] = card_stats["damage"]
	# Front-vs-front: a cosmetic squad of 10 sprites that cull one per ~10% HP
	# lost (keeps the little-army animation), but combat HP is a single pool and
	# the sprite count does NOT scale damage (see flat_damage below).
	stats["soldier_count"] = 10
	stats["hp_per_soldier"] = max(1, int(ceil(float(card_stats["hp"]) / 10.0)))
	if synergy_counts.get("scout", 0) >= 2 and unit_id == "scout":
		stats["move_speed_px"] = float(stats.get("move_speed_px", 60.0)) + 18.0
	if String(card.get("item", "")) == "drum":
		stats["move_speed_px"] = float(stats.get("move_speed_px", 60.0)) + 12.0
	stats["is_hero"] = card.get("hero", false)
	stats["is_villain"] = card.get("villain", false)
	stats["flat_damage"] = true  # Branch B: front-vs-front — a wounded unit still hits full
	u.setup(unit_id, team_id, pos, stats)
	u.holding = true             # held until the front-vs-front controller engages the front
	u.max_hp = int(round(float(u.max_hp) * hp_mult))
	u.hp = u.max_hp
	u.unit_name = "%s Lv %d" % [_unit_name(unit_id), int(card.get("level", 1))]
	u.died.connect(_on_unit_died)
	_unit_state[u.get_instance_id()] = {
		"card": _copy_card(card),
		"team": team_id,
		"damage": 0,
		"shield": unit_id == "soldier",
	}
	return u

func _enemy_roster(size_hint: int) -> Array:
	var count: int = clampi(size_hint + int(round_no / 3), 2, TEAM_SIZE)
	var out: Array = []
	for _i in range(count):
		var level := 1 + int(round_no >= 4) + int(round_no >= 7)
		out.append({"id": _random_unit_id(), "level": clampi(level, 1, MAX_LEVEL), "xp": 0})
	return out

func _line_positions(count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var step: float = FIELD_RECT.size.y / float(count + 1)
	for i in range(count):
		out.append(FIELD_RECT.position.y + step * float(i + 1))
	return out

func _formation_positions(count: int, team_id: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var y_positions := _line_positions(count)
	for i in range(count):
		var depth := float(i) * 64.0
		var x := 470.0 - depth
		if team_id == 1:
			x = 810.0 + depth
		out.append(Vector2(x, y_positions[i]))
	return out

func _auto_target(delta: float) -> void:
	_ai_timer -= delta
	if _ai_timer > 0.0:
		return
	_ai_timer = AI_RETARGET_PERIOD
	# Branch B — front-vs-front: only each team's frontmost-alive unit fights;
	# everyone else holds. When a front faints, the next in line steps up.
	_front_engage(player_units, enemy_units)
	_front_engage(enemy_units, player_units)

# Frontmost still-alive unit of a team. Live arrays are kept in formation order
# (index 0 = front) and compacted by _on_unit_died, so the first alive entry is
# the current front.
func _frontmost_alive(team: Array) -> RTUnit:
	for u: RTUnit in team:
		if is_instance_valid(u) and u.is_alive():
			return u
	return null

func _front_engage(team: Array, foes: Array) -> void:
	var front: RTUnit = _frontmost_alive(team)
	var foe_front: RTUnit = _frontmost_alive(foes)
	for u: RTUnit in team:
		if not (is_instance_valid(u) and u.is_alive()):
			continue
		if u == front and foe_front != null:
			u.holding = false
			u.order_attack(foe_front)
		else:
			u.holding = true

func _assign_targets(attackers: Array, defenders: Array) -> void:
	for u: RTUnit in attackers:
		if not u.is_alive():
			continue
		if u.order == RTUnit.Order.ATTACK and u.attack_target != null and u.attack_target.is_alive():
			continue
		var nearest := _nearest_enemy(u, defenders)
		if nearest != null:
			u.order_attack(nearest)

func _nearest_enemy(unit: RTUnit, defenders: Array) -> RTUnit:
	if _unit_id_for(unit) == "archer":
		return _backline_enemy(unit, defenders)
	# Favour wounded enemies (concentrate fire) while still preferring the near.
	var best: RTUnit = null
	var best_score: float = INF
	for target: RTUnit in defenders:
		if not target.is_alive() or _untargetable(target):
			continue
		var d := unit.position.distance_to(target.position)
		var wounded: float = 1.0 - float(target.hp) / float(maxi(1, target.max_hp))
		var score: float = d - wounded * 140.0
		if score < best_score:
			best = target
			best_score = score
	return best

func _backline_enemy(unit: RTUnit, defenders: Array) -> RTUnit:
	var state: Dictionary = _unit_state.get(unit.get_instance_id(), {})
	var team_id := int(state.get("team", unit.team))
	var best: RTUnit = null
	var best_x := -INF if team_id == 0 else INF
	for target: RTUnit in defenders:
		if not target.is_alive() or _untargetable(target):
			continue
		if team_id == 0 and target.position.x > best_x:
			best = target
			best_x = target.position.x
		elif team_id == 1 and target.position.x < best_x:
			best = target
			best_x = target.position.x
	return best

func _unit_id_for(unit: RTUnit) -> String:
	var state: Dictionary = _unit_state.get(unit.get_instance_id(), {})
	if state.has("card"):
		return _card_id(state["card"])
	return unit.unit_type

func _tick_unit(unit: RTUnit, delta: float, all_units: Array) -> void:
	var target_before: RTUnit = unit.attack_target
	var hp_before: int = 0
	if target_before != null and target_before.is_alive():
		hp_before = target_before.hp
	var fired: Dictionary = unit.tick(delta, all_units)
	if not bool(fired.get("fired", false)):
		return
	var target: RTUnit = fired.get("target", target_before) as RTUnit
	if target == null or not is_instance_valid(target):
		return
	var damage: int = max(0, hp_before - target.hp)
	damage = _apply_infantry_shield(target, damage)
	if _unit_id_for(unit) == "healer" and _unit_id_for(target) == "scout" and target.is_alive():
		var bonus := 6 + int(_unit_level_for(unit)) * 3
		var bonus_dealt := _deal_damage(unit, target, bonus, Color(0.72, 1.0, 0.56), "Spear")
		damage += bonus_dealt
	else:
		_add_feedback(unit.position, target.position, Color(1.0, 0.72, 0.36), "Hit")
	Sfx.play("hit", -14.0)
	_record_damage(unit, damage)

func _apply_infantry_shield(target: RTUnit, damage: int) -> int:
	var state: Dictionary = _unit_state.get(target.get_instance_id(), {})
	if damage <= 0 or not bool(state.get("shield", false)):
		return damage
	state["shield"] = false
	_unit_state[target.get_instance_id()] = state
	target.hp = min(target.max_hp, target.hp + damage)
	if target.has_method("_refresh_hp_bar"):
		target.call("_refresh_hp_bar")
	_add_feedback(target.position, target.position, Color(0.68, 0.86, 1.0), "Shield")
	return 0

func _apply_start_abilities() -> void:
	for u: RTUnit in player_units + enemy_units:
		if not u.is_alive() or _unit_id_for(u) != "scout":
			continue
		var defenders := enemy_units if u.team == 0 else player_units
		var target := _nearest_enemy(u, defenders)
		if target == null:
			continue
		u.order_attack(target)
		var charge_damage := 8 + _unit_level_for(u) * 5
		var dealt := _deal_damage(u, target, charge_damage, Color(0.95, 0.95, 0.42), "Charge")
		_record_damage(u, dealt)
		Sfx.play("ability", -8.0)

func _deal_damage(source: RTUnit, target: RTUnit, amount: int, color: Color, text: String) -> int:
	if target == null or not is_instance_valid(target) or amount <= 0:
		return 0
	var before := target.hp
	if _consume_infantry_shield(target):
		_add_feedback(target.position, target.position, Color(0.68, 0.86, 1.0), "Shield")
		return 0
	target.take_damage(amount)
	var dealt: int = max(0, before - target.hp)
	if source != null and is_instance_valid(source):
		_add_feedback(source.position, target.position, color, text)
	return dealt

func _consume_infantry_shield(target: RTUnit) -> bool:
	var state: Dictionary = _unit_state.get(target.get_instance_id(), {})
	if not bool(state.get("shield", false)):
		return false
	state["shield"] = false
	_unit_state[target.get_instance_id()] = state
	return true

func _record_damage(unit: RTUnit, amount: int) -> void:
	if amount <= 0:
		return
	var key := unit.get_instance_id()
	var state: Dictionary = _unit_state.get(key, {})
	state["damage"] = int(state.get("damage", 0)) + amount
	_unit_state[key] = state

func _unit_level_for(unit: RTUnit) -> int:
	var state: Dictionary = _unit_state.get(unit.get_instance_id(), {})
	if state.has("card"):
		return int(state["card"].get("level", 1))
	return 1

func _add_feedback(from: Vector2, to: Vector2, color: Color, text: String = "") -> void:
	_feedback.append({"from": from, "to": to, "color": color, "age": 0.0, "life": FEEDBACK_LIFETIME, "text": text})

func _age_feedback(delta: float) -> void:
	var next: Array = []
	for fx: Dictionary in _feedback:
		fx["age"] = float(fx.get("age", 0.0)) + delta
		if float(fx["age"]) < float(fx.get("life", FEEDBACK_LIFETIME)):
			next.append(fx)
	_feedback = next

func _check_fight_end() -> bool:
	var p_alive := _any_alive(player_units)
	var e_alive := _any_alive(enemy_units)
	# Protect the general: in a campaign the hero dying ends the run immediately,
	# even if troops are still standing (enemy archers can reach the backline).
	if _campaign and _hero_unit != null and not (is_instance_valid(_hero_unit) and _hero_unit.is_alive()):
		p_alive = false
	if p_alive and e_alive:
		return false
	_build_recap(p_alive, e_alive)
	if _duel:
		_conclude_duel(p_alive and not e_alive)
		return true
	if _campaign:
		_conclude_campaign(p_alive and not e_alive)
		return true
	if p_alive and not e_alive:
		wins += 1
		_result_text = "WIN"
	elif e_alive and not p_alive:
		hearts -= 1
		_result_text = "LOSS"
	else:
		_result_text = "DRAW"
	if wins >= MAX_WINS:
		phase = Phase.GAME_OVER
		_result_text = "RUN WON"
	elif hearts <= 0:
		phase = Phase.GAME_OVER
		_result_text = "RUN LOST"
	elif p_alive and not e_alive:
		_generate_reward_choices()
		phase = Phase.REWARD
	else:
		phase = Phase.RESULT
	Sfx.play("win" if p_alive and not e_alive else "lose", -7.0)
	_rebuild_ui()
	return true

func _build_recap(p_alive: bool, e_alive: bool) -> void:
	var best_name := "MVP: none"
	var best_damage := -1
	var total_player_damage := 0
	for unit: RTUnit in player_units + enemy_units:
		var state: Dictionary = _unit_state.get(unit.get_instance_id(), {})
		var damage := int(state.get("damage", 0))
		if int(state.get("team", 0)) == 0:
			total_player_damage += damage
		if damage > best_damage:
			best_damage = damage
			best_name = "MVP: %s (%d damage)" % [unit.unit_name, damage]
	var survivors := "Survivors: %d friendly / %d enemy" % [_alive_count(player_units), _alive_count(enemy_units)]
	_last_recap = {
		"summary": "Team damage: %d" % total_player_damage,
		"mvp": best_name,
		"survivors": survivors,
	}

func _alive_count(units: Array) -> int:
	var count := 0
	for u: RTUnit in units:
		if is_instance_valid(u) and u.is_alive():
			count += 1
	return count

func _any_alive(units: Array) -> bool:
	for u: RTUnit in units:
		if is_instance_valid(u) and u.is_alive():
			return true
	return false

func _on_unit_died(u: RTUnit) -> void:
	if is_instance_valid(u):
		_add_feedback(u.position, u.position, Color(0.95, 0.18, 0.14), "Down")
		Sfx.play("death", -12.0)
	# A player Troop falling fires armed ally_death traps once (Spec B).
	if is_instance_valid(u) and u.team == 0 and not _armed_traps.is_empty():
		var rest: Array = []
		for trap in _armed_traps:
			if String(trap.get("trigger", "")) == "ally_death":
				_fire_trap(trap)
			else:
				rest.append(trap)
		_armed_traps = rest
	player_units.erase(u)
	enemy_units.erase(u)
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(func():
		_free_node(u)
	)

func _clear_units() -> void:
	for u: RTUnit in player_units:
		_free_node(u)
	for u: RTUnit in enemy_units:
		_free_node(u)
	player_units.clear()
	enemy_units.clear()

func _free_node(node: Node) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()
