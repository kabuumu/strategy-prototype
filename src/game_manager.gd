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
const NODES_PER_TIER: int = 3

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
	for tier in range(MAP_TIERS):
		var nodes: Array = []
		for i in range(NODES_PER_TIER):
			nodes.append({
				"type": _pick_node_type(tier, rng),
				"tier": tier,
				"index": i,
				"visited": false
			})
		map_data.append(nodes)

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
	if last_chosen_index == -1:
		return [0, 1, 2]
	var reach: Array = [last_chosen_index]
	if last_chosen_index > 0:
		reach.append(last_chosen_index - 1)
	if last_chosen_index < NODES_PER_TIER - 1:
		reach.append(last_chosen_index + 1)
	return reach

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
