extends Control
# Reusable hero skill-tree screen (Spec A) — CK3-style branching diamonds.
# Opened in-game (from the overworld) to spend banked XP on permanent per-hero
# nodes. "Skill points" are the single progression unit (no separate level).
#
# Layout per section: a CK3 diamond — a root that unlocks two branches, each
# branch chains down, and they converge at a capstone. Connector lines are
# drawn in _draw (behind the node buttons).

const UITheme := preload("res://src/ui/ui_theme.gd")

const SECTIONS: Array = ["might", "command", "guile", "tactics"]
const SEC_TITLE: Dictionary = {"might": "Might", "command": "Command", "guile": "Guile", "tactics": "Tactics"}
# Node order per section: [root, A1, A2, B1, B2, capstone].
const SEC_ORDER: Dictionary = {
	"might":   ["conditioning", "honed_blade", "warlord", "quickstep", "veteran", "might_cap"],
	"command": ["drillmaster", "banneret", "inspiring", "quartermaster", "thrifty", "command_sig"],
	"guile":   ["charisma", "negotiator", "silver_tongue", "duelist", "war_chest", "guile_cap"],
	"tactics": ["field_kit", "bandolier", "quick_draw", "scout_ahead", "reserves", "tactics_cap"],
}
const NODE_LABEL: Dictionary = {
	"conditioning": "Conditioning", "honed_blade": "Honed Blade", "warlord": "Warlord",
	"quickstep": "Quickstep", "veteran": "Veteran", "might_cap": "Bastion",
	"drillmaster": "Drillmaster", "banneret": "Banneret", "inspiring": "Inspiring",
	"quartermaster": "Quartermaster", "thrifty": "Steadfast", "command_sig": "Signature",
	"charisma": "Charisma", "negotiator": "Negotiator", "silver_tongue": "Silver Tongue",
	"duelist": "Duelist", "war_chest": "War Chest", "guile_cap": "Legend",
	"field_kit": "Field Kit", "bandolier": "Bandolier", "quick_draw": "Quick Draw",
	"scout_ahead": "Scout Ahead", "reserves": "Reserves", "tactics_cap": "Mastery",
}

var _hero: String = ""
var _on_close: Callable = Callable()
var _centers: Dictionary = {}   # node_id -> Vector2 (button centre, for connectors)

func setup(hero_id: String, on_close: Callable) -> void:
	_hero = hero_id
	_on_close = on_close
	GameManager.selected_hero = hero_id   # point the buy/respec helpers at this hero
	z_index = 300
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_centers.clear()

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.86)
	dim.size = Vector2(1280.0, 720.0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	UITheme.panel(self, Vector2(96.0, 36.0), Vector2(1088.0, 648.0), UITheme.PANEL, UITheme.LINE)

	var hero: Dictionary = GameManager.HEROES.get(_hero, {})
	add_child(UITheme.label("HERO SKILL TREE — %s" % String(hero.get("name", "Hero")), 28, UITheme.GOLD,
		Vector2(118.0, 50.0), Vector2(700.0, 36.0)))
	var xp: int = GameManager.hero_banked_xp(_hero)
	var earned: int = GameManager.hero_meta_level(_hero) - 1
	var unspent: int = GameManager.hero_unspent_points(_hero)
	add_child(UITheme.label("Skill points: %d unspent  ·  %d earned  ·  XP banked: %d" % [unspent, earned, xp],
		16, UITheme.TEXT, Vector2(118.0, 92.0), Vector2(680.0, 24.0)))

	var cost: int = GameManager.hero_level_cost(GameManager.hero_meta_level(_hero))
	var bp := UITheme.button("Earn Skill Point  (%d XP)" % cost, Vector2(818.0, 52.0), Vector2(248.0, 34.0),
		UITheme.GREEN.darkened(0.1) if xp >= cost else Color(0.20, 0.22, 0.26), _on_buy_point, 14)
	bp.disabled = xp < cost
	add_child(bp)
	var rs := UITheme.button("Respec  (−1 earned point)", Vector2(818.0, 92.0), Vector2(248.0, 30.0),
		Color(0.50, 0.28, 0.28) if earned > 0 else Color(0.20, 0.20, 0.24), _on_respec, 13)
	rs.disabled = earned <= 0
	add_child(rs)

	var sec_top := 168.0
	for si in range(SECTIONS.size()):
		var sec: String = SECTIONS[si]
		var ox: float = 118.0 + float(si) * 262.0
		add_child(UITheme.label(str(SEC_TITLE[sec]), 17, UITheme.GOLD.lightened(0.1),
			Vector2(ox + 50.0, sec_top - 28.0), Vector2(160.0, 22.0)))
		_layout_section(sec, ox, sec_top)

	add_child(UITheme.button("Close", Vector2(560.0, 636.0), Vector2(160.0, 40.0),
		Color(0.30, 0.32, 0.44), _on_close_pressed, 16))
	queue_redraw()

func _layout_section(sec: String, ox: float, sy: float) -> void:
	var nodes: Array = SEC_ORDER[sec]
	var p: Array = [
		Vector2(ox + 66.0, sy),          # root
		Vector2(ox + 6.0,  sy + 76.0),   # A1
		Vector2(ox + 6.0,  sy + 152.0),  # A2
		Vector2(ox + 126.0, sy + 76.0),  # B1
		Vector2(ox + 126.0, sy + 152.0), # B2
		Vector2(ox + 66.0, sy + 228.0),  # capstone
	]
	for i in range(6):
		var nid: String = nodes[i]
		_centers[nid] = p[i] + Vector2(54.0, 20.0)
		_add_node(nid, p[i])

func _add_node(nid: String, pos: Vector2) -> void:
	var def: Dictionary = GameManager.HERO_TREE[nid]
	var rank: int = GameManager.hero_node_rank(nid)
	var maxr: int = int(def["max_rank"])
	var can: bool = GameManager.hero_can_buy_node(nid)
	var col: Color
	if rank >= 1 and rank >= maxr:
		col = UITheme.GREEN.darkened(0.2)
	elif rank >= 1:
		col = UITheme.BLUE.darkened(0.05)
	elif can:
		col = UITheme.GOLD.darkened(0.2)
	else:
		col = Color(0.17, 0.18, 0.22)
	var btn := UITheme.button("%s\n%d/%d" % [str(NODE_LABEL.get(nid, nid)), rank, maxr],
		pos, Vector2(108.0, 40.0), col, _on_node.bind(nid), 11)
	btn.disabled = not can
	add_child(btn)

func _draw() -> void:
	for sec in SECTIONS:
		var n: Array = SEC_ORDER[sec]
		_link(n[0], n[1]); _link(n[0], n[3])   # root -> both branch entries
		_link(n[1], n[2]); _link(n[3], n[4])   # branch chains
		_link(n[2], n[5]); _link(n[4], n[5])   # converge at the capstone

func _link(a: String, b: String) -> void:
	if not (_centers.has(a) and _centers.has(b)):
		return
	var owned: bool = GameManager.hero_node_rank(a) >= 1
	draw_line(_centers[a], _centers[b],
		UITheme.GOLD.darkened(0.05) if owned else Color(0.32, 0.34, 0.42), 2.0)

func _on_node(nid: String) -> void:
	if GameManager.hero_buy_node(nid):
		GameManager._save_meta()
		_rebuild()

func _on_buy_point() -> void:
	if GameManager.hero_buy_level():
		GameManager._save_meta()
		_rebuild()

func _on_respec() -> void:
	if GameManager.hero_respec():
		GameManager._save_meta()
		_rebuild()

func _on_close_pressed() -> void:
	var cb := _on_close
	queue_free()
	if cb.is_valid():
		cb.call()
