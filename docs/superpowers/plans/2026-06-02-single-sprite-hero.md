# Single-Sprite Hero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the hero representation in-battle to display as a single unit sprite that is slightly larger (scale 1.3), while retaining the collision footprint and gameplay radius of a full squad.

**Architecture:** We will pass a flag indicating if a unit is the hero from the autobattler scene down to `RTUnit`. Within `RTUnit`, if this flag is true, we preserve the original base soldier count for radius calculations, but visually construct only a single sprite at the center with a larger scale.

**Tech Stack:** GDScript (Godot 4.4)

---

### Task 1: Pass Hero Status from Autobattler to RTUnit

**Files:**
- Modify: [autobattler.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/autobattler/autobattler.gd)

- [ ] **Step 1: Update `_start_duel_fight()` to set `"hero": true` on the hero card**
  Modify the `hero_card` dictionary initialization so it always specifies `"hero": true`.
  *Target lines 1031-1036 in [autobattler.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/autobattler/autobattler.gd):*
  ```gdscript
  	var hero_card: Dictionary
  	if GameManager.has_hero():
  		var hd := GameManager.hero_data()
  		hero_card = {"id": String(hd["fight_archetype"]), "level": int(hd["fight_level"]) + GameManager.hero_fight_bonus_level(), "xp": 0}
  	else:
  		hero_card = {"id": "soldier", "level": 1 + GameManager.hero_fight_bonus_level(), "xp": 0}
  ```
  *Replacement:*
  ```gdscript
  	var hero_card: Dictionary
  	if GameManager.has_hero():
  		var hd := GameManager.hero_data()
  		hero_card = {"id": String(hd["fight_archetype"]), "level": int(hd["fight_level"]) + GameManager.hero_fight_bonus_level(), "xp": 0, "hero": true}
  	else:
  		hero_card = {"id": "soldier", "level": 1 + GameManager.hero_fight_bonus_level(), "xp": 0, "hero": true}
  ```

- [ ] **Step 2: Propagate the hero flag in `_spawn_unit()`**
  Pass the `"hero"` key from the card metadata into the `stats` dictionary as `"is_hero"` so the `RTUnit` setup can read it.
  *Target lines 1082-1085 in [autobattler.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/autobattler/autobattler.gd):*
  ```gdscript
  	if String(card.get("item", "")) == "drum":
  		stats["move_speed_px"] = float(stats.get("move_speed_px", 60.0)) + 12.0
  	u.setup(unit_id, team_id, pos, stats)
  ```
  *Replacement:*
  ```gdscript
  	if String(card.get("item", "")) == "drum":
  		stats["move_speed_px"] = float(stats.get("move_speed_px", 60.0)) + 12.0
  	stats["is_hero"] = card.get("hero", false)
  	u.setup(unit_id, team_id, pos, stats)
  ```

- [ ] **Step 3: Run the headless smoke test to verify there are no syntax/parser errors**
  Run: `tools/smoke_test.sh`
  Expected output: "== all scenes booted clean =="

- [ ] **Step 4: Commit changes for Task 1**
  ```bash
  git add src/autobattler/autobattler.gd
  git commit -m "feat: propagate hero status from autobattler to unit setup"
  ```

---

### Task 2: Implement Single-Sprite Rendering and Scale in RTUnit

**Files:**
- Modify: [rt_unit.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/rtbattle/rt_unit.gd)

- [ ] **Step 1: Declare `is_hero` class member**
  Add the member variable under configuration.
  *Target lines 30-31 in [rt_unit.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/rtbattle/rt_unit.gd):*
  ```gdscript
  var unit_name: String = "Soldier"
  ```
  *Replacement:*
  ```gdscript
  var unit_name: String = "Soldier"
  var is_hero: bool = false
  ```

- [ ] **Step 2: Read `is_hero` and customize count / radius setup**
  Update `setup()` to read `is_hero`, compute radius using base count, and override `soldier_count` to `1` with total HP.
  *Target lines 71-91 in [rt_unit.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/rtbattle/rt_unit.gd):*
  ```gdscript
  func setup(type: String, p_team: int, world_pos: Vector2, stats: Dictionary) -> void:
  	unit_type        = type
  	team             = p_team
  	position         = world_pos
  	unit_name        = String(stats.get("name", type.capitalize()))
  	soldier_count    = int(stats.get("soldier_count", 9))
  	hp_per_soldier   = int(stats.get("hp_per_soldier", 15))
  	max_hp           = soldier_count * hp_per_soldier
  	hp               = max_hp
  	damage_per_attack = int(stats.get("damage_per_attack", 8))
  	attack_cooldown   = float(stats.get("attack_cooldown", 1.1))
  	attack_range_px   = float(stats.get("attack_range_px", 60.0))
  	move_speed_px     = float(stats.get("move_speed_px", 60.0))
  	is_ranged         = attack_range_px > 80.0
  	# Radius scales with soldier count so a 9-man block is wider than a 5-man.
  	radius            = 18.0 + sqrt(float(soldier_count)) * 7.0
  	# Idle stance: detect enemies within attack range + a small buffer so
  	# units engage smoothly rather than chattering at the threshold.
  	engage_radius_px  = attack_range_px + 40.0
  	_build_visuals(stats)
  ```
  *Replacement:*
  ```gdscript
  func setup(type: String, p_team: int, world_pos: Vector2, stats: Dictionary) -> void:
  	unit_type        = type
  	team             = p_team
  	position         = world_pos
  	unit_name        = String(stats.get("name", type.capitalize()))
  	is_hero          = bool(stats.get("is_hero", false))
  	var base_soldier_count = int(stats.get("soldier_count", 9))
  	if is_hero:
  		soldier_count = 1
  		hp_per_soldier = base_soldier_count * int(stats.get("hp_per_soldier", 15))
  	else:
  		soldier_count = base_soldier_count
  		hp_per_soldier = int(stats.get("hp_per_soldier", 15))
  	max_hp           = soldier_count * hp_per_soldier
  	hp               = max_hp
  	damage_per_attack = int(stats.get("damage_per_attack", 8))
  	attack_cooldown   = float(stats.get("attack_cooldown", 1.1))
  	attack_range_px   = float(stats.get("attack_range_px", 60.0))
  	move_speed_px     = float(stats.get("move_speed_px", 60.0))
  	is_ranged         = attack_range_px > 80.0
  	# Radius scales with base soldier count so hero has full squad blocking footprint.
  	radius            = 18.0 + sqrt(float(base_soldier_count)) * 7.0
  	# Idle stance: detect enemies within attack range + a small buffer so
  	# units engage smoothly rather than chattering at the threshold.
  	engage_radius_px  = attack_range_px + 40.0
  	_build_visuals(stats)
  ```

- [ ] **Step 3: Update `_build_visuals()` to position and scale the hero sprite**
  Center the hero sprite at `(0, 0)` with a scale of `1.3`, avoiding grid offsets or jitter.
  *Target lines 125-155 in [rt_unit.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/rtbattle/rt_unit.gd):*
  ```gdscript
  	# Build soldier sprites in a loose grid around the centre.
  	var sprite_key: String = String(stats.get("sprite_key", unit_type))
  	var team_name: String  = "player" if team == 0 else "enemy"
  	var tex: Texture2D     = load("res://assets/units/%s_%s.png" % [sprite_key, team_name])

  	var cols: int = max(1, int(ceil(sqrt(float(soldier_count)))))
  	var spacing: float = (radius * 1.6) / float(cols)
  	for i in range(soldier_count):
  		var s := Soldier.new()
  		var col: int = i % cols
  		var row: int = i / cols
  		# Centre the formation around (0,0). Add a small per-soldier jitter
  		# so the regiment looks like a crowd rather than a grid.
  		var seed_v := Vector2(
  			float(i) * 12.9898,
  			float(i) * 78.233
  		)
  		var jitter := Vector2(
  			fposmod(sin(seed_v.x) * 43758.5453, 1.0) - 0.5,
  			fposmod(sin(seed_v.y) * 43758.5453, 1.0) - 0.5
  			) * (spacing * 0.4)
  		var ox: float = (float(col) - float(cols - 1) * 0.5) * spacing + jitter.x
  		var oy: float = (float(row) - float(cols - 1) * 0.5) * spacing + jitter.y
  		s.offset       = Vector2(ox, oy)
  		s.sprite       = Sprite2D.new()
  		s.sprite.texture        = tex
  		s.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  		s.sprite.scale          = Vector2(0.9, 0.9)
  		s.sprite.position       = s.offset
  		add_child(s.sprite)
  		_soldiers.append(s)
  ```
  *Replacement:*
  ```gdscript
  	# Build soldier sprites in a loose grid around the centre.
  	var sprite_key: String = String(stats.get("sprite_key", unit_type))
  	var team_name: String  = "player" if team == 0 else "enemy"
  	var tex: Texture2D     = load("res://assets/units/%s_%s.png" % [sprite_key, team_name])

  	var cols: int = max(1, int(ceil(sqrt(float(soldier_count)))))
  	var spacing: float = (radius * 1.6) / float(cols)
  	for i in range(soldier_count):
  		var s := Soldier.new()
  		var ox: float = 0.0
  		var oy: float = 0.0
  		if not is_hero:
  			var col: int = i % cols
  			var row: int = i / cols
  			# Centre the formation around (0,0). Add a small per-soldier jitter
  			# so the regiment looks like a crowd rather than a grid.
  			var seed_v := Vector2(
  				float(i) * 12.9898,
  				float(i) * 78.233
  			)
  			var jitter := Vector2(
  				fposmod(sin(seed_v.x) * 43758.5453, 1.0) - 0.5,
  				fposmod(sin(seed_v.y) * 43758.5453, 1.0) - 0.5
  			) * (spacing * 0.4)
  			ox = (float(col) - float(cols - 1) * 0.5) * spacing + jitter.x
  			oy = (float(row) - float(cols - 1) * 0.5) * spacing + jitter.y
  		s.offset       = Vector2(ox, oy)
  		s.sprite       = Sprite2D.new()
  		s.sprite.texture        = tex
  		s.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  		s.sprite.scale          = Vector2(1.3, 1.3) if is_hero else Vector2(0.9, 0.9)
  		s.sprite.position       = s.offset
  		add_child(s.sprite)
  		_soldiers.append(s)
  ```

- [ ] **Step 4: Run the headless smoke test to verify no syntax errors**
  Run: `tools/smoke_test.sh`
  Expected output: "== all scenes booted clean =="

- [ ] **Step 5: Commit changes for Task 2**
  ```bash
  git add src/rtbattle/rt_unit.gd
  git commit -m "feat: render hero as single unit sprite at scale 1.3"
  ```
