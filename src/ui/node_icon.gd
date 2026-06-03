class_name NodeIcon
extends Control

# A small map-node glyph (coloured disc + type icon) used in the level-select
# legend so the key matches exactly what's drawn on the overworld. The glyph
# shapes live in the static draw_glyph() so the map renderer (_draw_node_icon)
# and this control share one source of truth.

var node_type: String = "battle"
var disc_color: Color = Color.GRAY

func _init(p_type: String = "battle", p_color: Color = Color.GRAY) -> void:
	node_type = p_type
	disc_color = p_color
	custom_minimum_size = Vector2(22.0, 22.0)
	size = Vector2(22.0, 22.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := Vector2(11.0, 11.0)
	draw_circle(c, 10.0, disc_color)
	draw_arc(c, 10.0, 0.0, TAU, 20, disc_color.lightened(0.3), 1.5)
	draw_glyph(self, c, 6.0, node_type, Color(0.97, 0.97, 1.0, 0.95))

# Draw the per-type icon centred on `c` with radius `r` in colour `w`.
static func draw_glyph(ci: CanvasItem, c: Vector2, r: float, type: String, w: Color) -> void:
	match type:
		"battle":   # crossed swords
			ci.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), w, maxf(2.0, r * 0.5))
			ci.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), w, maxf(2.0, r * 0.5))
		"elite_battle":   # burst
			for k in range(4):
				var a := float(k) * PI / 4.0
				var d := Vector2(cos(a), sin(a)) * r
				ci.draw_line(c - d, c + d, w, maxf(1.5, r * 0.4))
		"shop":   # coin
			ci.draw_arc(c, r, 0.0, TAU, 16, w, maxf(2.0, r * 0.45))
			ci.draw_string(ThemeDB.fallback_font, c + Vector2(-r * 0.55, r * 0.55), "$",
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 2.0), w)
		"heal":   # cross
			ci.draw_line(c + Vector2(0.0, -r), c + Vector2(0.0, r), w, maxf(2.5, r * 0.6))
			ci.draw_line(c + Vector2(-r, 0.0), c + Vector2(r, 0.0), w, maxf(2.5, r * 0.6))
		"gain_unit":   # figure
			ci.draw_circle(c + Vector2(0.0, -r * 0.45), r * 0.42, w)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, r * 0.05), Vector2(r * 1.1, r * 0.8)), w)
		"treasure":   # gem
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(r * 0.8, 0.0),
				c + Vector2(0.0, r), c + Vector2(-r * 0.8, 0.0)]), w)
		"event":   # question mark
			ci.draw_string(ThemeDB.fallback_font, c + Vector2(-r * 0.55, r * 0.7), "?",
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 2.2), w)
		_:
			ci.draw_circle(c, r * 0.5, w)
