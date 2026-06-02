# Hero Front Formation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the battle line formation during campaign fights so that the hero (in Fight mode) is always positioned at the very front (closest to the enemy), while keeping the fallback stats and write-back functionality correct.

**Architecture:** Modify `_start_campaign_fight()` in `autobattler.gd` so that the hero's card is prepended at index 0 of `p_cards` (and its corresponding `null` entry at index 0 of `p_entries`), rather than appended at the end of the arrays.

**Tech Stack:** GDScript (Godot 4.4)

---

### Task 1: Prepend Hero to Campaign Cards

**Files:**
- Modify: [autobattler.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/autobattler/autobattler.gd)

- [ ] **Step 1: Move hero spawning code block to the beginning of roster spawning**
  Change the spawning setup logic in `_start_campaign_fight()` so the hero card is added to the empty `p_cards`/`p_entries` arrays first, followed by the normal roster entries.
  *Target lines 911-924 in [autobattler.gd](file:///Users/robhawkes/Documents/personal/godot/strategy-prototype/src/autobattler/autobattler.gd):*
  ```gdscript
  	# Player team — one regiment per campaign roster entry (remembered so the
  	# survivors can be written back with permadeath after the fight).
  	var p_cards: Array = []
  	var p_entries: Array = []
  	for entry: Dictionary in GameManager.player_roster:
  		p_cards.append(_campaign_card(String(entry["type"])))
  		p_entries.append(entry)
  	# Hero fights as an extra card (Fight mode). The null roster entry keeps the
  	# zip aligned and signals the survivor write-back to skip it (never persisted).
  	if GameManager.has_hero() and GameManager.hero_battle_mode == "fight":
  		var hd := GameManager.hero_data()
  		p_cards.append({"id": String(hd["fight_archetype"]), "level": int(hd["fight_level"]) + GameManager.hero_fight_bonus_level(), "xp": 0, "hero": true})
  		p_entries.append(null)
  ```
  *Replacement:*
  ```gdscript
  	# Player team — one regiment per campaign roster entry (remembered so the
  	# survivors can be written back with permadeath after the fight).
  	var p_cards: Array = []
  	var p_entries: Array = []
  	# Prepend Hero if fighting (Fight mode) so they receive the front-most index (0)
  	if GameManager.has_hero() and GameManager.hero_battle_mode == "fight":
  		var hd := GameManager.hero_data()
  		p_cards.append({"id": String(hd["fight_archetype"]), "level": int(hd["fight_level"]) + GameManager.hero_fight_bonus_level(), "xp": 0, "hero": true})
  		p_entries.append(null)
  	for entry: Dictionary in GameManager.player_roster:
  		p_cards.append(_campaign_card(String(entry["type"])))
  		p_entries.append(entry)
  ```

- [ ] **Step 2: Run the headless smoke test to verify no compilation/parser errors**
  Run: `tools/smoke_test.sh`
  Expected output: "== all scenes booted clean =="

- [ ] **Step 3: Commit changes for Task 1**
  ```bash
  git add src/autobattler/autobattler.gd
  git commit -m "feat: place hero at the front of the battle formation"
  ```
