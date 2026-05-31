class_name UITheme
extends Node

const BG: Color = Color(0.055, 0.065, 0.090)
const PANEL: Color = Color(0.095, 0.105, 0.145, 0.96)
const PANEL_ALT: Color = Color(0.075, 0.085, 0.120, 0.95)
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
		lbl.size = size
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func panel(parent: Node, pos: Vector2, size: Vector2, bg: Color = PANEL, border: Color = LINE) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", panel_style(bg, border))
	parent.add_child(p)
	return p

static func color_band(parent: Node, pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

static func button(text: String, pos: Vector2, size: Vector2, color: Color, cb: Callable, font_size: int = 18) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = size
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_stylebox_override("normal", button_style(color))
	btn.add_theme_stylebox_override("hover", button_style(color.lightened(0.14)))
	btn.add_theme_stylebox_override("pressed", button_style(color.darkened(0.22)))
	btn.add_theme_stylebox_override("focus", button_style(color.lightened(0.08)))
	btn.pressed.connect(cb)
	return btn

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
