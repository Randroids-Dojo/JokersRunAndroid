class_name InputRouter
extends Node
## Keyboard + mouse + gamepad + touch, merged into one Controls per frame (port of input.ts).

var c := Controls.new()
var touch: TouchControls
var using_pad := false
## Use assisted steering for the touch stick and tilt.
var touch_assist := true

var _pressed := {}  # keycode -> true, this frame
var _mouse_pressed := {}
var _last_tap := {"L": -1e9, "R": -1e9}
var _pending_roll := 0
var _pad_prev := {}


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			using_pad = false
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			_pressed[code] = true
			var now := Time.get_ticks_msec()
			var tap := ""
			if code == KEY_A or code == KEY_LEFT:
				tap = "L"
			elif code == KEY_D or code == KEY_RIGHT:
				tap = "R"
			if tap != "":
				if now - float(_last_tap[tap]) < 280.0:
					_pending_roll = -1 if tap == "L" else 1
					_last_tap[tap] = -1e9
				else:
					_last_tap[tap] = now
	elif event is InputEventMouseButton and (event as InputEventMouseButton).device != InputEvent.DEVICE_ID_EMULATION:
		# device -1 is the mouse emulated from touch; real mice only.
		var m := event as InputEventMouseButton
		if m.pressed and not DisplayServer.is_touchscreen_available():
			_mouse_pressed[m.button_index] = true


func release_all() -> void:
	_pressed.clear()
	_mouse_pressed.clear()
	if touch:
		touch.release_all()


var using_touch: bool:
	get:
		return touch != null and touch.enabled


func _k(codes: Array) -> bool:
	for code in codes:
		if Input.is_physical_key_pressed(code):
			return true
	return false


func _p(codes: Array) -> bool:
	for code in codes:
		if _pressed.has(code):
			return true
	return false


## Sample once per rendered frame before simulation steps.
func poll() -> void:
	var pitch := (1.0 if _k([KEY_W, KEY_UP]) else 0.0) - (1.0 if _k([KEY_S, KEY_DOWN]) else 0.0)
	var roll := (1.0 if _k([KEY_D, KEY_RIGHT]) else 0.0) - (1.0 if _k([KEY_A, KEY_LEFT]) else 0.0)
	var yaw := (1.0 if _k([KEY_E]) else 0.0) - (1.0 if _k([KEY_Q]) else 0.0)
	var boost := _k([KEY_SHIFT])
	var brake := _k([KEY_X, KEY_C])
	var mouse_l := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not DisplayServer.is_touchscreen_available()
	var guns := _k([KEY_SPACE, KEY_J]) or mouse_l
	var missile := _p([KEY_F, KEY_K]) or _mouse_pressed.has(MOUSE_BUTTON_RIGHT)
	var target_next := _p([KEY_TAB, KEY_T, KEY_L]) or _mouse_pressed.has(MOUSE_BUTTON_MIDDLE)
	var roll_tap := _pending_roll
	if roll_tap == 0 and _p([KEY_R]):
		roll_tap = -1 if roll < 0.0 else 1
	var look := _k([KEY_V])
	var order := 1 if _p([KEY_1]) else (2 if _p([KEY_2]) else (3 if _p([KEY_3]) else 0))
	var pause := _p([KEY_ESCAPE, KEY_P])
	var confirm := _p([KEY_ENTER, KEY_KP_ENTER, KEY_SPACE])
	var skip := _p([KEY_ENTER, KEY_SPACE])

	for dev in Input.get_connected_joypads():
		var dz := func(v: float) -> float: return 0.0 if absf(v) < 0.14 else (v - signf(v) * 0.14) / 0.86
		var ax: float = dz.call(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X))
		var ay: float = dz.call(Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		var btn := func(b: int) -> bool: return Input.is_joy_button_pressed(dev, b)
		var any := false
		var pressed_now := {}
		for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			var key := "%d:%d" % [dev, b]
			var down: bool = btn.call(b)
			pressed_now[b] = down and not _pad_prev.get(key, false)
			_pad_prev[key] = down
			any = any or down
		var lt := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.5
		var rt := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		if absf(ax) > 0.0 or absf(ay) > 0.0 or any or lt or rt:
			using_pad = true
		if absf(ax) > absf(roll):
			roll = ax
		if absf(ay) > absf(pitch):
			pitch = -ay
		if btn.call(JOY_BUTTON_LEFT_SHOULDER):
			yaw = -1.0
		if btn.call(JOY_BUTTON_RIGHT_SHOULDER):
			yaw = 1.0
		boost = boost or rt
		brake = brake or lt
		guns = guns or btn.call(JOY_BUTTON_X)
		missile = missile or pressed_now[JOY_BUTTON_A]
		target_next = target_next or pressed_now[JOY_BUTTON_Y]
		if pressed_now[JOY_BUTTON_B]:
			roll_tap = -1 if roll < 0.0 else 1
		look = look or btn.call(JOY_BUTTON_LEFT_STICK) or btn.call(JOY_BUTTON_RIGHT_STICK)
		if pressed_now[JOY_BUTTON_DPAD_UP]:
			order = 1
		if pressed_now[JOY_BUTTON_DPAD_LEFT]:
			order = 2
		if pressed_now[JOY_BUTTON_DPAD_RIGHT]:
			order = 3
		pause = pause or pressed_now[JOY_BUTTON_START]
		confirm = confirm or pressed_now[JOY_BUTTON_A] or pressed_now[JOY_BUTTON_START]
		skip = skip or pressed_now[JOY_BUTTON_A] or pressed_now[JOY_BUTTON_START]

	var turn := 0.0
	var assist := false
	var taps: Array[Vector2] = []
	if touch and touch.enabled:
		var t := touch.sample()
		if t.steering:
			if touch_assist:
				assist = true
				turn = t.x
			elif absf(t.x) > absf(roll):
				roll = t.x
			if absf(t.y) > absf(pitch):
				pitch = t.y
		elif touch_assist and roll == 0.0 and pitch == 0.0 and yaw == 0.0:
			# Thumb off the stick in assisted mode: hold wings level and the nose on the horizon.
			assist = true
		boost = boost or t.boost
		brake = brake or t.brake
		guns = guns or t.gun
		missile = missile or t.msl
		target_next = target_next or t.tgt
		if t.roll != 0:
			roll_tap = t.roll
		look = look or t.look
		if t.order != 0:
			order = t.order
		pause = pause or t.pause
		skip = skip or not (t.taps as Array).is_empty()
		for tp in t.taps:
			taps.append(tp)
	c.using_touch = using_touch
	c.taps = taps
	c.pause = pause
	c.confirm = confirm
	c.skip = skip
	c.look = look
	c.order = order
	c.target_next = target_next
	c.turn = turn
	c.assist = assist
	c.pitch = pitch
	c.roll = roll
	c.yaw = yaw
	c.boost = boost
	c.brake = brake
	c.guns = guns
	c.missile = missile
	c.roll_tap = roll_tap
	_pressed.clear()
	_mouse_pressed.clear()
	_pending_roll = 0
