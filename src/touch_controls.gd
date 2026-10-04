class_name TouchControls
extends Control
## Touch controls: a floating flight stick for the left thumb, a weapon/throttle cluster for
## the right thumb, tap-to-target anywhere, optional tilt steering and haptics. The output is
## sampled once per frame into Controls, so the flight model and mission code are unchanged.
## Port of touch.ts (multi-touch via InputEventScreenTouch/Drag indices).

signal enabled_changed(on: bool)

const STICK_R := 64.0
const DEAD := 0.08
const TAP_MS := 260
const TAP_PX := 14.0
const LOOK_HOLD_MS := 320
const BOOST_LATCH_MS := 280
const CLUSTER := ["gun", "msl", "boost", "brake", "roll", "tgt"]
const ORDERS := ["order1", "order2", "order3"]
const ORDER_TEXT := ["COVER ME", "SCOUTS", "SPLIT"]
const ORDER_KEYS := ["cover", "scouts", "split"]

## Touch UI is shown and sampled. Enabled by the first touch, disabled by keyboard/pad use.
var enabled := false
## Processed stick output, screen-up positive.
var x := 0.0
var y := 0.0
var boost_latched := false
var haptics := true
var tilt := TiltInput.new()
## Per-frame visual state pushed by the game (see render()).
var view := {
	"live": false, "controls": false, "lock": 0.0, "locked": false, "ecm": false,
	"rails": [1.0, 1.0], "boost": 1.0, "boosting": false, "gun_hot": false, "evade": false,
	"orders": "", "teach": "", "hint": "",
}

var safe_l := 0.0
var safe_r := 0.0
var safe_b := 0.0
var _stick_id := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _stick_used := false
var _held := {}  # touch index -> button name
var _edges := {}  # button name -> true
var _tgt_down := {}  # touch index -> msec
var _boost_down := {}  # touch index -> msec, or -1 when the press cancelled a latch
var _look_held := false
var _taps: Array[Vector2] = []
var _tap_cand := {}  # touch index -> [Vector2, msec]
var _last_roll_dir := 1
var _btn := {}  # name -> {"c": Vector2, "r": float} or {"rect": Rect2}
var _anim_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rest_stick()


func layout(w: float, h: float, sl: float, sr: float, sb: float) -> void:
	size = Vector2(w, h)
	safe_l = sl
	safe_r = sr
	safe_b = sb
	var R := w - sr
	var B := h - sb
	# Same geometry as the CSS cluster (right/bottom offsets + diameters).
	_btn["gun"] = {"c": Vector2(R - 22 - 49, B - 22 - 49), "r": 49.0}
	_btn["msl"] = {"c": Vector2(R - 138 - 41, B - 18 - 41), "r": 41.0}
	_btn["boost"] = {"c": Vector2(R - 128 - 33, B - 116 - 33), "r": 33.0}
	_btn["brake"] = {"c": Vector2(R - 238 - 30, B - 28 - 30), "r": 30.0}
	_btn["roll"] = {"c": Vector2(R - 36 - 32, B - 138 - 32), "r": 32.0}
	_btn["tgt"] = {"c": Vector2(R - 216 - 27, B - 132 - 27), "r": 27.0}
	_btn["pause"] = {"rect": Rect2(sl + 10, 10, 42, 42)}
	var font := UiKit.spaced(UiKit.bold, 1.1)
	var widths: Array[float] = []
	var total := 0.0
	for t in ORDER_TEXT:
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 23.0
		widths.append(tw)
		total += tw
	total += 12.0
	var x0 := (w - total) / 2.0
	for i in 3:
		_btn[ORDERS[i]] = {"rect": Rect2(x0, 100, widths[i], 28)}
		x0 += widths[i] + 6.0
	if _stick_id < 0:
		_rest_stick()
	queue_redraw()


func set_enabled(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	if not on:
		release_all()
	enabled_changed.emit(on)
	queue_redraw()


func release_all() -> void:
	_held.clear()
	_tgt_down.clear()
	_boost_down.clear()
	_tap_cand.clear()
	boost_latched = false
	_look_held = false
	_stick_id = -1
	x = 0.0
	y = 0.0
	_rest_stick()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			set_enabled(true)
			if view.live:
				_down(e.index, e.position)
		else:
			_up(e.index, e.position, e.canceled)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_update_stick(d.position)
	elif event is InputEventKey and event.is_pressed() and InputRouter.is_keyboard_key(event as InputEventKey):
		set_enabled(false)
	elif event is InputEventJoypadButton and event.is_pressed():
		set_enabled(false)


func _hit(pos: Vector2) -> String:
	var cine: bool = not view.controls
	for name in _btn:
		var b: Dictionary = _btn[name]
		if cine and name != "pause":
			continue
		if name in ORDERS and view.orders == "":
			continue
		if b.has("rect"):
			if (b.rect as Rect2).grow(4.0).has_point(pos):
				return name
		elif pos.distance_to(b.c) <= b.r + 6.0:
			return name
	return ""


func _down(index: int, pos: Vector2) -> void:
	var b := _hit(pos)
	if b != "":
		_held[index] = b
		var now := Time.get_ticks_msec()
		if b == "tgt":
			_tgt_down[index] = now
		elif b == "boost":
			# Tap toggles the afterburner; a press that starts while latched only cancels.
			_boost_down[index] = -1 if boost_latched else now
			boost_latched = false
		elif b != "gun" and b != "brake":
			_edges[b] = true
		if b == "roll":
			vibrate(10)
		queue_redraw()
		return
	_tap_cand[index] = [pos, Time.get_ticks_msec()]
	if pos.x < size.x * 0.5 and _stick_id < 0:
		_stick_id = index
		# Keep the whole base on screen.
		var m := STICK_R + 10.0
		_origin = Vector2(clampf(pos.x, m, size.x - m), clampf(pos.y, m, size.y - m))
		_update_stick(pos)


func _up(index: int, pos: Vector2, cancelled: bool) -> void:
	var now := Time.get_ticks_msec()
	if _held.has(index):
		var b: String = _held[index]
		_held.erase(index)
		if b == "tgt":
			var t0: int = _tgt_down.get(index, 0)
			_tgt_down.erase(index)
			if not cancelled and now - t0 < LOOK_HOLD_MS:
				_edges["tgt"] = true
		if b == "boost":
			var t0: int = _boost_down.get(index, 0)
			_boost_down.erase(index)
			# A quick tap latches boost on; a long press was momentary.
			if not cancelled and t0 >= 0 and now - t0 < BOOST_LATCH_MS:
				boost_latched = true
		queue_redraw()
	if _tap_cand.has(index):
		var c: Array = _tap_cand[index]
		_tap_cand.erase(index)
		if not cancelled and now - int(c[1]) < TAP_MS and pos.distance_to(c[0]) < TAP_PX:
			_taps.append(pos)
	if index == _stick_id:
		_stick_id = -1
		x = 0.0
		y = 0.0
		_rest_stick()


func _update_stick(p: Vector2) -> void:
	var d := p - _origin
	var dl := d.length()
	# Drag-follow: if the thumb wanders far past the rim, the base slides after it.
	if dl > STICK_R * 1.35:
		_origin += d * ((dl - STICK_R * 1.35) / dl)
		d = p - _origin
		dl = d.length()
	var n := minf(1.0, dl / STICK_R)
	var m := 0.0 if n < DEAD else pow((n - DEAD) / (1.0 - DEAD), 1.35)
	var u := d / dl if dl > 0.0 else Vector2.ZERO
	x = u.x * m
	y = -u.y * m
	_knob = u * n * STICK_R
	_stick_used = true
	queue_redraw()


func _rest_stick() -> void:
	_origin = Vector2(maxf(96.0, size.x * 0.13), size.y - maxf(110.0, size.y * 0.3))
	_knob = Vector2.ZERO
	queue_redraw()


func _is_held(b: String) -> bool:
	for v in _held.values():
		if v == b:
			return true
	return false


## Read once per frame. Edge-triggered actions are consumed.
func sample() -> Dictionary:
	var sx := x
	var sy := y
	var steering := _stick_id >= 0
	if not steering and tilt.active:
		tilt.poll()
		sx = tilt.steer
		sy = tilt.pitch
		steering = true
	var roll := 0
	if _edges.has("roll"):
		if absf(sx) > 0.25:
			roll = int(signf(sx))
		else:
			_last_roll_dir = -_last_roll_dir
			roll = _last_roll_dir
	var now := Time.get_ticks_msec()
	for id in _tgt_down:
		if now - int(_tgt_down[id]) >= LOOK_HOLD_MS:
			_look_held = true
	if _tgt_down.is_empty():
		_look_held = false
	var order := 1 if _edges.has("order1") else (2 if _edges.has("order2") else (3 if _edges.has("order3") else 0))
	var boost := boost_latched
	for t in _boost_down.values():
		if int(t) >= 0:
			boost = true
	var s := {
		"steering": steering, "x": sx, "y": sy,
		"gun": _is_held("gun"), "boost": boost, "brake": _is_held("brake"),
		"msl": _edges.has("msl"), "roll": roll, "tgt": _edges.has("tgt"), "look": _look_held,
		"pause": _edges.has("pause"), "order": order, "taps": _taps.duplicate(),
	}
	_edges.clear()
	_taps.clear()
	return s


## Brake or an empty tank cancels a latched boost.
func unlatch_boost() -> void:
	boost_latched = false


func render(v: Dictionary, dt: float) -> void:
	view = v
	_anim_t += dt
	visible = enabled and v.live
	if visible:
		queue_redraw()


func vibrate(ms_or_pattern) -> void:
	if not enabled or not haptics:
		return
	if ms_or_pattern is Array:
		var t := 0.0
		var on := true
		for ms in ms_or_pattern:
			if on:
				_vibrate_later(int(ms), t)
			t += float(ms) / 1000.0
			on = not on
	else:
		Input.vibrate_handheld(int(ms_or_pattern))


func _vibrate_later(ms: int, delay: float) -> void:
	if delay <= 0.0:
		Input.vibrate_handheld(ms)
	else:
		get_tree().create_timer(delay, true, false, true).timeout.connect(func() -> void: Input.vibrate_handheld(ms))


# ---------------------------------------------------------------- Drawing

func _draw() -> void:
	if not visible:
		return
	var cine: bool = not view.controls
	_draw_pause()
	if cine:
		_draw_hint()
		return
	_draw_stick()
	for name in CLUSTER:
		_draw_button(name)
	if view.orders != "":
		for i in 3:
			_draw_chip(i)
	_draw_hint()


func _pulse(period: float) -> float:
	return 0.5 - 0.5 * cos(TAU * fmod(_anim_t, period) / period)


func _fan(c: Vector2, r: float, inner: Color, outer: Color, center_off := Vector2.ZERO) -> void:
	var n := 40
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.append(c + center_off)
	cols.append(inner)
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
		cols.append(outer)
	draw_polygon(pts, cols)


func _glow(c: Vector2, r: float, col: Color, spread: float) -> void:
	var steps := 6
	for i in steps:
		var k := float(i + 1) / steps
		var a := col.a * (1.0 - k) * 0.2
		draw_arc(c, r + spread * k, 0, TAU, 48, Color(col.r, col.g, col.b, a), spread / steps + 1.0, true)


func _draw_stick() -> void:
	var active := _stick_id >= 0
	var op := 1.0 if active else 0.5
	var c := _origin
	var teach: bool = view.teach == "stick"
	var hud := Cfg.C_HUD
	_fan(c, STICK_R, Color(0.024, 0.055, 0.043, 0.12 * op), Color(0.024, 0.055, 0.043, 0.38 * op))
	var ring_col := Cfg.C_GOLD if teach else Color(hud.r, hud.g, hud.b, 0.55)
	if teach:
		var p := _pulse(1.0)
		draw_arc(c, STICK_R + 3.5, 0, TAU, 64, Color(1, 0.82, 0.35, 0.35 * p * op), 7.0, true)
		_glow(c, STICK_R, Color(1, 0.82, 0.35, 0.6 * p * op), 22.0)
	draw_arc(c, STICK_R - 1.0, 0, TAU, 64, Color(ring_col.r, ring_col.g, ring_col.b, ring_col.a * op), 2.0, true)
	for k in 4:
		var a := -PI / 2.0 + k * PI / 2.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (STICK_R - 4.0), c + dir * (STICK_R - 13.0), Color(hud.r, hud.g, hud.b, 0.7 * op), 2.0)
	var kc := c + _knob
	draw_circle(kc + Vector2(0, 2), 31.0, Color(0, 0, 0, 0.12 * op), true, -1.0, true)
	_fan(kc, 29.0, Color(0.784, 1, 0.902, 0.55 * op), Color(0.314, 0.627, 0.47, 0.35 * op), Vector2(-5.8, -8.7))
	draw_arc(kc, 28.0, 0, TAU, 48, Color(hud.r, hud.g, hud.b, 0.9 * op), 2.0, true)
	if not _stick_used:
		HudOverlay.text_at(self, c + Vector2(0, 74 + 7), "DRAG TO FLY", 11, Color(hud.r, hud.g, hud.b, op), HORIZONTAL_ALIGNMENT_CENTER, UiKit.spaced(UiKit.bold, 2.2))


func _draw_button(name: String) -> void:
	var b: Dictionary = _btn[name]
	var c: Vector2 = b.c
	var r: float = b.r
	var down := _is_held(name) or (name == "boost" and _boost_down.size() > 0)
	if down:
		r *= 0.9
	var hud := Cfg.C_HUD
	var border := Color(hud.r, hud.g, hud.b, 0.6)
	var bg := Color(0.024, 0.055, 0.043, 0.34)
	var fg := hud
	var alpha := 1.0
	var teach: bool = view.teach == name
	var label := name.to_upper()
	# The web's `#touch .tb` rule (13px) outranks the per-button sizes.
	var font_size := 13
	match name:
		"gun":
			if view.gun_hot:
				border = Color.WHITE
				fg = Color.WHITE
				_glow(c, r, Color(1, 1, 1, 0.35), 20.0)
				draw_arc(c, r + 2.0, 0, TAU, 64, Color(1, 1, 1, 0.25), 4.0, true)
		"msl":
			var ring := Cfg.C_HOSTILE if view.locked else hud
			# Lock progress ring just outside the button.
			draw_arc(c, r + 4.3, 0, TAU, 64, Color(hud.r, hud.g, hud.b, 0.1), 7.4, true)
			var lk: float = view.lock
			if lk > 0.01:
				draw_arc(c, r + 4.3, -PI / 2.0, -PI / 2.0 + TAU * lk, maxi(4, int(64 * lk)), ring, 7.4, true)
			if view.locked:
				border = Cfg.C_HOSTILE
				fg = Color.WHITE
				bg = Color(0.47, 0.04, 0.016, 0.45)
			if view.ecm:
				alpha = 0.55
		"boost":
			var on: bool = view.boosting or boost_latched
			if on:
				border = Cfg.C_GOLD
				fg = Cfg.C_GOLD
				_glow(c, r, Color(1, 0.745, 0.235, 0.45), 16.0)
		"roll":
			if view.evade:
				border = Cfg.C_HOSTILE
				fg = Color.WHITE
				bg = Color(0.59, 0.04, 0.016, 0.5)
				label = "EVADE"
				var p := _pulse(0.5)
				draw_arc(c, r + 4.0, 0, TAU, 64, Color(1, 0.235, 0.157, 0.35 * p), 8.0, true)
				_glow(c, r, Color(1, 0.235, 0.157, 0.7 * p), 24.0)
	if teach:
		border = Cfg.C_GOLD
		fg = Cfg.C_GOLD
		var p := _pulse(1.0)
		draw_arc(c, r + 3.5, 0, TAU, 64, Color(1, 0.82, 0.35, 0.35 * p), 7.0, true)
		_glow(c, r, Color(1, 0.82, 0.35, 0.6 * p), 22.0)
	if down:
		bg = Color(hud.r, hud.g, hud.b, 0.38)
		fg = Color.WHITE
	draw_circle(c + Vector2(0, 2), r + 2.0, Color(0, 0, 0, 0.1 * alpha), true, -1.0, true)
	draw_circle(c, r, Color(bg.r, bg.g, bg.b, bg.a * alpha), true, -1.0, true)
	if name == "boost":
		_energy_fill(c, r, view.boost, Color(1, 0.745, 0.235, 0.28) if (view.boosting or boost_latched) else Color(hud.r, hud.g, hud.b, 0.18))
	if name == "gun":
		draw_arc(c, r - 26.0, 0, TAU, 48, Color(fg.r, fg.g, fg.b, 0.35 * alpha), 1.5, true)
	draw_arc(c, r - 1.0, 0, TAU, 64, Color(border.r, border.g, border.b, border.a * alpha), 2.0, true)
	var font := UiKit.spaced(UiKit.bold, font_size * 0.12)
	var fc := Color(fg.r, fg.g, fg.b, fg.a * alpha)
	if name == "msl":
		HudOverlay.text_at(self, c + Vector2(0, -4), label, font_size, fc, HORIZONTAL_ALIGNMENT_CENTER, font)
		var rails: Array = view.rails
		for i in 2:
			var px := c.x - 16.0 + i * 18.0
			var py := c.y + 9.0
			draw_rect(Rect2(px, py, 14, 4), Color(hud.r, hud.g, hud.b, 0.2 * alpha))
			draw_rect(Rect2(px, py, 14.0 * clampf(float(rails[i]), 0.0, 1.0), 4), fc)
	else:
		HudOverlay.text_at(self, c, label, font_size, fc, HORIZONTAL_ALIGNMENT_CENTER, font)


## Fill the lower part of a circle up to `frac` of its height.
func _energy_fill(c: Vector2, r: float, frac: float, col: Color) -> void:
	if frac <= 0.01:
		return
	if frac >= 0.99:
		draw_circle(c, r - 1.0, col, true, -1.0, true)
		return
	var level := r - 2.0 * r * frac  # y offset of the fill line from the centre (y down)
	var phi := acos(clampf(level / r, -1.0, 1.0))
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var a := PI / 2.0 - phi + 2.0 * phi * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * (r - 1.0))
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)


func _draw_pause() -> void:
	var rect: Rect2 = _btn["pause"].rect
	var down := _is_held("pause")
	var hud := Cfg.C_HUD
	var bg := Color(hud.r, hud.g, hud.b, 0.38) if down else Color(0.024, 0.055, 0.043, 0.34)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(hud.r, hud.g, hud.b, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
	var fg := Color.WHITE if down else hud
	var cx := rect.get_center()
	draw_rect(Rect2(cx.x - 8, cx.y - 8, 5, 16), fg)
	draw_rect(Rect2(cx.x + 3, cx.y - 8, 5, 16), fg)


func _draw_chip(i: int) -> void:
	var rect: Rect2 = _btn[ORDERS[i]].rect
	var on: bool = view.orders == ORDER_KEYS[i]
	var teach: bool = view.teach == "orders"
	var friend := Cfg.C_FRIEND
	var sb := StyleBoxFlat.new()
	sb.bg_color = friend if on else Color(0.016, 0.047, 0.078, 0.45)
	sb.border_color = Color(friend.r, friend.g, friend.b, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.anti_aliasing = true
	if teach:
		var p := _pulse(1.0)
		var g := StyleBoxFlat.new()
		g.bg_color = Color(1, 0.82, 0.35, 0.35 * p)
		g.set_corner_radius_all(20)
		g.anti_aliasing = true
		draw_style_box(g, rect.grow(7.0))
	draw_style_box(sb, rect)
	HudOverlay.text_at(self, rect.get_center(), ORDER_TEXT[i], 11, Color("04121c") if on else friend, HORIZONTAL_ALIGNMENT_CENTER, UiKit.spaced(UiKit.bold, 1.1))


func _draw_hint() -> void:
	var hint: String = view.hint
	if hint == "":
		return
	var a := 1.0 if fmod(_anim_t, 1.2) < 0.6 else 0.25
	HudOverlay.text_at(self, Vector2(size.x / 2.0, size.y * 0.78 - 9.0), hint, 13, Color(1, 1, 1, 0.85 * a), HORIZONTAL_ALIGNMENT_CENTER, UiKit.spaced(UiKit.bold, 3.9))


# ---------------------------------------------------------------- Tilt

## Steering-wheel style tilt from the gravity sensor (already rotated into screen space by
## the engine). Measures wheel rotation and fore/aft tilt relative to a calibrated pose.
class TiltInput:
	var active := false
	var steer := 0.0
	var pitch := 0.0
	var _neutral := INF

	func enable() -> bool:
		var g := Input.get_gravity()
		if g.length_squared() < 0.01:
			g = Input.get_accelerometer()
		if g.length_squared() < 0.01 and OS.get_name() != "Android":
			return false
		active = true
		_neutral = INF
		return true

	func disable() -> void:
		active = false
		steer = 0.0
		pitch = 0.0

	func recalibrate() -> void:
		_neutral = INF

	func poll() -> void:
		var g := Input.get_gravity()
		if g.length_squared() < 0.01:
			g = Input.get_accelerometer()
		if g.length_squared() < 0.01:
			return
		# World "up" in screen coordinates (x right, y up on screen, z out of the glass).
		var up := -g.normalized()
		var wheel := -atan2(up.x, up.y)
		var fore := atan2(up.z, up.y)
		if _neutral == INF:
			_neutral = fore
		steer = _dz(wheel, deg_to_rad(3.0), deg_to_rad(30.0))
		# Pulling the top edge toward you (screen tilts up toward vertical) climbs.
		pitch = _dz(_neutral - fore, deg_to_rad(3.0), deg_to_rad(22.0))

	static func _dz(v: float, dead: float, full: float) -> float:
		var a := absf(v)
		return 0.0 if a < dead else signf(v) * clampf((a - dead) / (full - dead), 0.0, 1.0)
