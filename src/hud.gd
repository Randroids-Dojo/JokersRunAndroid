class_name Hud
extends CanvasLayer
## HUD widgets laid out like the web build's compact phone layout (844x390 base units):
## score/combo, objective + timer, hull, radar, scout uploads, gauges, boss bar, prompts,
## popups, radio, banners, countdown, letterbox, fades and the next-mission card.

## Plays a radio line as it is shown; returns its spoken length in seconds (0 if silent).
var on_radio: Callable

var overlay: HudOverlay
var radar: HudRadar
var W := 844.0
var H := 390.0
var safe_l := 0.0
var safe_r := 0.0

var _root: Control
var _score_lbl: Label
var _score_val: Label
var _hot: Label
var _combo_text: Label
var _combo_bar: ColorRect
var _objective: Label
var _timer_lbl: Label
var _timer_val: Label
var _subtimer: Label
var _hull_lbl: Label
var _hull_bar: ColorRect
var _hull_num: Label
var _scout_rows: Array = []
var _boss: Control
var _boss_name: Label
var _boss_stage: Label
var _boss_hp: ColorRect
var _boss_press_lbl: Label
var _boss_press: ColorRect
var _boss_status: Label
var _spd_box: PanelContainer
var _spd: Label
var _alt_box: PanelContainer
var _alt: Label
var _gauge_lbls: Array[Label] = []
var _pullup: Label
var _prompt: PanelContainer
var _prompt_text: RichTextLabel
var _popups: VBoxContainer
var _radio: PanelContainer
var _radio_who: Label
var _radio_text: Label
var _radio_style: StyleBoxFlat
var _banner: Control
var _banner_main: Label
var _banner_sub: Label
var _banner_stripes: ColorRect
var _countdown: Label
var _area_warn: Label
var _letter_top: ColorRect
var _letter_bot: ColorRect
var fade: ColorRect
var cloud_fog: ColorRect
var vignette: ColorRect
var _card: Control
var top: CanvasLayer

var visible_hud := false
var cinematic := false
var objective_text := ""
var radar_range := 4500.0
var _radar_target := 4500.0
var ping_t := 99.0
var wing_order_shown := ""
## The touch order chips are on screen (bottom centre); the radio caption steps up over them.
var orders_up := false
var _banner_q: Array = []
var _banner_t := 0.0
var _banner_active := false
var _radio_q: Array = []
var _radio_cur: Array = []
var _radio_t := 0.0
var _radio_dur := 0.0
var _last_score := -1.0
var _last_combo := -1
var _uploads := false
var _cache := {}


func _ready() -> void:
	UiKit.init()
	layer = 1
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	cloud_fog = UiKit.rect(_root, Color(0.9, 0.93, 0.95, 0.0))
	vignette = UiKit.rect(_root, Color(1, 1, 1, 1))
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vm
	vignette.modulate.a = 0.0

	overlay = HudOverlay.new()
	overlay.hud = self
	_root.add_child(overlay)
	radar = HudRadar.new()
	radar.hud = self
	_root.add_child(radar)

	var sb := UiKit.semibold
	_score_lbl = UiKit.label(_root, "SCORE", UiKit.spaced(sb, 1.6), 9, Cfg.C_HUD_DIM)
	_score_val = UiKit.label(_root, "0", UiKit.bold, 22, Cfg.C_HUD)
	_hot = UiKit.label(_root, "", UiKit.spaced(sb, 1.3), 11, Cfg.C_GOLD)
	_combo_text = UiKit.label(_root, "", UiKit.bold_italic, 15, Cfg.C_COMBO)
	_combo_bar = UiKit.bar(_root, Vector2(140, 6), Color(0.651, 1, 0.816, 0.22), Cfg.C_COMBO)

	_objective = UiKit.label(_root, "", UiKit.spaced(sb, 1.8), 11, Cfg.C_HUD)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_lbl = UiKit.label(_root, "", UiKit.spaced(sb, 2.2), 9, Cfg.C_HUD_DIM)
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_val = UiKit.label(_root, "", UiKit.bold, 26, Cfg.C_HUD)
	_timer_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtimer = UiKit.label(_root, "", UiKit.spaced(sb, 1.6), 10, Cfg.C_HUD_DIM)
	_subtimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_hull_lbl = UiKit.label(_root, "HULL", UiKit.spaced(sb, 2.0), 11, Cfg.C_HUD_DIM)
	_hull_bar = UiKit.bar(_root, Vector2(56, 5), Color(0.651, 1, 0.816, 0.22), Cfg.C_HUD)
	_hull_num = UiKit.label(_root, "100", UiKit.bold, 11, Cfg.C_HUD)

	for i in 3:
		var name_l := UiKit.label(_root, "", UiKit.spaced(sb, 1.0), 10, Cfg.C_TARGET)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var b := UiKit.bar(_root, Vector2(64, 4), Color(1, 0.62, 0.11, 0.2), Cfg.C_TARGET)
		var st := UiKit.label(_root, "", UiKit.bold, 10, Cfg.C_TARGET)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_scout_rows.append([name_l, b, st])

	_boss = Control.new()
	_boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boss)
	_boss_name = UiKit.label(_boss, "ACE", UiKit.spaced(UiKit.bold, 3.0), 10, Cfg.C_ACE)
	_boss_stage = UiKit.label(_boss, "STAGE 1", UiKit.spaced(UiKit.bold, 3.0), 10, Cfg.C_ACE)
	_boss_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boss_hp = UiKit.bar(_boss, Vector2(250, 8), Color(1, 0.24, 0.39, 0.2), Cfg.C_ACE)
	_boss_press_lbl = UiKit.label(_boss, "PRESSURE", UiKit.spaced(sb, 2.4), 9, Color("ffc35b"))
	_boss_press = UiKit.bar(_boss, Vector2(180, 4), Color(1, 0.76, 0.36, 0.2), Color("ffc35b"))
	_boss_status = UiKit.label(_boss, "", UiKit.spaced(UiKit.bold, 2.4), 10, Cfg.C_ACE)
	_boss_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss.visible = false

	var gauge_style := UiKit.box_style(Color(0, 0, 0, 0), Cfg.C_HUD_DIM, [1, 1, 1, 1], Vector4(6, 0, 6, 0))
	_spd_box = PanelContainer.new()
	_spd_box.add_theme_stylebox_override("panel", gauge_style)
	_spd_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_spd_box)
	_spd = UiKit.label(_spd_box, "0", UiKit.bold, 17, Cfg.C_HUD)
	_spd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spd.custom_minimum_size = Vector2(46, 0)
	_alt_box = PanelContainer.new()
	_alt_box.add_theme_stylebox_override("panel", gauge_style)
	_alt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_alt_box)
	_alt = UiKit.label(_alt_box, "0", UiKit.bold, 17, Cfg.C_HUD)
	_alt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alt.custom_minimum_size = Vector2(46, 0)
	for t in ["SPD", "KM/H", "ALT", "M"]:
		var l := UiKit.label(_root, t, UiKit.spaced(sb, 2.0), 10 if t.length() < 4 else 9, Cfg.C_HUD_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gauge_lbls.append(l)
	_pullup = UiKit.label(_root, "PULL UP", UiKit.spaced(UiKit.bold, 2.4), 12, Cfg.C_HOSTILE)
	_pullup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pullup.visible = false

	_prompt = PanelContainer.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_stylebox_override("panel", UiKit.box_style(Color(0.024, 0.047, 0.04, 0.55), Cfg.C_GOLD, [3, 0, 0, 0], Vector4(11, 7, 11, 7)))
	_root.add_child(_prompt)
	_prompt_text = RichTextLabel.new()
	_prompt_text.bbcode_enabled = true
	_prompt_text.fit_content = true
	_prompt_text.scroll_active = false
	_prompt_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_text.add_theme_font_override("normal_font", UiKit.medium)
	_prompt_text.add_theme_font_override("bold_font", UiKit.bold)
	_prompt_text.add_theme_font_override("italics_font", UiKit.bold_italic)
	_prompt_text.add_theme_font_override("bold_italics_font", UiKit.bold_italic)
	_prompt_text.add_theme_font_size_override("normal_font_size", 12)
	_prompt_text.add_theme_font_size_override("bold_font_size", 12)
	_prompt_text.add_theme_font_size_override("italics_font_size", 17)
	_prompt_text.add_theme_color_override("default_color", Color.WHITE)
	_prompt.add_child(_prompt_text)
	_prompt.visible = false

	_popups = VBoxContainer.new()
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popups.add_theme_constant_override("separation", 0)
	_root.add_child(_popups)

	_radio_style = UiKit.box_style(Color(0.016, 0.04, 0.03, 0.7), Cfg.C_HUD, [3, 0, 0, 0], Vector4(10, 6, 10, 7))
	_radio = PanelContainer.new()
	_radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio.add_theme_stylebox_override("panel", _radio_style)
	_root.add_child(_radio)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	_radio.add_child(rv)
	_radio_who = UiKit.label(rv, "", UiKit.spaced(UiKit.bold, 2.7), 9, Cfg.C_HUD, false)
	_radio_text = UiKit.label(rv, "", UiKit.medium, 13, Color("f2f6f4"), false)
	_radio_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio.visible = false
	_radio.resized.connect(_place_radio)

	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	_banner_stripes = UiKit.rect(_banner, Color(1, 1, 1, 1))
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/stripes.gdshader")
	_banner_stripes.material = sm
	_banner_main = UiKit.label(_banner, "", UiKit.spaced(UiKit.bold_italic, 2.8), 35, Color.WHITE, false)
	_banner_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_main.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_sub = UiKit.label(_banner, "", UiKit.spaced(UiKit.semibold, 3.3), 11, Color.WHITE, false)
	_banner_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_banner_sub.add_theme_constant_override("shadow_offset_x", 0)
	_banner_sub.add_theme_constant_override("shadow_offset_y", 1)
	_banner_sub.add_theme_constant_override("shadow_outline_size", 2)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.visible = false

	_countdown = UiKit.label(_root, "", UiKit.bold_italic, 76, Cfg.C_HOSTILE)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_area_warn = UiKit.label(_root, "RETURN TO COMBAT AREA", UiKit.spaced(UiKit.bold, 3.0), 12, Cfg.C_GOLD)
	_area_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_area_warn.visible = false

	# Letterbox bars sit above the HUD but under the touch controls (layer 3), so the pause
	# button stays reachable in cinematics, and under the menus (layer 4).
	var bars := CanvasLayer.new()
	bars.layer = 2
	add_child(bars)
	_letter_top = UiKit.rect(bars, Color.BLACK)
	_letter_bot = UiKit.rect(bars, Color.BLACK)
	# The next-mission card and the fade sit above the menus (layer 3), like the web DOM order.
	top = CanvasLayer.new()
	top.layer = 10
	add_child(top)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_card)
	var cbg := UiKit.rect(_card, Color(0, 0, 0, 0.82))
	cbg.name = "bg"
	var ck := UiKit.label(_card, "NEXT MISSION", UiKit.spaced(UiKit.semibold, 9.0), 15, Color(1, 1, 1, 0.7), false)
	ck.name = "kicker"
	ck.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ct := UiKit.label(_card, "BREAKOUT", UiKit.spaced(UiKit.bold_italic, 8.0), 64, Color.WHITE)
	ct.name = "title"
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ct.add_theme_color_override("font_shadow_color", Color(1, 0.24, 0.16, 0.5))
	ct.add_theme_constant_override("shadow_offset_y", 0)
	ct.add_theme_constant_override("shadow_outline_size", 18)
	_card.visible = false
	fade = UiKit.rect(top, Color(0, 0, 0, 1))
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_visible_hud(false)


func layout(w: float, h: float, sl: float, sr: float) -> void:
	W = w
	H = h
	safe_l = sl
	safe_r = sr
	for r in [cloud_fog, vignette, overlay, fade]:
		(r as Control).position = Vector2.ZERO
		(r as Control).size = Vector2(w, h)
	_score_lbl.position = Vector2(sl + 62, 8)
	_score_val.position = Vector2(sl + 62, 18)
	_hot.position = Vector2(sl + 62, 44)
	_combo_text.position = Vector2(sl + 62, 56)
	_combo_bar.position = Vector2(sl + 62, 78)
	_objective.position = Vector2(w * 0.27, 33)
	_objective.size = Vector2(w * 0.46, 14)
	_timer_lbl.position = Vector2(w * 0.3, 48)
	_timer_lbl.size = Vector2(w * 0.4, 10)
	_timer_val.position = Vector2(w * 0.3, 55)
	_timer_val.size = Vector2(w * 0.4, 30)
	_subtimer.position = Vector2(w * 0.25, 86)
	_subtimer.size = Vector2(w * 0.5, 12)
	var hx := w - sr - 136.0 - 128.0
	_hull_lbl.position = Vector2(hx, 9)
	_hull_bar.position = Vector2(hx + 43, 16)
	_hull_num.position = Vector2(hx + 104, 9)
	for i in 3:
		var row: Array = _scout_rows[i]
		var y := 130.0 + i * 15.0
		var right := w - sr - 12.0
		(row[2] as Label).position = Vector2(right - 34, y)
		(row[2] as Label).size = Vector2(34, 12)
		(row[1] as ColorRect).position = Vector2(right - 34 - 6 - 64, y + 5)
		(row[0] as Label).position = Vector2(right - 34 - 6 - 64 - 6 - 90, y)
		(row[0] as Label).size = Vector2(90, 12)
	var bw := minf(250.0, w * 0.3)
	_boss.position = Vector2((w - bw) / 2.0, 98)
	_boss_name.position = Vector2(0, 0)
	_boss_stage.position = Vector2(bw - 120, 0)
	_boss_stage.size = Vector2(120, 12)
	_boss_hp.position = Vector2(0, 15)
	_boss_hp.size = Vector2(bw, 8)
	(_boss_hp.get_node("fill") as ColorRect).size = Vector2(bw, 8)
	_boss_press_lbl.position = Vector2(0, 26)
	_boss_press.position = Vector2(70, 30)
	_boss_press.size = Vector2(bw - 70, 4)
	_boss_status.position = Vector2(0, 38)
	_boss_status.size = Vector2(bw, 12)
	var gy := h * 0.4
	var lx := w / 2.0 - 196.0
	var rx := w / 2.0 + 196.0 - 60.0
	_gauge_lbls[0].position = Vector2(lx, gy - 26)
	_gauge_lbls[0].size = Vector2(60, 12)
	_spd_box.position = Vector2(lx, gy - 12)
	_spd_box.size = Vector2(60, 24)
	_gauge_lbls[1].position = Vector2(lx, gy + 14)
	_gauge_lbls[1].size = Vector2(60, 12)
	_gauge_lbls[2].position = Vector2(rx, gy - 26)
	_gauge_lbls[2].size = Vector2(60, 12)
	_alt_box.position = Vector2(rx, gy - 12)
	_alt_box.size = Vector2(60, 24)
	_gauge_lbls[3].position = Vector2(rx, gy + 14)
	_gauge_lbls[3].size = Vector2(60, 12)
	_pullup.position = Vector2(rx - 20, gy + 30)
	_pullup.size = Vector2(100, 14)
	# Narrower when a camera cutout pushes the column right, so it ends before the speed gauge.
	var pw := minf(minf(214.0, w * 0.27), w / 2.0 - 196.0 - 8.0 - (sl + 12.0))
	_prompt.position = Vector2(sl + 12, 104)
	_prompt.custom_minimum_size = Vector2(pw, 0)
	_prompt.size = Vector2(pw, 0)
	_prompt_text.custom_minimum_size = Vector2(pw - 22.0, 0)
	# Left of the crosshair, under the speed gauge: clear of the status column and the buttons.
	_popups.size = Vector2(170, 0)
	_popups.position = Vector2(w / 2.0 - 30.0 - 170.0, h * 0.475)
	# Ends before the button cluster, which a right-hand camera cutout pushes inward.
	var rw := minf(w * 0.33, (w - sr - 306.0) - w * 0.3)
	_radio.position = Vector2(w * 0.3, 0)
	_radio.custom_minimum_size = Vector2(rw, 0)
	_radio.size.x = rw
	_radio_text.custom_minimum_size = Vector2(rw - 23.0, 0)
	# Just under the objective; the timer and ace panel step aside while a banner shows.
	_banner.position = Vector2(0, 52)
	_banner.size = Vector2(w, 67)
	_banner_stripes.position = Vector2(w * 0.26, 0)
	_banner_stripes.size = Vector2(w * 0.48, 67)
	(_banner_stripes.material as ShaderMaterial).set_shader_parameter("rect_size", Vector2(w * 0.48, 67))
	_countdown.position = Vector2(0, h * 0.52 - 50.0)
	_countdown.size = Vector2(w, 100)
	_area_warn.position = Vector2(0, h * 0.3)
	_area_warn.size = Vector2(w, 16)
	_card.size = Vector2(w, h)
	(_card.get_node("bg") as ColorRect).size = Vector2(w, h)
	(_card.get_node("kicker") as Label).position = Vector2(0, h * 0.5 - 60.0)
	(_card.get_node("kicker") as Label).size = Vector2(w, 20)
	(_card.get_node("title") as Label).position = Vector2(0, h * 0.5 - 40.0)
	(_card.get_node("title") as Label).size = Vector2(w, 80)
	radar.position = Vector2(w - sr - 10.0 - 116.0, 8)
	radar.size = Vector2(116, 116)
	_letter_top.size = Vector2(w, _letter_top.size.y)
	_letter_bot.size = Vector2(w, _letter_bot.size.y)
	_letter_bot.position = Vector2(0, h - _letter_bot.size.y)
	_place_radio()


func _place_radio() -> void:
	# Above the bottom letterbox bar in cinematics, above the order chips in play.
	var lift := 44.0 if orders_up else 6.0
	if _letter_bot.size.y > 1.0:
		lift = maxf(lift, _letter_bot.size.y + 8.0)
	_radio.position = Vector2(W * 0.3, H - lift - _radio.size.y)


func set_visible_hud(on: bool) -> void:
	visible_hud = on
	_root.visible = on


func set_cinematic(on: bool) -> void:
	cinematic = on
	var target := H * 0.09 if on else 0.0
	var tw := _tw().set_parallel(true)
	tw.tween_property(_letter_top, "size:y", target, 0.6)
	tw.tween_property(_letter_bot, "size:y", target, 0.6)
	tw.tween_property(_letter_bot, "position:y", H - target, 0.6)
	for c in [_score_lbl, _score_val, _hot, _combo_text, _combo_bar, _objective, _timer_lbl, _timer_val, _subtimer, _hull_lbl, _hull_bar, _hull_num, _boss, _spd_box, _alt_box, _prompt, radar, overlay]:
		(c as CanvasItem).modulate.a = 0.0 if on else 1.0
	for r in _scout_rows:
		for c in r:
			(c as CanvasItem).modulate.a = 0.0 if on else 1.0
	for l in _gauge_lbls:
		l.modulate.a = 0.0 if on else 1.0


func objective(text: String, flash := true) -> void:
	objective_text = text
	_objective.text = text
	_place_subtimer()
	if flash and text != "":
		var tw := _tw()
		for i in 3:
			tw.tween_property(_objective, "modulate", Color(2, 2, 2, 1), 0.3)
			tw.tween_property(_objective, "modulate", Color.WHITE, 0.3)


func timer(lbl, seconds := 0.0, tenths := false, count_up := false) -> void:
	if lbl == null:
		_timer_lbl.visible = false
		_timer_val.visible = false
		_place_subtimer()
		return
	if not _timer_val.visible:
		_timer_lbl.visible = true
		_timer_val.visible = true
		_place_subtimer()
	_timer_lbl.text = lbl
	_timer_val.text = MathX.fmt_clock(seconds, tenths)
	var col := Cfg.C_HUD
	if not count_up:
		if seconds <= 10.0:
			col = Cfg.C_HOSTILE if fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25 else Color(1, 0.3, 0.24, 0.35)
		elif seconds <= 30.0:
			col = Cfg.C_GOLD
	_timer_val.add_theme_color_override("font_color", col)


func subtimer(text: String) -> void:
	_subtimer.text = text
	_place_subtimer()


func _place_subtimer() -> void:
	_subtimer.position.y = 86.0 if _timer_val.visible else 36.0 + (14.0 if _objective.text != "" else 0.0) + 4.0


func phase(_text: String) -> void:
	pass


func banner(main: String, sub := "", style := "info", dur := 2.4) -> void:
	_banner_q.append([main, sub, style, dur])


func banner_now(main: String, sub := "", style := "info", dur := 2.4) -> void:
	_banner_q.clear()
	_banner_t = 0.0
	_banner_active = false
	_banner_q.append([main, sub, style, dur])


func clear_banners() -> void:
	_banner_q.clear()
	_banner_t = 0.0
	_banner_active = false
	_banner.visible = false


func _show_banner(b: Array) -> void:
	var style: String = b[2]
	_banner_main.text = b[0]
	_banner_sub.text = b[1]
	_banner_sub.visible = b[1] != ""
	_banner_stripes.visible = style == "warning"
	var main_col := Color.WHITE
	var sub_col := Cfg.C_HUD
	var size := 28
	match style:
		"gold":
			main_col = Cfg.C_GOLD
			sub_col = Color.WHITE
		"combo":
			main_col = Cfg.C_COMBO
		"red":
			main_col = Color("ff3b4e")
			sub_col = Color("ffd2d6")
		"warning":
			sub_col = Color.WHITE
	_banner_main.add_theme_color_override("font_color", main_col)
	_banner_main.add_theme_font_size_override("font_size", size)
	_banner_sub.add_theme_color_override("font_color", sub_col)
	# Web text shadows: a dark drop for gold, soft glows elsewhere (approximated by a halo).
	var sh := Color(0, 0, 0, 0.35)
	var sh_off := Vector2(0, 2)
	var sh_size := 0
	match style:
		"gold":
			sh = Color(0.35, 0.2, 0.0, 0.6)
			sh_off = Vector2(0, 3)
		"warning":
			sh = Color(1, 0, 0, 0.45)
			sh_off = Vector2.ZERO
			sh_size = 8
		"red":
			sh = Color(1, 0.12, 0.24, 0.35)
			sh_off = Vector2.ZERO
			sh_size = 8
		"combo":
			sh = Color(0.24, 0.86, 1, 0.3)
			sh_off = Vector2.ZERO
			sh_size = 8
	_banner_main.add_theme_color_override("font_shadow_color", sh)
	_banner_main.add_theme_constant_override("shadow_offset_x", int(sh_off.x))
	_banner_main.add_theme_constant_override("shadow_offset_y", int(sh_off.y))
	_banner_main.add_theme_constant_override("shadow_outline_size", sh_size)
	# Fit between the score column (and its combo bar) and the radar, whatever the safe insets.
	var half := minf(W / 2.0 - (safe_l + 62.0 + 140.0 + 8.0), (W - safe_r - 10.0 - 116.0 - 8.0) - W / 2.0)
	var main_font := _banner_main.get_theme_font("font")
	var text_w := main_font.get_string_size(_banner_main.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if text_w > half * 2.0:
		size = maxi(18, int(floor(size * half * 2.0 / text_w)))
		_banner_main.add_theme_font_size_override("font_size", size)
	var band_w := minf(W * 0.48, half * 2.0)
	_banner_stripes.position.x = (W - band_w) / 2.0
	_banner_stripes.size.x = band_w
	(_banner_stripes.material as ShaderMaterial).set_shader_parameter("rect_size", _banner_stripes.size)
	var warn := style == "warning"
	var top := 6.0 if warn else 0.0
	_banner_main.position = Vector2(0, top)
	_banner_main.size = Vector2(W, 30)
	var sub_sb := StyleBoxFlat.new()
	sub_sb.bg_color = Color(0, 0, 0, 0.6) if warn else Color(0, 0, 0, 0)
	sub_sb.content_margin_left = 14 if warn else 0
	sub_sb.content_margin_right = 14 if warn else 0
	sub_sb.content_margin_top = 3 if warn else 0
	sub_sb.content_margin_bottom = 3 if warn else 0
	_banner_sub.add_theme_stylebox_override("normal", sub_sb)
	_banner_sub.size = Vector2.ZERO
	_banner_sub.reset_size()
	_banner_sub.position = Vector2((W - _banner_sub.size.x) / 2.0, top + 30.0 + 4.0)
	_banner.visible = true
	_banner.pivot_offset = Vector2(W / 2.0, 0)  # pop in downward, clear of the objective
	_banner.scale = Vector2(1.5, 1.5)
	_banner.modulate.a = 0.0
	var tw := _tw().set_parallel(true)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_active = true
	_banner_t = b[3]


func popup(lines: Array) -> void:
	var i := 0
	for l in lines:
		var kind: String = l.get("kind", "bonus")
		var col := Cfg.C_HUD
		var size := 11
		var font: Font = UiKit.spaced(UiKit.bold, 1.0)
		match kind:
			"kill":
				col = Color.WHITE
			"combo":
				col = Cfg.C_COMBO
				size = 14
				font = UiKit.bold_italic
			"gold":
				col = Cfg.C_GOLD
				size = 13
			"time":
				col = Cfg.C_COMBO
			"bad":
				col = Cfg.C_HOSTILE
		var text: String = l.text
		if l.has("points"):
			text += "  +" + MathX.fmt_score(l.points)
		var lab := UiKit.label(_popups, text, font, size, col)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long lines wrap, clear of the prompt
		lab.modulate.a = 0.0
		var tw := lab.create_tween().set_ignore_time_scale(true)
		tw.tween_interval(i * 0.07)
		tw.tween_property(lab, "modulate:a", 1.0, 0.2)
		tw.tween_interval(2.0)
		tw.tween_property(lab, "modulate:a", 0.0, 0.5)
		tw.tween_callback(lab.queue_free)
		i += 1
	while _popups.get_child_count() > 4:
		var c := _popups.get_child(0)
		_popups.remove_child(c)
		c.queue_free()


func radio(who: String, text: String, priority := false) -> void:
	if priority:
		_radio_q.clear()
		_radio_t = _radio_dur
	_radio_q.append([who, text])


func clear_radio() -> void:
	_radio_q.clear()
	_radio_cur = []
	_radio.visible = false


func radio_busy() -> bool:
	return not _radio_cur.is_empty() or not _radio_q.is_empty()


## BBCode prompt, or "" to hide.
func prompt(bb: String) -> void:
	if bb == "":
		_prompt.visible = false
		return
	_prompt.visible = true
	if _prompt_text.text != bb:
		_prompt_text.text = bb
		_prompt.size.y = 0.0


func countdown(n: int) -> void:
	if n <= 0:
		_countdown.text = ""
		return
	var s := str(n)
	if _countdown.text != s:
		_countdown.text = s
		_countdown.pivot_offset = Vector2(W / 2.0, 50)
		_countdown.scale = Vector2(1.6, 1.6)
		_countdown.modulate.a = 0.4
		var tw := _tw().set_parallel(true)
		tw.tween_property(_countdown, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT)
		tw.tween_property(_countdown, "modulate:a", 1.0, 0.6)


func boss(info) -> void:
	if info == null:
		_boss.visible = false
		return
	_boss.visible = true
	UiKit.set_bar(_boss_hp, info.hp)
	UiKit.set_bar(_boss_press, info.pressure)
	_boss_stage.text = "ENRAGED" if info.stage == 2 else "STAGE 1"
	_boss_status.text = info.status
	if info.low:
		_boss_status.add_theme_color_override("font_color", Cfg.C_GOLD if fmod(Time.get_ticks_msec() / 1000.0, 0.4) < 0.2 else Color(1, 0.82, 0.35, 0.3))
	else:
		_boss_status.add_theme_color_override("font_color", Cfg.C_ACE)


func scouts(rows) -> void:
	for i in 3:
		var r: Array = _scout_rows[i]
		var show_row: bool = rows != null and i < rows.size() and _uploads
		for c in r:
			(c as CanvasItem).visible = show_row
		if not show_row:
			continue
		var d: Dictionary = rows[i]
		var st: String = d.state
		var col := Cfg.C_TARGET
		var status := "%d%%" % int(round(d.upload * 100.0))
		if st == "down":
			col = Cfg.C_HUD_DIM
			status = "DOWN"
		elif st == "dark":
			col = Color(1, 0.62, 0.11, 0.5)
			status = "LOST"
		elif st == "paused":
			status = "JAMMED"
		(r[0] as Label).text = d.name
		(r[0] as Label).add_theme_color_override("font_color", col)
		(r[2] as Label).text = status
		(r[2] as Label).add_theme_color_override("font_color", Color.WHITE if st == "paused" else col)
		UiKit.set_bar(r[1], 0.0 if st == "down" else float(d.upload))


func wing_order(order: String) -> void:
	wing_order_shown = order


func ping() -> void:
	ping_t = 0.0


func set_radar_range(r: float) -> void:
	_radar_target = r


func show_card(on: bool) -> void:
	_card.visible = on
	if on:
		_card.modulate.a = 0.0
		var t := _card.get_node("title") as Label
		t.modulate.a = 0.0
		var tw := _tw()
		tw.tween_property(_card, "modulate:a", 1.0, 1.2)
		tw.parallel().tween_property(t, "modulate:a", 1.0, 2.2)


func update(dt: float, g: Game) -> void:
	overlay.game = g
	radar.game = g
	# Banners.
	if _banner_active:
		_banner_t -= dt
		if _banner_t <= 0.35 and _banner_t + dt > 0.35:
			var tw := _tw().set_parallel(true)
			tw.tween_property(_banner, "modulate:a", 0.0, 0.35)
			tw.tween_property(_banner, "scale", Vector2(0.9, 0.9), 0.35)
		if _banner_t <= 0.0:
			_banner_active = false
			_banner.visible = false
	if not _banner_active and not _banner_q.is_empty():
		_show_banner(_banner_q.pop_front())
	# The banner sits over the timer and ace panel, which step aside meanwhile.
	var status_a := 0.0 if cinematic or _banner_active else 1.0
	if _timer_val.modulate.a != status_a:
		for c in [_timer_lbl, _timer_val, _subtimer, _boss]:
			(c as CanvasItem).modulate.a = status_a
	if _banner_active and _banner_stripes.visible:
		_banner_main.modulate.a = 1.0 if fmod(Time.get_ticks_msec() / 1000.0, 0.45) < 0.225 else 0.25
	else:
		_banner_main.modulate.a = 1.0
	# Radio.
	if not _radio_cur.is_empty():
		_radio_t += dt
		var full: String = _radio_cur[1]
		var shown := full.substr(0, mini(full.length(), int(_radio_t * 55.0)))
		if shown != _radio_text.text:
			_radio_text.text = shown
			# Let the panel shrink back after a longer line.
			_radio.size.y = 0.0
		if _radio_t >= _radio_dur:
			_radio_cur = []
			_radio.visible = false
	if _radio_cur.is_empty() and not _radio_q.is_empty():
		_radio_cur = _radio_q.pop_front()
		_radio_t = 0.0
		var who: String = _radio_cur[0]
		_radio.visible = true
		_radio_who.text = who
		var blue := who.begins_with("JOKER")
		_radio_style.border_color = Cfg.C_FRIEND if blue else Cfg.C_HUD
		_radio_who.add_theme_color_override("font_color", Cfg.C_FRIEND if blue else Cfg.C_HUD)
		_radio_text.text = ""
		var spoken: float = on_radio.call(who, _radio_cur[1]) if on_radio.is_valid() else 0.0
		_radio_dur = maxf(1.8 + (_radio_cur[1] as String).length() * 0.055, spoken + 0.6)
	if _radio.visible:
		_place_radio()  # follows the letterbox bars and the order chips
	# Numbers.
	var s := g.score
	if s.total != _last_score:
		_last_score = s.total
		_score_val.text = MathX.fmt_score(s.total)
	_hot.visible = s.hot_start > 1.001 and g.show_hot_start
	_hot.text = "HOT START x%.1f" % s.hot_start
	_combo_text.visible = s.combo > 0
	_combo_bar.visible = s.combo > 0
	if s.combo != _last_combo:
		if s.combo > _last_combo and s.combo > 0:
			_combo_text.pivot_offset = Vector2(0, 8)
			_combo_text.scale = Vector2(1.35, 1.35)
			_tw().tween_property(_combo_text, "scale", Vector2.ONE, 0.35)
		_last_combo = s.combo
		_combo_text.text = "COMBO x%d" % s.combo
	UiKit.set_bar(_combo_bar, 1.0 if s.combo_frozen else s.combo_timer / 10.0)
	var p := g.player
	_spd.text = str(int(round(p.speed * 3.6)))
	_alt.text = MathX.fmt_score(maxf(0.0, p.pos.y))
	var hp := maxf(0.0, p.hp / p.max_hp)
	UiKit.set_bar(_hull_bar, hp)
	_hull_num.text = str(int(ceil(hp * 100.0)))
	var low := hp < 0.35
	(_hull_bar.get_node("fill") as ColorRect).color = Cfg.C_HOSTILE if low else Cfg.C_HUD
	_hull_num.add_theme_color_override("font_color", Cfg.C_HOSTILE if low else Cfg.C_HUD)
	var gh := g.pc.last_ground
	var sink := -p.vel.y
	_pullup.visible = g.controls_enabled and p.pos.y - gh < 260.0 and sink > 0.0 and (p.pos.y - gh) / sink < 3.2 and fmod(Time.get_ticks_msec() / 1000.0, 0.35) < 0.2
	_area_warn.visible = g.out_of_area and g.controls_enabled
	_uploads = g.uploads_active
	radar_range += (_radar_target - radar_range) * minf(1.0, dt * 3.0)
	ping_t += dt
	overlay.queue_redraw()
	radar.queue_redraw()


## HUD animations run on real time, unaffected by slow motion.
func _tw() -> Tween:
	return create_tween().set_ignore_time_scale(true)
