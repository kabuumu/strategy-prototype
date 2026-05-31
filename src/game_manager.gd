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
		"move_range": 5,
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
		"sprite_unit": "soldier",   # which sprite file to load
		"is_boss": true,
		# Enrage bonuses applied when hp/max_hp drops to (or below) threshold
		"enrage_threshold": 0.5,
		"enrage_damage_bonus": 15,
		"enrage_move_bonus": 1,
		"enrage_range_bonus": 1,
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
	}
}

# How much the Healer's Field Heal restores
const HEAL_ABILITY_AMOUNT: int = 35

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
# Map constants
# ---------------------------------------------------------------------------
const MAP_TIERS: int = 5
# Tier sizes are generated per-run (see _generate_map).
# Last tier is always 1 node (boss); others vary from 2–5.

# ---------------------------------------------------------------------------
# Persistent game state
# ---------------------------------------------------------------------------
# Each entry: { "type": String, "hp": int }  — HP persists across battles,
# and units that die in battle are removed (permadeath).
var player_roster: Array[Dictionary] = []
var gold: int = 0
var relics: Array[String] = []   # owned relic ids (run-long passives)
var current_tier: int = 0
var last_chosen_index: int = -1
var map_data: Array = []

# Run statistics — reset on every new run
var battles_won: int = 0
var elites_defeated: int = 0
var units_lost: int = 0
var best_streak_ever: int = 0   # persists across runs

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
}

# Set before switching to the battle scene
var pending_battle_tier: int = 0
var pending_battle_elite: bool = false

# ---------------------------------------------------------------------------
func _ready() -> void:
	reset()

func reset() -> void:
	player_roster = []
	for t: String in ["soldier", "soldier", "archer"]:
		add_unit(t)
	gold = 0
	relics = []
	current_tier = 0
	last_chosen_index = -1
	pending_battle_tier = 0
	pending_battle_elite = false
	battles_won = 0
	elites_defeated = 0
	units_lost = 0
	_generate_map()

# Called by battle on victory. Updates streak counters.
func register_battle_won(elite: bool) -> void:
	battles_won += 1
	if elite:
		elites_defeated += 1
	if battles_won > best_streak_ever:
		best_streak_ever = battles_won

# ---------------------------------------------------------------------------
# Map generation
# ---------------------------------------------------------------------------
func _generate_map() -> void:
	map_data.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Tier 0 always starts as a single central node; middle tiers vary 2-5; final tier = 1 (boss)
	var sizes: Array = []
	sizes.append(1)
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

	# Wire up connections between every adjacent tier pair
	for tier in range(MAP_TIERS - 1):
		_generate_connections(tier, rng)

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
	if tier == 0:
		return "battle"
	var roll := rng.randi() % 10
	if roll < 4:
		return "battle"
	elif roll < 6:
		return "elite_battle"
	elif roll < 7:
		return "gain_unit"
	elif roll < 9:
		return "shop"
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
	# Final-tier elite is the boss fight — Warlord plus a small honour guard
	if is_final_battle(tier, elite):
		return ["warlord", "archer", "soldier"] as Array[String]
	var rng := RandomNumberGenerator.new()
	rng.seed = tier * 31 + (13 if elite else 7)
	var pool: Array[String] = ["soldier", "archer", "scout"]
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
	})

# Restore every roster unit to full HP (heal node). Honours VETERAN HP boosts.
func heal_roster() -> void:
	for entry: Dictionary in player_roster:
		entry["hp"] = unit_effective_max_hp(entry)

# Called by battle on victory: rebuild roster from surviving units (dead units
# are dropped — permadeath) carrying their remaining HP and upgrades forward.
func set_roster(survivors: Array[Dictionary]) -> void:
	units_lost += max(0, player_roster.size() - survivors.size())
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
# Economy
# ---------------------------------------------------------------------------
# Gold rewarded for winning a battle, scaling with tier and elite status.
func battle_gold_reward(tier: int, elite: bool) -> int:
	return 25 + tier * 10 + (25 if elite else 0)

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
	return 8 if has_relic("whetstone") else 0

func relic_move_bonus() -> int:
	return 1 if has_relic("boots") else 0

func relic_max_hp_bonus() -> int:
	return 20 if has_relic("plating") else 0
