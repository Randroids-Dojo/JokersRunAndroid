class_name UiKit
extends RefCounted
## Fonts, text styles and small widget builders shared by the HUD, touch controls and screens.

static var semibold: FontFile
static var bold: FontFile
static var bold_italic: FontFile
static var medium: FontFile
static var _spaced := {}


static func init() -> void:
	if semibold:
		return
	semibold = load("res://assets/fonts/ChakraPetch-SemiBold.ttf")
	bold = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	bold_italic = load("res://assets/fonts/ChakraPetch-BoldItalic.ttf")
	medium = load("res://assets/fonts/ChakraPetch-Medium.ttf")


## A letter-spaced variant (CSS letter-spacing in px).
static func spaced(base: Font, px: float) -> Font:
	var key := "%s:%.1f" % [base.resource_path, px]
	if _spaced.has(key):
		return _spaced[key]
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = int(round(px))
	_spaced[key] = v
	return v


static func label(parent: Node, text: String, font: Font, size: int, color: Color, outline := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func rect(parent: Node, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


static func box_style(bg: Color, border := Color.TRANSPARENT, widths := [0, 0, 0, 0], pad := Vector4(0, 0, 0, 0), radius := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = widths[0]
	s.border_width_top = widths[1]
	s.border_width_right = widths[2]
	s.border_width_bottom = widths[3]
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	return s


## Horizontal bar: a background rect with a fill child scaled by `set_bar`.
static func bar(parent: Node, size: Vector2, bg: Color, fill: Color) -> ColorRect:
	var b := rect(parent, bg)
	b.size = size
	var f := rect(b, fill)
	f.name = "fill"
	f.size = size
	return b


static func set_bar(b: ColorRect, frac: float, vertical := false) -> void:
	var f: ColorRect = b.get_node("fill")
	var v := clampf(frac, 0.0, 1.0)
	if vertical:
		f.size = Vector2(b.size.x, b.size.y * v)
		f.position = Vector2(0, b.size.y * (1.0 - v))
	else:
		f.size = Vector2(b.size.x * v, b.size.y)


static func anchor(c: Control, ax: float, ay: float, x: float, y: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.position = Vector2(x, y)
