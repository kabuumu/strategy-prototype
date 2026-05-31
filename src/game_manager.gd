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
		"color": Color(0.25, 0.5, 1.0)
	},
	"archer": {
		"name": "Archer",
		"max_hp": 70,
		"move_range": 2,
		"attack_range": 3,
		"damage": 25,
		"color": Color(0.2, 0.75, 0.35)
	},
	"scout": {
		"name": "Scout",
		"max_hp": 60,
		"move_range": 5,
		"attack_range": 1,
		"damage": 20,
		"color": Color(0.95, 0.8, 0.1)
	}
}

# ---------------------------------------------------------------------------
# Map constants
# ---------------------------------------------------------------------------
const MAP_TIERS: int = 5
# Tier sizes are generated per-run (see _generate_map).
# Last tier is always 1 node (boss); others vary from 2–5.

# ---------------------------------------------------------------------------
# Persistent game state
# ---------------------------------------------------------------------------
var player_roster: Array[String] = []
var current_tier: int = 0
var last_chosen_index: int = -1
var map_data: Array = []

# Set before switching to the battle scene
var pending_battle_tier: int = 0
var pending_battle_elite: bool = false

# ---------------------------------------------------------------------------
func _ready() -> void:
	reset()

func reset() -> void:
	player_roster = ["soldier", "soldier", "archer"]
	current_tier = 0
	last_chosen_index = -1
	pending_battle_tier = 0
	pending_battle_elite = false
	_generate_map()

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
	if roll < 5:
		return "battle"
	elif roll < 7:
		return "elite_battle"
	elif roll < 9:
		return "gain_unit"
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
	var rng := RandomNumberGenerator.new()
	rng.seed = tier * 31 + (13 if elite else 7)
	var pool: Array[String] = ["soldier", "archer", "scout"]
	var count: int = clampi(2 + tier + (1 if elite else 0), 2, 5)
	var result: Array[String] = []
	for _i in range(count):
		result.append(pool[rng.randi() % pool.size()])
	return result

func get_hp_multiplier(tier: int, elite: bool) -> float:
	return 1.0 + tier * 0.2 + (0.25 if elite else 0.0)

# ---------------------------------------------------------------------------
# Roster management
# ---------------------------------------------------------------------------
func add_unit(unit_type: String) -> void:
	player_roster.append(unit_type)
