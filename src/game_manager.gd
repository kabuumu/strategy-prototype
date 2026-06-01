extends Node

# ---------------------------------------------------------------------------
# Unit type definitions
# ---------------------------------------------------------------------------
const UNIT_TYPES: Dictionary = {
	"soldier": {
		"name": "Soldier",
		"max_hp": 100,
		"move_range": 3,
		"attack_range": 1,
		"damage": 35,
		"color": Color(0.25, 0.5, 1.0),
		# Shield Bash: melee strike that stuns the target for a turn
		"ability": {"id": "bash", "name": "Shield Bash", "desc": "Melee hit that stuns the target"}
	},
	"archer": {
		"name": "Archer",
		"max_hp": 70,
		"move_range": 2,
		"attack_range": 3,
		"damage": 25,
		"color": Color(0.2, 0.75, 0.35),
		# Piercing Shot: hits the target and the cell directly behind it
		"ability": {"id": "pierce", "name": "Piercing Shot", "desc": "Hits the target and the unit behind it"}
	},
	"scout": {
		"name": "Scout",
		"max_hp": 60,
		"move_range": 4,
		"attack_range": 1,
		"damage": 20,
		"color": Color(0.95, 0.8, 0.1),
		# Dash: take a second move this activation
		"ability": {"id": "dash", "name": "Dash", "desc": "Move a second time this turn"}
	},
	# Boss — only spawned for the final-tier elite battle. Visually larger
	# with a red aura. Enrages at <=50% HP for +damage and +mobility. Reuses
	# the soldier_enemy sprite for the body.
	"warlord": {
		"name": "Warlord",
		"max_hp": 220,
		"move_range": 3,
		"attack_range": 1,
		"damage": 35,
		"color": Color(0.85, 0.20, 0.20),
		"is_boss": true,
		# Enrage bonuses applied when hp/max_hp drops to (or below) threshold
		"enrage_threshold": 0.5,
		"enrage_damage_bonus": 15,
		"enrage_move_bonus": 1,
		"enrage_range_bonus": 1,
	},
	# Ranged boss — sets your units on fire (burn DoT). Glass-cannon vs Warlord.
	"pyromancer": {
		"name": "Pyromancer",
		"max_hp": 170,
		"move_range": 2,
		"attack_range": 3,
		"damage": 24,
		"color": Color(0.95, 0.45, 0.12),
		"is_boss": true,
		"attack_burn": 2,           # applies 2 turns of burn on every hit
		"enrage_threshold": 0.5,
		"enrage_damage_bonus": 10,
		"enrage_move_bonus": 0,
		"enrage_range_bonus": 1,
	},
	# Tank boss — huge HP, slow, hits like a truck and enrages late + hard.
	"juggernaut": {
		"name": "Juggernaut",
		"max_hp": 320,
		"move_range": 2,
		"attack_range": 1,
		"damage": 40,
		"color": Color(0.55, 0.30, 0.75),
		"is_boss": true,
		"enrage_threshold": 0.4,
		"enrage_damage_bonus": 25,
		"enrage_move_bonus": 1,
		"enrage_range_bonus": 0,
	},
	"healer": {
		"name": "Healer",
		"max_hp": 65,
		"move_range": 3,
		"attack_range": 1,
		"damage": 10,
		"color": Color(0.20, 0.82, 0.70),
		# Field Heal: restore HP to a nearby ally
		"ability": {"id": "heal_ally", "name": "Field Heal", "desc": "Heal a nearby ally for 35"}
	},
	# --- Advanced recruits (found via gain-unit nodes / the shop) -------------
	# These reuse the boss sprite art (sprite_unit) and existing ability ids,
	# so they slot into the 2D battle and the 3D skirmish with no new plumbing.
	"knight": {
		"name": "Knight",
		"max_hp": 130,
		"move_range": 3,
		"attack_range": 1,
		"damage": 32,
		"color": Color(0.78, 0.80, 0.88),
		"sprite_unit": "warlord",
		# Charge: dash a second time to close the gap before striking
		"ability": {"id": "dash", "name": "Charge", "desc": "Move a second time this turn"}
	},
	"mage": {
		"name": "Battlemage",
		"max_hp": 70,
		"move_range": 2,
		"attack_range": 3,
		"damage": 28,
		"color": Color(0.70, 0.45, 0.95),
		"sprite_unit": "pyromancer",
		# Arcane Lance: pierces the target and whatever stands behind it
		"ability": {"id": "pierce", "name": "Arcane Lance", "desc": "Hits the target and the unit behind it"}
	},
	"guardian": {
		"name": "Guardian",
		"max_hp": 165,
		"move_range": 2,
		"attack_range": 1,
		"damage": 24,
		"color": Color(0.55, 0.42, 0.72),
		"sprite_unit": "juggernaut",
		# Crushing Blow: heavy melee hit that stuns the target
		"ability": {"id": "bash", "name": "Crushing Blow", "desc": "Melee hit that stuns the target"}
	},
	"berserker": {
		"name": "Berserker",
		"max_hp": 75,
		"move_range": 3,
		"attack_range": 1,
		"damage": 42,
		"color": Color(0.85, 0.32, 0.22),
		"sprite_unit": "soldier",
		# Bloodrush: dash in for a savage strike (glass-cannon melee)
		"ability": {"id": "dash", "name": "Bloodrush", "desc": "Move a second time this turn"}
	},
	"marksman": {
		"name": "Marksman",
		"max_hp": 55,
		"move_range": 2,
		"attack_range": 4,
		"damage": 30,
		"color": Color(0.40, 0.70, 0.45),
		"sprite_unit": "archer",
		# Piercing Bolt: long-range shot that punches through to the unit behind
		"ability": {"id": "pierce", "name": "Piercing Bolt", "desc": "Hits the target and the unit behind it"}
	}
}

# How much the Healer's Field Heal restores
const HEAL_ABILITY_AMOUNT: int = 35

# Action points per class per turn. A unit spends 1 AP per move, attack, or
# ability, and may act in any order until its AP runs out. Scouts get an extra.
const UNIT_AP: Dictionary = {
	"soldier": 2, "archer": 2, "scout": 3, "healer": 2,
	"warlord": 3, "pyromancer": 2, "juggernaut": 2,
	"knight": 3, "mage": 2, "guardian": 2, "berserker": 3, "marksman": 2,
}

func ap_for(unit_type: String) -> int:
	return int(UNIT_AP.get(unit_type, 2))

# Unit types the player can recruit/buy (excludes bosses).
func recruitable_types() -> Array[String]:
	var out: Array[String] = []
	for k: String in UNIT_TYPES:
		if not bool(UNIT_TYPES[k].get("is_boss", false)):
			out.append(k)
	return out

# ---------------------------------------------------------------------------
# Persistent unit upgrades earned after battle wins
# ---------------------------------------------------------------------------
# Stacking is permitted (multiple SHARPSHOOTERs = +5 dmg each).
# Effects are applied in unit.gd's getters and during setup.
const UPGRADE_TYPES: Dictionary = {
	"veteran":      {"name": "Veteran",      "desc": "+20 max HP, heal 20",  "color": Color(0.50, 0.95, 0.45)},
	"sharpshooter": {"name": "Sharpshooter", "desc": "+5 damage",            "color": Color(0.95, 0.45, 0.30)},
	"swift":        {"name": "Swift",        "desc": "+1 move range",        "color": Color(0.45, 0.75, 0.95)},
	"eagle_eye":    {"name": "Eagle Eye",    "desc": "+1 attack range (max 4)", "color": Color(0.95, 0.85, 0.35)},
	"ironhide":     {"name": "Ironhide",     "desc": "−20% damage taken",    "color": Color(0.70, 0.70, 0.85)},
	"lucky":        {"name": "Lucky",        "desc": "+15% crit chance",     "color": Color(0.95, 0.65, 0.95)},
	"berserker":    {"name": "Berserker",    "desc": "+5 dmg per 25% HP missing", "color": Color(0.95, 0.30, 0.20)},
}
const UPGRADE_IDS: Array[String] = ["veteran", "sharpshooter", "swift", "eagle_eye", "ironhide", "lucky", "berserker"]

# ---------------------------------------------------------------------------
# Biomes — one per tier. Bias terrain generation + battle background so each
# tier of a run looks and plays differently. "mtn" is the mountain-cluster
# count range; forest/hill/lava are target tile counts.
# ---------------------------------------------------------------------------
const BIOMES: Array[Dictionary] = [
	{"name": "Grassy Plains",    "bg": Color(0.07, 0.10, 0.07), "mtn": Vector2i(2, 3), "forest": 3, "hill": 2, "lava": 0},
	{"name": "Deep Woods",       "bg": Color(0.05, 0.11, 0.07), "mtn": Vector2i(2, 3), "forest": 8, "hill": 1, "lava": 0},
	{"name": "Rocky Highlands",  "bg": Color(0.10, 0.09, 0.07), "mtn": Vector2i(4, 6), "forest": 2, "hill": 6, "lava": 0},
	{"name": "Volcanic Wastes",  "bg": Color(0.13, 0.06, 0.05), "mtn": Vector2i(3, 5), "forest": 0, "hill": 2, "lava": 6},
	{"name": "The Citadel",      "bg": Color(0.10, 0.07, 0.13), "mtn": Vector2i(4, 5), "forest": 1, "hill": 3, "lava": 3},
]

func biome_for_tier(tier: int) -> Dictionary:
	return BIOMES[clampi(tier, 0, BIOMES.size() - 1)]

# Bosses — one is chosen per run for the final-tier fight (see boss_id).
const BOSS_IDS: Array[String] = ["warlord", "pyromancer", "juggernaut"]

# ---------------------------------------------------------------------------
# Map constants
# ---------------------------------------------------------------------------
const MAP_TIERS: int = 5
# Tier sizes are generated per-run (see _generate_map).
# Tier 0 is 2-3 varied starting nodes; middle tiers vary 2–5; last tier = 1 (boss).

# ---------------------------------------------------------------------------
# Persistent game state
# ---------------------------------------------------------------------------
# Each entry: { "type": String, "hp": int }  — HP persists across battles,
# and units that die in battle are removed (permadeath).
var player_roster: Array[Dictionary] = []
var gold: int = 0
var relics: Array[String] = []   # owned relic ids (run-long passives)
var curses: Array[String] = []   # afflictions (run-long negative passives)
var battle_mode: String = "2d"   # how campaign battles play: "2d" hex turn-based / "3d" real-time / "auto" auto-battler
var current_tier: int = 0
var last_chosen_index: int = -1
var map_data: Array = []
var boss_id: String = "warlord"   # the boss for this run's final battle

# Run statistics — reset on every new run
var battles_won: int = 0
var best_streak_ever: int = 0   # persists across runs
var best_tier_reached: int = 0  # persists across runs (1-based; 5 = boss cleared)
var total_runs: int = 0         # persists across runs
var tutorial_seen: bool = false # persists; first-battle help auto-shows once
var last_run_battles_won: int = 0  # snapshot of the run that just ended (in-memory only)
var last_run_tier_reached: int = 0
var last_run_won: bool = false

# Settings (persisted in meta).
var master_volume: float = 0.8

const META_PATH: String = "user://meta.cfg"

# Shop prices
const SHOP_HEAL_COST: int = 25
const SHOP_UNIT_COST: int = 60
const SHOP_RELIC_COST: int = 80

# Run-modifying relics
const RELICS: Dictionary = {
	"whetstone": {"name": "Whetstone",     "desc": "+8 damage to all your units"},
	"boots":     {"name": "Swift Boots",   "desc": "+1 move range to all your units"},
	"plating":   {"name": "Plating",       "desc": "+20 max HP to all your units"},
	"venom":     {"name": "Venom Coating",  "desc": "Your melee hits poison the target"},
	"medkit":    {"name": "Field Kit",     "desc": "Units start each battle +15 HP"},
	"longbow":   {"name": "War Bow",       "desc": "+1 attack range to all your units"},
	"coffer":    {"name": "Gilded Coffer", "desc": "+20 gold after every battle"},
	"war_banner":{"name": "War Banner",    "desc": "+1 action point to all your units"},
	"keen_edge": {"name": "Keen Edge",     "desc": "+12% crit chance to all your units"},
	"aegis":     {"name": "Aegis",         "desc": "Your units take 15% less damage"},
	"vampiric":  {"name": "Vampiric Edge",  "desc": "Melee hits heal the attacker for 30% of damage dealt"},
	"rally":     {"name": "Rally Banner",   "desc": "Killing an enemy refunds 1 action point"},
	# Mythic — only ever granted by the (extremely rare) god encounter.
	"divine_favor": {"name": "Divine Favour", "desc": "+25 dmg, +60 HP, +2 move, +1 range, +1 AP, +25% crit, −40% damage taken"},
}

# Army synergies — passive bonuses earned by roster composition, rewarding
# deliberate army-building. Computed live from player_roster; applied (player
# team) in unit.gd and shown on the map.
const SYNERGIES: Dictionary = {
	"phalanx": {"name": "Phalanx",  "desc": "3+ melee units → all units take 10% less damage"},
	"volley":  {"name": "Volley",   "desc": "3+ ranged units → +1 attack range for all"},
	"horde":   {"name": "Horde",    "desc": "6+ units → +4 damage for all"},
}

func army_synergies() -> Array[String]:
	var melee: int = 0
	var ranged: int = 0
	for e: Dictionary in player_roster:
		if int(UNIT_TYPES[e["type"]]["attack_range"]) <= 1:
			melee += 1
		else:
			ranged += 1
	var out: Array[String] = []
	if melee >= 3:
		out.append("phalanx")
	if ranged >= 3:
		out.append("volley")
	if player_roster.size() >= 6:
		out.append("horde")
	return out

func has_synergy(id: String) -> bool:
	return id in army_synergies()

# Curses — run-long afflictions (the dark side of risky events). Applied to the
# player team in unit.gd, mirroring relics but negative.
const CURSES: Dictionary = {
	"frailty":  {"name": "Curse of Frailty",  "desc": "−15 max HP to all your units"},
	"dullness": {"name": "Curse of Dullness",  "desc": "−5 damage to all your units"},
	"sloth":    {"name": "Curse of Sloth",     "desc": "−1 move range to all your units"},
	# Mythic — the dark mirror of Divine Favour, only from the demon encounter.
	"damnation": {"name": "Damnation", "desc": "−50 max HP, −20 damage, −2 move range to all your units"},
}

# Set before switching to the battle scene
var pending_battle_tier: int = 0
var pending_battle_elite: bool = false
# When true, the campaign battle is fought as a 3D skirmish (set by level_select).
var pending_skirmish: bool = false
# When true, the campaign battle is auto-resolved by the auto-battler (set by level_select).
var pending_autobattle: bool = false
# When true, the campaign battle is a tower-defence stand (set by level_select).
var pending_td: bool = false
# When true, the campaign battle is a base-building RTS (set by level_select).
var pending_base: bool = false
# When true, the campaign battle is a 2D real-time (Total War) fight (set by level_select).
var pending_rt: bool = false
# Set by the non-hex campaign modes on a win so level_select offers an upgrade
# pick (the hex battle has its own inline upgrade picker). Consumed on the map.
var pending_upgrade_reward: bool = false

# ---------------------------------------------------------------------------
func _ready() -> void:
	_load_meta()
	apply_audio()
	reset()

# --- Settings -------------------------------------------------------------
func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	_save_meta()

func apply_audio() -> void:
	var db: float = -60.0 if master_volume <= 0.001 else linear_to_db(master_volume)
	AudioServer.set_bus_volume_db(0, db)

func reset() -> void:
	# Capture the just-ended run's stats so the title screen can show a recap.
	# (Skipped on the very first call when no run has happened yet.)
	if battles_won > 0 or current_tier > 0:
		last_run_battles_won = battles_won
		last_run_tier_reached = current_tier + 1  # 1-based
		last_run_won = battles_won >= MAP_TIERS
		total_runs += 1
		if last_run_tier_reached > best_tier_reached:
			best_tier_reached = last_run_tier_reached
		_save_meta()
	player_roster = []
	for t: String in ["soldier", "soldier", "archer"]:
		add_unit(t)
	gold = 0
	relics = []
	curses = []
	current_tier = 0
	last_chosen_index = -1
	pending_battle_tier = 0
	pending_battle_elite = false
	battles_won = 0
	# Pick this run's final boss
	var brng := RandomNumberGenerator.new()
	brng.randomize()
	boss_id = BOSS_IDS[brng.randi() % BOSS_IDS.size()]
	_generate_map()

# Called by battle on victory. Updates streak counters.
func register_battle_won(_elite: bool) -> void:
	battles_won += 1
	# Surviving regiments gain battle experience (toward veterancy).
	for entry: Dictionary in player_roster:
		entry["xp"] = int(entry.get("xp", 0)) + 1
	if battles_won > best_streak_ever:
		best_streak_ever = battles_won
		_save_meta()

# ---------------------------------------------------------------------------
# Meta-progression persistence
# ---------------------------------------------------------------------------
func _load_meta() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) != OK:
		return
	best_streak_ever  = int(cfg.get_value("meta", "best_streak_ever",  0))
	best_tier_reached = int(cfg.get_value("meta", "best_tier_reached", 0))
	total_runs        = int(cfg.get_value("meta", "total_runs",        0))
	tutorial_seen     = bool(cfg.get_value("meta", "tutorial_seen",    false))
	master_volume     = float(cfg.get_value("meta", "master_volume",   0.8))

func _save_meta() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "best_streak_ever",  best_streak_ever)
	cfg.set_value("meta", "best_tier_reached", best_tier_reached)
	cfg.set_value("meta", "total_runs",        total_runs)
	cfg.set_value("meta", "tutorial_seen",     tutorial_seen)
	cfg.set_value("meta", "master_volume",     master_volume)
	cfg.save(META_PATH)

# Mark the first-battle help as seen (persists so it won't auto-open again).
func mark_tutorial_seen() -> void:
	if not tutorial_seen:
		tutorial_seen = true
		_save_meta()

# ---------------------------------------------------------------------------
# Run save / resume — persists the whole in-progress run (roster, gold, relics,
# map, position). All values are primitives so ConfigFile round-trips cleanly.
# Deliberately NOT touched by reset(), so launching the game never wipes a save.
# ---------------------------------------------------------------------------
const RUN_SAVE_PATH: String = "user://run_save.cfg"
# Bump when the run-save schema changes incompatibly; older saves are discarded
# on load instead of loading partial/garbage state.
const SAVE_VERSION: int = 2

func has_saved_run() -> bool:
	if not FileAccess.file_exists(RUN_SAVE_PATH):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK:
		return false
	return int(cfg.get_value("run", "version", 1)) == SAVE_VERSION

func save_run() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "version", SAVE_VERSION)
	cfg.set_value("run", "roster", player_roster)
	cfg.set_value("run", "gold", gold)
	cfg.set_value("run", "relics", relics)
	cfg.set_value("run", "curses", curses)
	cfg.set_value("run", "current_tier", current_tier)
	cfg.set_value("run", "last_chosen_index", last_chosen_index)
	cfg.set_value("run", "map_data", map_data)
	cfg.set_value("run", "battles_won", battles_won)
	cfg.set_value("run", "boss_id", boss_id)
	cfg.set_value("run", "battle_mode", battle_mode)
	cfg.save(RUN_SAVE_PATH)

# Load a saved run into the live state. Returns false if no valid save exists.
func load_run() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK:
		return false
	# Discard saves from an incompatible schema version.
	if int(cfg.get_value("run", "version", 1)) != SAVE_VERSION:
		clear_run()
		return false
	var raw_map: Array = cfg.get_value("run", "map_data", [])
	if raw_map.is_empty():
		return false
	player_roster = []
	for e in cfg.get_value("run", "roster", []):
		if e is Dictionary:
			player_roster.append(e)
	relics = []
	for r in cfg.get_value("run", "relics", []):
		relics.append(str(r))
	curses = []
	for c in cfg.get_value("run", "curses", []):
		curses.append(str(c))
	gold              = int(cfg.get_value("run", "gold", 0))
	current_tier      = int(cfg.get_value("run", "current_tier", 0))
	last_chosen_index = int(cfg.get_value("run", "last_chosen_index", -1))
	map_data          = raw_map
	battles_won       = int(cfg.get_value("run", "battles_won", 0))
	boss_id           = str(cfg.get_value("run", "boss_id", "warlord"))
	battle_mode       = str(cfg.get_value("run", "battle_mode", "2d"))
	pending_battle_tier = 0
	pending_battle_elite = false
	return true

func clear_run() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)

# ---------------------------------------------------------------------------
# Map generation
# ---------------------------------------------------------------------------
func _generate_map() -> void:
	map_data.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Tier 0 offers 2-3 starting paths; middle tiers vary 2-5; final tier = 1 (boss)
	var sizes: Array = []
	sizes.append(rng.randi_range(2, 3))
	for _t in range(MAP_TIERS - 2):
		sizes.append(rng.randi_range(2, 5))
	sizes.append(1)

	# Create nodes (connections filled in next pass)
	for tier in range(MAP_TIERS):
		var nodes: Array = []
		for i in range(sizes[tier]):
			nodes.append({
				"type": _pick_node_type(tier, rng),
				"tier": tier,
				"index": i,
				"visited": false,
				"connections": []
			})
		map_data.append(nodes)

	# Give the starting tier a curated, varied spread: one tougher (elite) path,
	# never all battles, so the opening choice is meaningful.
	var start_types: Array = _starting_node_types(map_data[0].size(), rng)
	for i in range(map_data[0].size()):
		map_data[0][i]["type"] = start_types[i]

	# Wire up connections between every adjacent tier pair
	for tier in range(MAP_TIERS - 1):
		_generate_connections(tier, rng)

# Types for the 2-3 starting nodes: always one tougher "elite_battle", a normal
# "battle" when there's room for three, and the rest drawn from utility nodes —
# guaranteeing variety and at least one non-combat opening.
func _starting_node_types(count: int, _rng: RandomNumberGenerator) -> Array:
	var out: Array = ["elite_battle"]
	if count >= 3:
		out.append("battle")
	# Openers exclude "heal" (units start full) and "shop" (no gold yet) — both
	# are pointless before the first battle. Gain-unit is the useful non-combat
	# start.
	var utility: Array = ["gain_unit"]
	utility.shuffle()
	var ui: int = 0
	while out.size() < count:
		out.append(utility[ui % utility.size()])
		ui += 1
	out.shuffle()
	return out

func _generate_connections(tier: int, rng: RandomNumberGenerator) -> void:
	var from_count: int = map_data[tier].size()
	var to_count:   int = map_data[tier + 1].size()

	# Each source node connects to its proportionally-mapped target(s)
	for i in range(from_count):
		var t: float = 0.0 if from_count == 1 else float(i) / float(from_count - 1)
		var target_f: float = t * float(to_count - 1)
		var lo: int = clamp(int(floor(target_f)), 0, to_count - 1)
		var hi: int = clamp(int(ceil(target_f)),  0, to_count - 1)

		var conns: Array = [lo]
		if hi != lo:
			conns.append(hi)

		# Randomly add one extra adjacent connection for branching variety
		if to_count > 2 and rng.randi() % 3 == 0:
			var extra: int = clamp(lo + rng.randi_range(-1, 1), 0, to_count - 1)
			if extra not in conns:
				conns.append(extra)

		map_data[tier][i]["connections"] = conns

	# Guarantee every target node has at least one incoming connection
	for j in range(to_count):
		var found := false
		for i in range(from_count):
			if j in map_data[tier][i]["connections"]:
				found = true
				break
		if not found:
			# Attach to the source node whose proportional position is closest
			var best_i := 0
			var best_d := 999.0
			for i in range(from_count):
				var t: float = 0.0 if from_count == 1 else float(i) / float(from_count - 1)
				var d: float = abs(t * float(to_count - 1) - float(j))
				if d < best_d:
					best_d = d
					best_i = i
			var c: Array = map_data[tier][best_i]["connections"]
			c.append(j)
			map_data[tier][best_i]["connections"] = c

func _pick_node_type(tier: int, rng: RandomNumberGenerator) -> String:
	if tier == MAP_TIERS - 1:
		return "elite_battle"
	# Tier 0 is overwritten by _starting_node_types after generation; the value
	# returned here is just a placeholder.
	var roll := rng.randi() % 13
	if roll < 4:
		return "battle"
	elif roll < 6:
		return "elite_battle"
	elif roll < 7:
		return "gain_unit"
	elif roll < 9:
		return "shop"
	elif roll < 11:
		return "event"
	elif roll < 12:
		return "treasure"
	else:
		return "heal"

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------
func get_reachable_indices() -> Array:
	if current_tier >= MAP_TIERS:
		return []
	# Before any node is visited, all nodes in tier 0 are available
	if last_chosen_index == -1:
		var result: Array = []
		for i in range(map_data[0].size()):
			result.append(i)
		return result
	# Otherwise, return only the connections from the last visited node
	return map_data[current_tier - 1][last_chosen_index]["connections"]

func visit_node(tier: int, index: int) -> void:
	map_data[tier][index]["visited"] = true
	last_chosen_index = index
	current_tier = tier + 1

# ---------------------------------------------------------------------------
# Battle configuration
# ---------------------------------------------------------------------------
func get_battle_enemy_roster(tier: int, elite: bool) -> Array[String]:
	# Final-tier elite is the boss fight — this run's boss plus an honour guard
	if is_final_battle(tier, elite):
		return [boss_id, "archer", "soldier"] as Array[String]
	var rng := RandomNumberGenerator.new()
	rng.seed = tier * 31 + (13 if elite else 7)
	# Tougher unit types join the enemy pool as the run deepens, for variety.
	var pool: Array[String] = ["soldier", "archer", "scout"]
	if tier >= 2:
		pool.append("healer")
		pool.append("knight")
		pool.append("berserker")
	if tier >= 3:
		pool.append("mage")
		pool.append("guardian")
		pool.append("marksman")
	var count: int = clampi(2 + tier + (1 if elite else 0), 2, 5)
	var result: Array[String] = []
	for _i in range(count):
		result.append(pool[rng.randi() % pool.size()])
	return result

func is_final_battle(tier: int, elite: bool) -> bool:
	return elite and tier == MAP_TIERS - 1

func get_hp_multiplier(tier: int, elite: bool) -> float:
	return 1.0 + tier * 0.2 + (0.25 if elite else 0.0)

# ---------------------------------------------------------------------------
# Roster management
# ---------------------------------------------------------------------------
func add_unit(unit_type: String) -> void:
	player_roster.append({
		"type": unit_type,
		"hp":   int(UNIT_TYPES[unit_type]["max_hp"]),
		"upgrades": [] as Array,
		"xp": 0,
	})

# Veterancy: a regiment levels every 3 battles it survives (max level 4). Each
# level past 1 grants +8 max HP and +2 damage (applied for the player team).
func unit_level(entry: Dictionary) -> int:
	return clampi(1 + int(entry.get("xp", 0)) / 3, 1, 4)

# Restore every roster unit to full HP (heal node). Honours VETERAN HP boosts.
func heal_roster() -> void:
	for entry: Dictionary in player_roster:
		entry["hp"] = unit_effective_max_hp(entry)

# Called by battle on victory: rebuild roster from surviving units (dead units
# are dropped — permadeath) carrying their remaining HP and upgrades forward.
func set_roster(survivors: Array[Dictionary]) -> void:
	player_roster = survivors

# Apply an upgrade to a roster entry by index. Bumps stored HP for VETERAN so
# the heal is honoured immediately.
func apply_upgrade(roster_index: int, upgrade_id: String) -> void:
	if roster_index < 0 or roster_index >= player_roster.size():
		return
	if not UPGRADE_TYPES.has(upgrade_id):
		return
	var entry: Dictionary = player_roster[roster_index]
	var ups: Array = entry.get("upgrades", [])
	ups.append(upgrade_id)
	entry["upgrades"] = ups
	if upgrade_id == "veteran":
		# Heal 20 (capped at new effective max)
		var new_max := unit_effective_max_hp(entry)
		entry["hp"] = mini(new_max, int(entry["hp"]) + 20)
	player_roster[roster_index] = entry

# Total max HP after VETERAN stacks
func unit_effective_max_hp(entry: Dictionary) -> int:
	var base: int = int(UNIT_TYPES[entry["type"]]["max_hp"])
	var bonus: int = 0
	for u: String in entry.get("upgrades", []):
		if u == "veteran":
			bonus += 20
	bonus += (unit_level(entry) - 1) * 8   # veterancy
	return base + bonus

# Pick `count` distinct random upgrades from the pool. If pool is smaller,
# returns all of them.
func random_upgrade_choices(count: int) -> Array[String]:
	var pool: Array[String] = UPGRADE_IDS.duplicate()
	pool.shuffle()
	var n: int = mini(count, pool.size())
	var out: Array[String] = []
	for i in range(n):
		out.append(pool[i])
	return out

# ---------------------------------------------------------------------------
# Random events (the "event" map node)
# ---------------------------------------------------------------------------
# Each event has flavour text and 2-3 choices. A choice may cost gold ("cost",
# gated in the UI) and applies an "effect" dict — any of: gold (+/-), heal_all,
# damage_all (each unit, never lethal), add_unit "random", add_relic "random",
# add_upgrade "random" (random survivor), lose_unit true (weakest perishes).
const EVENTS: Array = [
	{
		"title": "Wandering Mercenary",
		"text": "A scarred sellsword offers his blade — for the right price.",
		"choices": [
			{"label": "Hire him (40g)", "cost": 40, "effect": {"add_unit": "random"}},
			{"label": "Send him away", "effect": {}},
		],
	},
	{
		"title": "Ancient Shrine",
		"text": "A moss-covered shrine hums with old power. Do you honour it, or pry loose its gilding?",
		"choices": [
			{"label": "Pray (heal the party)", "effect": {"heal_all": 30}},
			{"label": "Strip the gold (+60g, party bruised)", "effect": {"gold": 60, "damage_all": 12}},
		],
	},
	{
		"title": "Abandoned Cache",
		"text": "Supplies left by a fallen company. You can only carry one prize.",
		"choices": [
			{"label": "Take the coin (+70g)", "effect": {"gold": 70}},
			{"label": "Take the relic", "effect": {"add_relic": "random"}},
		],
	},
	{
		"title": "Blood Altar",
		"text": "The altar promises power for a life freely given.",
		"choices": [
			{"label": "Make the sacrifice (lose a unit, gain a relic)", "effect": {"lose_unit": true, "add_relic": "random"}},
			{"label": "Refuse the bargain", "effect": {}},
		],
	},
	{
		"title": "Veteran Drillmaster",
		"text": "An old campaigner offers to drill one of your regiments.",
		"choices": [
			{"label": "Pay for training (40g)", "cost": 40, "effect": {"add_upgrade": "random"}},
			{"label": "March on", "effect": {}},
		],
	},
	{
		"title": "Cursed Idol",
		"text": "A leering idol of gold. It would fetch a fortune — but it feels wrong.",
		"choices": [
			{"label": "Smash it for gold (+90g, a unit is slain)", "effect": {"gold": 90, "lose_unit": true}},
			{"label": "Leave it be", "effect": {}},
		],
	},
	{
		"title": "Field Hospital",
		"text": "A camp of healers tends the wounded of both armies.",
		"choices": [
			{"label": "Rest the party (heal fully)", "effect": {"heal_all": 9999}},
			{"label": "Donate for a blessing (30g, +relic)", "cost": 30, "effect": {"add_relic": "random"}},
		],
	},
	{
		"title": "Gambler's Wager",
		"text": "A grinning dicer rattles his cup. Care to test your luck?",
		"choices": [
			{"label": "Small bet — 30g (50%: +80g)", "cost": 30, "effect": {"gamble_gold": 80}},
			{"label": "Big bet — 60g (50%: +160g)", "cost": 60, "effect": {"gamble_gold": 160}},
			{"label": "Keep your coin", "effect": {}},
		],
	},
	{
		"title": "Crossroads Camp",
		"text": "A waystation at the fork. Travellers offer rest, trade, or a quiet shrine.",
		"choices": [
			{"label": "Rest (heal party)", "effect": {"heal_all": 9999}},
			{"label": "Trade goods (+50g)", "effect": {"gold": 50}},
			{"label": "Pray at the shrine (25g, +relic)", "cost": 25, "effect": {"add_relic": "random"}},
		],
	},
	{
		"title": "Press-Ganged Recruits",
		"text": "A gang of brawlers — you could conscript them by force, or pay them honestly.",
		"choices": [
			{"label": "Conscript (free unit, party worn −8 HP)", "effect": {"add_unit": "random", "damage_all": 8}},
			{"label": "Pay them fairly (50g, free unit)", "cost": 50, "effect": {"add_unit": "random"}},
			{"label": "Move on", "effect": {}},
		],
	},
	{
		"title": "Hooded Relic Trader",
		"text": "A cloaked dealer spreads a velvet cloth of curious artifacts — rare, and not cheap.",
		"choices": [
			{"label": "Buy the artifact (85g)", "cost": 85, "effect": {"add_relic": "random"}},
			{"label": "Haggle for two (130g, +relic, party tired −6 HP)", "cost": 130, "effect": {"add_relic": "random", "heal_all": 0, "damage_all": 6}},
			{"label": "Browse and leave", "effect": {}},
		],
	},
	{
		"title": "Wandering Witch",
		"text": "A hedge-witch stirs a kettle. 'A sip of my brew, dearie? Fortune favours the bold... usually.'",
		"choices": [
			{"label": "Drink the brew (55% bless / 45% curse)", "effect": {"witch_brew": true}},
			{"label": "Cross her palm for a blessing (60g, +relic)", "cost": 60, "effect": {"add_relic": "random"}},
			{"label": "Hurry past", "effect": {}},
		],
	},
	{
		"title": "Faustian Bargain",
		"text": "A horned figure offers true power — at a price paid in your army's vitality.",
		"choices": [
			{"label": "Accept the pact (gain a relic AND a curse)", "effect": {"add_relic": "random", "add_curse": "random"}},
			{"label": "Spurn the devil", "effect": {}},
		],
	},
	{
		"title": "Bandit Toll",
		"text": "Bandits block the pass, hands on hilts. 'Pay the toll, or we take it in blood.'",
		"choices": [
			{"label": "Pay them off (60g)", "cost": 60, "effect": {}},
			{"label": "Fight through (party takes −14 HP, loot +50g)", "effect": {"gold": 50, "damage_all": 14}},
			{"label": "Bribe their captain (40g, he joins you)", "cost": 40, "effect": {"add_unit": "random"}},
		],
	},
	{
		"title": "Fey Shrine",
		"text": "Will-o'-wisps drift around a fairy ring. Step inside and tempt fate — most leave changed, a rare few are truly blessed.",
		"choices": [
			{"label": "Enter the ring (rare great blessing possible)", "effect": {"fortune": true}},
			{"label": "Leave an offering (40g, safe blessing)", "cost": 40, "effect": {"add_relic": "random"}},
			{"label": "Keep your distance", "effect": {}},
		],
	},
]

# The god encounter — astronomically rare (~1 in 100 runs given a couple of
# event nodes per run). Hands out the mythic Divine Favour relic.
const GOD_EVENT: Dictionary = {
	"title": "An Audience with a God",
	"text": "The air turns to gold. A vast, serene presence regards your warband with something like fondness. 'You amuse me, little general. Take this, and make legends.'",
	"choices": [
		{"label": "Accept the Divine Favour", "effect": {"add_relic_id": "divine_favor"}},
		{"label": "Bow and decline (you fool)", "effect": {}},
	],
}

# The demon encounter — the dark mirror of the god. Equally rare; inflicts the
# mythic Damnation curse unless you buy your way out.
const DEMON_EVENT: Dictionary = {
	"title": "The Devil's Due",
	"text": "The shadows congeal into a horned thing with a banker's smile. 'A toll, general — in gold, in blood, or in suffering. Choose.'",
	"choices": [
		{"label": "Pay tribute to be spared (80g)", "cost": 80, "effect": {}},
		{"label": "Offer a soul (lose a unit, walk free)", "effect": {"lose_unit": true}},
		{"label": "Defy it (suffer Damnation)", "effect": {"add_curse_id": "damnation"}},
	],
}

func random_event() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# ~0.6% each per event node => roughly 1 in 100 runs you meet the god or demon.
	var roll: float = rng.randf()
	if not has_relic("divine_favor") and roll < 0.006:
		return GOD_EVENT
	if not has_curse("damnation") and roll < 0.012:
		return DEMON_EVENT
	return EVENTS[rng.randi() % EVENTS.size()]

func _random_recruitable() -> String:
	var pool := recruitable_types()
	if pool.is_empty():
		return "soldier"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return pool[rng.randi() % pool.size()]

# Apply an event choice (after the UI has confirmed affordability). Returns a
# short result message for a toast.
func apply_event_choice(choice: Dictionary) -> String:
	var cost: int = int(choice.get("cost", 0))
	if cost > 0:
		spend_gold(cost)
	var eff: Dictionary = choice.get("effect", {})
	var parts: Array[String] = []
	if eff.has("gold"):
		var g: int = int(eff["gold"])
		gold = maxi(0, gold + g)
		parts.append(("+%d gold" % g) if g >= 0 else ("%d gold" % g))
	if eff.has("gamble_gold"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		if rng.randf() < 0.5:
			var payout: int = int(eff["gamble_gold"])
			gold += payout
			parts.append("the bet pays off — +%d gold!" % payout)
		else:
			parts.append("the bet is lost")
	if eff.has("heal_all"):
		var amt: int = int(eff["heal_all"])
		for entry: Dictionary in player_roster:
			entry["hp"] = mini(unit_effective_max_hp(entry), int(entry["hp"]) + amt)
		parts.append("party healed")
	if eff.has("damage_all"):
		var dmg: int = int(eff["damage_all"])
		for entry: Dictionary in player_roster:
			entry["hp"] = maxi(1, int(entry["hp"]) - dmg)   # never lethal
		parts.append("party bruised")
	if eff.has("add_unit"):
		var t: String = _random_recruitable()
		add_unit(t)
		parts.append("recruited %s" % String(UNIT_TYPES[t]["name"]))
	if eff.has("add_relic"):
		var rid: String = grant_random_relic()
		parts.append(("found %s" % String(RELICS[rid]["name"])) if rid != "" else "no relic to find")
	if eff.has("add_relic_id"):
		var fixed: String = String(eff["add_relic_id"])
		if RELICS.has(fixed):
			add_relic(fixed)
			for entry: Dictionary in player_roster:
				entry["hp"] = unit_effective_max_hp(entry)
			parts.append("RECEIVED %s" % String(RELICS[fixed]["name"]))
	if eff.has("add_curse"):
		var cid: String = grant_random_curse()
		parts.append(("afflicted by %s" % String(CURSES[cid]["name"])) if cid != "" else "the hex fizzles")
	if eff.has("add_curse_id"):
		var fc: String = String(eff["add_curse_id"])
		if CURSES.has(fc):
			add_curse(fc)
			parts.append("AFFLICTED: %s" % String(CURSES[fc]["name"]))
	if eff.has("witch_brew"):
		var rng2 := RandomNumberGenerator.new()
		rng2.randomize()
		if rng2.randf() < 0.55:
			var brid: String = grant_random_relic()
			parts.append(("blessed with %s" % String(RELICS[brid]["name"])) if brid != "" else "a warm glow, nothing more")
		else:
			var bcid: String = grant_random_curse()
			parts.append(("cursed with %s" % String(CURSES[bcid]["name"])) if bcid != "" else "a bitter taste, nothing more")
	if eff.has("fortune"):
		# Mostly modest, but a RARE great blessing (two relics + full heal) is possible.
		var rng3 := RandomNumberGenerator.new()
		rng3.randomize()
		var r: float = rng3.randf()
		if r < 0.12:
			var b1: String = grant_random_relic()
			var b2: String = grant_random_relic()
			for entry: Dictionary in player_roster:
				entry["hp"] = unit_effective_max_hp(entry)
			var names: Array[String] = []
			if b1 != "": names.append(String(RELICS[b1]["name"]))
			if b2 != "": names.append(String(RELICS[b2]["name"]))
			parts.append("a GREAT BLESSING! " + (", ".join(names) if not names.is_empty() else "the party is restored"))
		elif r < 0.6:
			var rb: String = grant_random_relic()
			parts.append(("blessed with %s" % String(RELICS[rb]["name"])) if rb != "" else "a faint blessing")
		else:
			var rc: String = grant_random_curse()
			parts.append(("cursed with %s" % String(CURSES[rc]["name"])) if rc != "" else "the omen passes")
	if eff.has("add_upgrade") and not player_roster.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var idx: int = rng.randi() % player_roster.size()
		var ups := random_upgrade_choices(1)
		if not ups.is_empty():
			apply_upgrade(idx, ups[0])
			parts.append("%s trained" % String(UNIT_TYPES[player_roster[idx]["type"]]["name"]))
	if eff.has("lose_unit") and bool(eff["lose_unit"]) and not player_roster.is_empty():
		var worst: int = 0
		for i in range(player_roster.size()):
			if int(player_roster[i]["hp"]) < int(player_roster[worst]["hp"]):
				worst = i
		var lost_name: String = String(UNIT_TYPES[player_roster[worst]["type"]]["name"])
		player_roster.remove_at(worst)
		parts.append("lost %s" % lost_name)
	if parts.is_empty():
		return "You move on."
	return ", ".join(parts).capitalize()

# ---------------------------------------------------------------------------
# Economy
# ---------------------------------------------------------------------------
# Gold rewarded for winning a battle, scaling with tier and elite status.
func battle_gold_reward(tier: int, elite: bool) -> int:
	return 25 + tier * 10 + (25 if elite else 0) + (20 if has_relic("coffer") else 0)

func add_gold(amount: int) -> void:
	gold += amount

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true

# ---------------------------------------------------------------------------
# Relics
# ---------------------------------------------------------------------------
func has_relic(id: String) -> bool:
	return id in relics

func add_relic(id: String) -> void:
	if id not in relics:
		relics.append(id)

func unowned_relics() -> Array[String]:
	var out: Array[String] = []
	for id: String in RELICS:
		if id not in relics:
			out.append(id)
	return out

# Grant a random unowned relic (e.g. elite reward). Returns its id, or "".
func grant_random_relic() -> String:
	var pool := unowned_relics()
	if pool.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var id: String = pool[rng.randi() % pool.size()]
	add_relic(id)
	return id

func relic_damage_bonus() -> int:
	return (8 if has_relic("whetstone") else 0) + (25 if has_relic("divine_favor") else 0)

func relic_move_bonus() -> int:
	return (1 if has_relic("boots") else 0) + (2 if has_relic("divine_favor") else 0)

func relic_max_hp_bonus() -> int:
	return (20 if has_relic("plating") else 0) + (60 if has_relic("divine_favor") else 0)

func relic_range_bonus() -> int:
	return (1 if has_relic("longbow") else 0) + (1 if has_relic("divine_favor") else 0)

func relic_ap_bonus() -> int:
	return (1 if has_relic("war_banner") else 0) + (1 if has_relic("divine_favor") else 0)

func relic_crit_bonus() -> float:
	return (0.12 if has_relic("keen_edge") else 0.0) + (0.25 if has_relic("divine_favor") else 0.0)

# Multiplier on damage the player's units take (Aegis / Divine Favour). 1.0 = none.
func relic_damage_taken_mult() -> float:
	var m: float = 1.0
	if has_relic("aegis"):
		m *= 0.85
	if has_relic("divine_favor"):
		m *= 0.60
	return m

# --- Curses ---------------------------------------------------------------
func has_curse(id: String) -> bool:
	return id in curses

func add_curse(id: String) -> void:
	if id not in curses and CURSES.has(id):
		curses.append(id)

func grant_random_curse() -> String:
	var pool: Array[String] = []
	for id: String in CURSES:
		if id not in curses:
			pool.append(id)
	if pool.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cid: String = pool[rng.randi() % pool.size()]
	add_curse(cid)
	return cid

func curse_max_hp_penalty() -> int:
	return (15 if has_curse("frailty") else 0) + (50 if has_curse("damnation") else 0)

func curse_damage_penalty() -> int:
	return (5 if has_curse("dullness") else 0) + (20 if has_curse("damnation") else 0)

func curse_move_penalty() -> int:
	return (1 if has_curse("sloth") else 0) + (2 if has_curse("damnation") else 0)
