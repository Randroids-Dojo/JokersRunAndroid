class_name Screens
extends CanvasLayer
## Title, pause, mission-failed and debrief screens, styled after the web build's compact
## (phone) CSS. Emits actions and setting toggles for the game to apply.

signal action(name: String)
signal toggled(key: String)

const INK := Color("0a0d10")
const RED := Color("d3242b")
const TOGGLES := [
	["assist", "ASSISTED STEERING", false, true],
	["tilt", "TILT STEERING", false, true],
	["haptics", "HAPTICS", false, true],
	["invert_pitch", "INVERT PITCH", false, false],
	["voice", "RADIO VOICE", false, false],
	["music", "MUSIC", false, false],
	["reduced_motion", "REDUCED SHAKE", false, false],
	["mute", "ALL SOUND", true, false],
]

var settings: Settings
var touch_mode := true
var title: Control
var pause: Control
var fail: Control
var debrief: Control
var _toggles: Array = []  # [Btn, key, inverted, touch_only, screen]
var _best: Label
var _best_gap: Control
var _touch_note: Label
var _fail_reason: Label
var _deb_rank: Label
var _deb_stats: GridContainer
var _root: Control
var _unavailable := {}
var _sl := 0.0
var _sr := 0.0


func _ready() -> void:
	layer = 4
	UiKit.init()
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_title()
	_build_pause()
	_build_fail()
	_build_debrief()
	show_screen("")


func layout(w: float, h: float, sl: float, sr: float) -> void:
	_sl = sl
	_sr = sr
	_root.size = Vector2(w, h)
	for s in [title, pause, fail, debrief]:
		(s as Control).size = Vector2(w, h)
	var wrap: Control = title.get_node("wrap")
	wrap.position = Vector2(maxf(w * 0.05, sl + 12.0), 0)
	wrap.size = Vector2(w - wrap.position.x - maxf(w * 0.05, sr + 12.0), h - h * 0.04)
	_fail_reason.custom_minimum_size.x = minf(560.0, w * 0.92) - 40.0
	for p in [pause.get_node("panel"), fail.get_node("panel")]:
		var panel := p as Control
		panel.custom_minimum_size.x = minf(560.0, w * 0.92)
		panel.size = Vector2(minf(560.0, w * 0.92), 0)
		panel.reset_size()
		panel.position = (Vector2(w, h) - panel.size) / 2.0
	var deb: Control = debrief.get_node("panel")
	deb.custom_minimum_size.x = minf(760.0, w * 0.92)
	deb.size = Vector2(minf(760.0, w * 0.92), 0)
	deb.reset_size()
	deb.position = Vector2((w - deb.size.x) / 2.0, h * 0.04)


func show_screen(name: String) -> void:
	title.visible = name == "title"
	pause.visible = name == "pause"
	fail.visible = name == "fail"
	debrief.visible = name == "debrief"
	if name != "":
		sync()
		# Panels size to content; re-centre once their layout settles.
		_relayout.call_deferred()


func _relayout() -> void:
	if _root.size.x > 0.0:
		layout(_root.size.x, _root.size.y, _sl, _sr)


func current() -> String:
	for n in ["title", "pause", "fail", "debrief"]:
		if (get(n) as Control).visible:
			return n
	return ""


func set_touch_mode(on: bool) -> void:
	touch_mode = on
	sync()


func sync() -> void:
	if settings == null:
		return
	for t in _toggles:
		var b: Btn = t[0]
		var key: String = t[1]
		var on := bool(settings.get(key))
		if t[2]:
			on = not on
		b.visible = touch_mode or not t[3]
		b.value = "UNAVAILABLE" if _unavailable.has(key) else ("ON" if on else "OFF")
		b.update_minimum_size()
		b.queue_redraw()
	_touch_note.visible = touch_mode
	_best.text = "BEST SCORE " + MathX.fmt_score(settings.best) if settings.best > 0 else ""
	_best.visible = _best.text != ""
	_best_gap.visible = _best.visible


func mark_unavailable(key: String) -> void:
	_unavailable[key] = true
	sync()


func set_fail_reason(text: String) -> void:
	_fail_reason.text = text


func set_debrief(rank: String, rows: Array) -> void:
	_deb_rank.text = rank
	for c in _deb_stats.get_children():
		c.queue_free()
	for r in rows:
		var total: bool = r.size() > 2
		var k := UiKit.label(_deb_stats, r[0], UiKit.spaced(UiKit.medium, 1.4), 16 if total else 12, Cfg.C_GOLD if total else Color(1, 1, 1, 0.7), false)
		var v := UiKit.label(_deb_stats, r[1], UiKit.bold, 16 if total else 12, Cfg.C_GOLD if total else Color.WHITE, false)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# CSS grid "auto auto auto auto" stretches every column to fill the row.
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if total:
			k.add_theme_constant_override("line_spacing", 0)
			for l in [k, v]:
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = Color(1, 1, 1, 0.25)
				sb.border_width_top = 1
				sb.content_margin_top = 4
				(l as Label).add_theme_stylebox_override("normal", sb)


# ---------------------------------------------------------------- Builders

func _screen(bg: Control) -> Control:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(s)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(bg)
	return s


func _gradient_bg(stops: Array, radial := false, center := Vector2(0.5, 0.5)) -> TextureRect:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 128
	if radial:
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = center
		t.fill_to = Vector2(1.05, 1.05)
	else:
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(1, 0)
	var r := TextureRect.new()
	r.texture = t
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return r


func _toggle_row(parent: Control, screen: String, keys: Array) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(flow)
	for t in TOGGLES:
		if not keys.has(t[0]):
			continue
		var b := Btn.new("toggle", t[1] + ": ")
		b.pressed.connect(func() -> void: toggled.emit(t[0]))
		flow.add_child(b)
		_toggles.append([b, t[0], t[2], t[3], screen])
	return flow


func _build_title() -> void:
	title = _screen(_gradient_bg([[0.0, Color(0.016, 0.031, 0.047, 0.82)], [0.45, Color(0.016, 0.031, 0.047, 0.35)], [0.7, Color(0.016, 0.031, 0.047, 0.1)], [1.0, Color(0.016, 0.031, 0.047, 0.1)]]))
	var wrap := VBoxContainer.new()
	wrap.name = "wrap"
	wrap.alignment = BoxContainer.ALIGNMENT_END
	wrap.add_theme_constant_override("separation", 0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(wrap)
	_kicker(wrap, "MISSION 01")
	var h1 := UiKit.label(wrap, "JOKER'S\nRUN", UiKit.bold_italic, 66, Color("f5f2ea"), false)
	h1.add_theme_constant_override("line_spacing", int(66 * 0.86 - UiKit.bold_italic.get_height(66)))
	h1.add_theme_color_override("font_shadow_color", Color(0.75, 0.157, 0.176, 0.85))
	h1.add_theme_constant_override("shadow_offset_x", 6)
	h1.add_theme_constant_override("shadow_offset_y", 6)
	h1.add_theme_constant_override("shadow_outline_size", 0)
	_spacer(wrap, 6)
	var tag := UiKit.label(wrap, "The fleet is running for neutral water. Enemy scouts have found it.\nDon't let them talk.", UiKit.medium, 13, Color(1, 1, 1, 0.82), false)
	tag.custom_minimum_size.x = 480
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.add_theme_constant_override("line_spacing", 3)
	_spacer(wrap, 12)
	var cta := Btn.new("cta", "LAUNCH")
	cta.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cta.pressed.connect(func() -> void: action.emit("launch"))
	wrap.add_child(cta)
	_spacer(wrap, 10)
	_touch_note = UiKit.label(wrap, "Left thumb flies: touch and drag anywhere on the left. Right thumb fights. Tap an enemy to target it.", UiKit.medium, 12, Color(1, 1, 1, 0.75), false)
	_touch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_touch_note.custom_minimum_size.x = 520
	_touch_note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_spacer(wrap, 10)
	var flow := _toggle_row(wrap, "title", ["assist", "tilt", "invert_pitch", "voice", "music", "reduced_motion"])
	_best_gap = _spacer(wrap, 8)
	_best = UiKit.label(wrap, "", UiKit.spaced(UiKit.medium, 2.2), 11, Color(1, 1, 1, 0.6), false)


## "♦ MISSION 01" kicker. The suit is drawn as an image: the UI font has no ♦ and Android's
## font fallback does not always supply one.
func _kicker(parent: Control, text: String) -> void:
	var k := RichTextLabel.new()
	k.bbcode_enabled = true
	k.fit_content = true
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	k.scroll_active = false
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k.add_theme_font_override("normal_font", UiKit.spaced(UiKit.semibold, 4.4))
	k.add_theme_font_size_override("normal_font_size", 11)
	k.add_theme_color_override("default_color", Color(1, 1, 1, 0.75))
	k.add_image(_suit_texture(), 7, 9, Color.WHITE, INLINE_ALIGNMENT_CENTER)
	k.append_text("  " + text)
	parent.add_child(k)


static var _suit: ImageTexture


static func _suit_texture() -> ImageTexture:
	if _suit:
		return _suit
	var w := 28
	var h := 36
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var red := Color("d3242b")
	for y in h:
		for x in w:
			# Signed distance to the diamond edge, for a soft anti-aliased rim.
			var d := absf((x + 0.5) / w * 2.0 - 1.0) + absf((y + 0.5) / h * 2.0 - 1.0)
			var a := clampf((1.0 - d) * 14.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(red.r, red.g, red.b, a))
	_suit = ImageTexture.create_from_image(img)
	return _suit


func _spacer(parent: Control, h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)
	return s


func _panel(parent: Control, accent: Color, min_w: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "panel"
	panel.add_theme_stylebox_override("panel", UiKit.box_style(Color(0.024, 0.04, 0.055, 0.92), accent, [0, 3, 0, 0], Vector4(20, 14, 20, 14)))
	panel.custom_minimum_size.x = min_w
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)
	return v


func _h2(parent: Control, text: String, col: Color, size := 26) -> Label:
	var l := UiKit.label(parent, text, UiKit.spaced(UiKit.bold_italic, size * 0.08), size, col, false)
	_spacer(parent, 8)
	return l


func _menu(parent: Control, items: Array, columns := 1) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for it in items:
		var b := Btn.new("menu", it[1])
		b.primary = it.size() > 2 and it[2]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: action.emit(it[0]))
		grid.add_child(b)


func _build_pause() -> void:
	pause = _screen(_dim())
	var v := _panel(pause, Cfg.C_GOLD, 380)
	_h2(v, "PAUSED", Color.WHITE)
	_menu(v, [["resume", "RESUME"], ["retry", "RESTART CHECKPOINT"], ["restart", "RESTART MISSION"], ["title", "QUIT TO TITLE"]])
	_spacer(v, 10)
	_toggle_row(v, "pause", ["assist", "tilt", "haptics", "invert_pitch", "voice", "music", "reduced_motion", "mute"])


func _dim() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.008, 0.02, 0.03, 0.6)
	return r


func _build_fail() -> void:
	fail = _screen(_dim())
	var v := _panel(fail, Cfg.C_HOSTILE, 380)
	_h2(v, "MISSION FAILED", Cfg.C_HOSTILE)
	_fail_reason = UiKit.label(v, "", UiKit.spaced(UiKit.medium, 1.4), 16, Color(1, 1, 1, 0.8), false)
	_fail_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spacer(v, 14)
	_menu(v, [["retry", "RETRY FROM CHECKPOINT", true], ["restart", "RESTART MISSION"]])


func _build_debrief() -> void:
	debrief = _screen(_gradient_bg([[0.0, Color(0.04, 0.07, 0.1, 0.85)], [1.0, Color(0, 0, 0, 0.95)]], true, Vector2(0.3, 0.4)))
	var outer := VBoxContainer.new()
	outer.name = "panel"
	outer.add_theme_constant_override("separation", 0)
	debrief.add_child(outer)
	_kicker(outer, "MISSION 01 · JOKER'S RUN")
	_spacer(outer, 8)
	_h2(outer, "MISSION COMPLETE", Cfg.C_GOLD, 30)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 16)
	outer.add_child(grid)
	var rank := PanelContainer.new()
	rank.custom_minimum_size = Vector2(96, 0)
	rank.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rank.add_theme_stylebox_override("panel", UiKit.box_style(Color(0, 0, 0, 0), Cfg.C_GOLD, [2, 2, 2, 2], Vector4(0, 10, 0, 4)))
	grid.add_child(rank)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", -4)
	rank.add_child(rv)
	var rl := UiKit.label(rv, "RANK", UiKit.spaced(UiKit.semibold, 5.2), 13, Cfg.C_GOLD, false)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deb_rank = UiKit.label(rv, "A", UiKit.bold_italic, 64, Color.WHITE, false)
	_deb_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deb_rank.add_theme_color_override("font_shadow_color", Color(0.75, 0.157, 0.176, 0.85))
	_deb_rank.add_theme_constant_override("shadow_offset_x", 5)
	_deb_rank.add_theme_constant_override("shadow_offset_y", 5)
	_deb_stats = GridContainer.new()
	_deb_stats.columns = 4
	_deb_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deb_stats.add_theme_constant_override("h_separation", 14)
	_deb_stats.add_theme_constant_override("v_separation", 2)
	grid.add_child(_deb_stats)
	_spacer(outer, 12)
	var nxt := PanelContainer.new()
	nxt.add_theme_stylebox_override("panel", UiKit.box_style(Color(1, 1, 1, 0.05), RED, [3, 0, 0, 0], Vector4(12, 8, 12, 8)))
	outer.add_child(nxt)
	var nl := RichTextLabel.new()
	nl.bbcode_enabled = true
	nl.fit_content = true
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.scroll_active = false
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.add_theme_font_override("normal_font", UiKit.spaced(UiKit.medium, 3.9))
	nl.add_theme_font_override("italics_font", UiKit.spaced(UiKit.bold_italic, 4.8))
	nl.add_theme_font_size_override("normal_font_size", 13)
	nl.add_theme_font_size_override("italics_font_size", 16)
	nl.add_theme_color_override("default_color", Color(1, 1, 1, 0.7))
	nl.text = "NEXT MISSION   [i][color=#ffffff]BREAKOUT[/color][/i]    [font_size=11][color=#ffffff66]in development[/color][/font_size]"
	nxt.add_child(nl)
	_spacer(outer, 10)
	_menu(outer, [["restart", "FLY AGAIN", true], ["title", "TITLE"]], 2)


# ---------------------------------------------------------------- Button

## A flat, touch-friendly button drawn in the web build's styles: "cta" (gold slanted
## launch button), "menu" (full-width row) and "toggle" (small chip with a gold value).
class Btn:
	extends Control
	signal pressed

	var kind := "menu"
	var text := ""
	var value := ""
	var primary := false
	var _down := false
	var _hover := false
	var _font: Font
	var _vfont: Font
	var _size := 13
	var _pad := Vector2(12, 8)

	func _init(p_kind: String, p_text: String) -> void:
		kind = p_kind
		text = p_text
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		match kind:
			"cta":
				_font = UiKit.spaced(UiKit.bold, 5.1)
				_size = 17
				_pad = Vector2(22, 10)
			"toggle":
				_font = UiKit.spaced(UiKit.medium, 1.4)
				_vfont = UiKit.spaced(UiKit.bold, 1.4)
				_size = 10
				_pad = Vector2(9, 6)
			_:
				_font = UiKit.spaced(UiKit.semibold, 2.6)
				_size = 13
				_pad = Vector2(12, 8)
		mouse_entered.connect(func() -> void:
			_hover = not DisplayServer.is_touchscreen_available()
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			_down = false
			queue_redraw())

	func _get_minimum_size() -> Vector2:
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x
		if _vfont and value != "":
			w += _vfont.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x
		var h := _font.get_height(_size)
		return Vector2(w + _pad.x * 2.0 + 2.0, h + _pad.y * 2.0 + 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := event as InputEventMouseButton
			if mb.pressed:
				_down = true
				queue_redraw()
			elif _down:
				_down = false
				queue_redraw()
				if Rect2(Vector2.ZERO, size).has_point(mb.position):
					pressed.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hi := _hover or _down
		var fg := Color.WHITE
		match kind:
			"cta":
				var bg := Color.WHITE if hi else Cfg.C_GOLD
				var s := 12.0
				draw_colored_polygon(PackedVector2Array([Vector2(s, 0), Vector2(size.x, 0), Vector2(size.x - s, size.y), Vector2(0, size.y)]), bg)
				fg = INK
			"toggle":
				draw_rect(r, Color(1, 1, 1, 0.14 if _down else 0.06))
				draw_rect(r.grow(-0.5), Cfg.C_GOLD if hi else Color(1, 1, 1, 0.25), false, 1.0)
				fg = Color(1, 1, 1, 0.8)
			_:
				var on := primary or hi
				draw_rect(r, Cfg.C_GOLD if on else Color(1, 1, 1, 0.05))
				draw_rect(r.grow(-0.5), Cfg.C_GOLD if on else Color(1, 1, 1, 0.18), false, 1.0)
				fg = INK if on else Color.WHITE
		var base_y := (size.y + _font.get_ascent(_size) - _font.get_descent(_size)) / 2.0
		if kind == "menu":
			draw_string(_font, Vector2(_pad.x + 1.0, base_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, fg)
		else:
			var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x
			var vw := _vfont.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x if _vfont and value != "" else 0.0
			var x0 := (size.x - tw - vw) / 2.0
			draw_string(_font, Vector2(x0, base_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, fg)
			if vw > 0.0:
				draw_string(_vfont, Vector2(x0 + tw, base_y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, Cfg.C_GOLD)
