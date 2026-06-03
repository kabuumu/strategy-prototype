class_name UITheme
extends Node

const BG: Color = Color(0.055, 0.065, 0.090)
const PANEL: Color = Color(0.095, 0.105, 0.145, 0.96)
const LINE: Color = Color(0.29, 0.31, 0.40, 0.90)
const TEXT: Color = Color(0.86, 0.89, 0.92)
const TEXT_MUTED: Color = Color(0.58, 0.61, 0.68)
const GOLD: Color = Color(0.95, 0.82, 0.34)
const GREEN: Color = Color(0.34, 0.74, 0.44)
const BLUE: Color = Color(0.24, 0.42, 0.72)
const RED: Color = Color(0.78, 0.25, 0.25)

static func panel_style(bg: Color = PANEL, border: Color = LINE, radius: int = 6, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = width
	s.border_width_right = width
	s.border_width_top = width
	s.border_width_bottom = width
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

static func button_style(color: Color, radius: int = 6, border_width: int = 2) -> StyleBoxFlat:
	return panel_style(color, color.lightened(0.24), radius, border_width)

static func label(text: String, font_size: int, color: Color, pos: Vector2, size: Vector2 = Vector2.ZERO) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = color
	lbl.position = pos
	if size != Vector2.ZERO:
		# Free Labels wrap at custom_minimum_size.x ONLY if `size` is left alone —
		# setting `.size` lets the control grow to its full single-line content
		# width (overriding the floor), so the text never wraps. Pin the box via
		# custom_minimum_size and let autowrap settle the width.
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = size
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func panel(parent: Node, pos: Vector2, size: Vector2, bg: Color = PANEL, border: Color = LINE) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", panel_style(bg, border))
	parent.add_child(p)
	return p

static func button(text: String, pos: Vector2, size: Vector2, color: Color, cb: Callable, font_size: int = 18, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = size
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_stylebox_override("normal", button_style(color))
	btn.add_theme_stylebox_override("hover", button_style(color.lightened(0.14)))
	btn.add_theme_stylebox_override("pressed", button_style(color.darkened(0.22)))
	btn.add_theme_stylebox_override("focus", button_style(color.lightened(0.08)))
	if tooltip != "":
		btn.tooltip_text = tooltip
	btn.pressed.connect(cb)
	return btn


# Full-screen help overlay: dimmed background, a titled panel of body text, and
# a Close button. Returns the root Control — add it as a child, free to dismiss.
static func help_overlay(title: String, body: String, on_close: Callable) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.z_index = 4096
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	panel(root, Vector2(240.0, 86.0), Vector2(800.0, 548.0))
	root.add_child(label(title, 28, GOLD, Vector2(280.0, 104.0), Vector2(720.0, 36.0)))
	root.add_child(label(body, 16, TEXT, Vector2(280.0, 156.0), Vector2(724.0, 360.0)))
	root.add_child(button("Close   [H / Esc]", Vector2(520.0, 556.0), Vector2(240.0, 44.0),
		Color(0.30, 0.32, 0.44), on_close))
	return root

static func chip(parent: Node, text: String, pos: Vector2, color: Color, width: float = 120.0) -> Label:
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = Vector2(width, 24.0)
	bg.color = color.darkened(0.38)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

	var lbl := label(text, 12, color.lightened(0.28), pos + Vector2(8.0, 4.0), Vector2(width - 16.0, 18.0))
	parent.add_child(lbl)
	return lbl
