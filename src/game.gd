class_name Game
extends Node3D
## Owns the world, the fixed-step simulation, combat rules, targeting, game flow (title,
## play, pause, fail, debrief) and per-frame presentation. Port of game.ts + main.ts.

const WING_SLOTS := [Vector3(-55, 4, 50), Vector3(55, 4, 50), Vector3(110, 9, 100)]
const SPANS := {"player": 7.0, "wingman": 7.0, "fighter": 7.0, "ace": 7.4, "scout": 15.0, "drone": 3.4}

var sim: Node3D
var terrain: Terrain
var world: World
var fleet: Fleet
var fx: Fx
var trails: Trails
var weapons: Weapons
var rig: CameraRig
var hud: Hud
var touch: TouchControls
var screens: Screens
var audio: GameAudio
var input: InputRouter
var mission: Mission
var score := Score.new()
var pc := PlayerController.new()
var settings := Settings.new()
var player: Aircraft
var aircraft: Array[Aircraft] = []
var wingmen: Array[Aircraft] = []
## The merged controls for this frame.
var controls: Controls
var _neutral := Controls.new()
## Touch UI: which control the tutorial is teaching right now.
var touch_teach := ""
## A cinematic that a tap can skip is waiting.
var skippable := false
## Optional test pilot (debug builds): Callable(g, dt) run after input polling.
var bot: Callable = Callable()

var time := 0.0
var real_time := 0.0
var time_scale := 1.0
var _slow_t := 0.0
var _slow_scale := 1.0
var mission_time := 0.0

var target: Aircraft = null
var lock_progress := 0.0
var locked := false
var missile_rails := [0.0, 0.0]
var _rail_idx := 0
var _gun_cd := 0.0
var _muzzle_side := 1.0

var controls_enabled := false
var cinematic := false
var formation := true
var wing_order := "cover"
var uploads_active := false
var show_boundary := false
var show_hot_start := false
var out_of_area := false
var area_center := Vector3(4000, 0, -2000)
var boost_regen_mult := 1.0
var lock_penalty := 1.0
## title | play | paused | failed | clear | debrief
var state := "title"
var god := false
## Recent notable events for diagnosis.
var events: Array[String] = []
var fps_avg := 60.0

var _enemy_launch_cd := 0.0
var _fail_timer := -1.0
var _fail_info := ["", ""]
var _last_hit_sound := 0.0
var _last_enemy_gun_sound := 0.0
var _last_popup_jam := 0.0
var _last_dodge_popup := 0.0
var _last_missile_radio := -100.0
var _vignette := 0.0
var _fade_tween: Tween
var _view_size := Vector2(844, 390)
# Adaptive render scale (the web build's DPR governor).
var _render_scale := 1.0
var _render_scale_max := 1.5
var _perf_acc := 0.0
var _perf_n := 0
var _perf_good := 0
var _perf_hold_until := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings.load_file()
	UiKit.init()
	sim = Node3D.new()
	sim.name = "Sim"
	sim.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sim)
	terrain = Terrain.new()
	sim.add_child(terrain)
	world = World.new()
	sim.add_child(world)
	world.setup(terrain)
	fleet = Fleet.new()
	sim.add_child(fleet)
	fx = Fx.new()
	sim.add_child(fx)
	fx.ground_at = func(x: float, z: float) -> float: return terrain.ground(x, z)
	trails = Trails.new()
	sim.add_child(trails)
	weapons = Weapons.new()
	sim.add_child(weapons)
	rig = CameraRig.new()
	add_child(rig)
	audio = GameAudio.new()
	add_child(audio)
	input = InputRouter.new()
	add_child(input)
	controls = input.c
	hud = Hud.new()
	add_child(hud)
	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 2
	add_child(touch_layer)
	touch = TouchControls.new()
	touch_layer.add_child(touch)
	input.touch = touch
	touch.haptics = settings.haptics
	touch.set_enabled(DisplayServer.is_touchscreen_available())
	touch.enabled_changed.connect(func(_on: bool) -> void:
		screens.set_touch_mode(touch.enabled)
		mission.refresh_prompt()
		_on_resize())
	screens = Screens.new()
	screens.settings = settings
	add_child(screens)
	screens.set_touch_mode(touch.enabled)
	screens.action.connect(_on_action)
	screens.toggled.connect(_on_toggle)
	player = _make_player()
	mission = Mission.new(self)
	hud.on_radio = func(who: String, text: String) -> float:
		audio.radio_blip()
		return audio.speak(text, who)
	_apply_settings()
	if settings.tilt and not touch.tilt.enable():
		settings.tilt = false
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	_render_scale_max = 1.5 if DisplayServer.is_touchscreen_available() else 1.75
	_render_scale = _render_scale_max
	_apply_render_scale()
	to_title()
	var selftest := OS.has_feature("selftest")
	for arg in OS.get_cmdline_user_args():
		selftest = selftest or arg.begins_with("--selftest")
	if selftest:
		add_child(SelfTest.new())


func _on_resize() -> void:
	var vp := get_viewport()
	_view_size = vp.get_visible_rect().size
	var w := _view_size.x
	var h := _view_size.y
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var sl := 0.0
	var sr := 0.0
	var sb := 0.0
	if win.x > 0 and safe.size.x > 0:
		var k := w / float(win.x)
		sl = maxf(0.0, safe.position.x * k)
		sr = maxf(0.0, (win.x - safe.end.x) * k)
		sb = maxf(0.0, (win.y - safe.end.y) * (h / float(win.y)))
	hud.layout(w, h, sl, sr)
	touch.layout(w, h, sl, sr, sb)
	screens.layout(w, h, sl, sr)
	_apply_render_scale()


func _apply_render_scale() -> void:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return
	# Render scale is in CSS-pixel terms: 1.0 = one pixel per base unit, like the web's DPR.
	var s := clampf(_render_scale * _view_size.x / float(win.x), 0.25, 1.0)
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


# ---------------------------------------------------------------- Spawning

func _make_player() -> Aircraft:
	var m := Models.aircraft("joker")
	var a := Aircraft.new("player", "blue", m, "JOKER 1")
	a.callsign = "J1"
	a.hp = Cfg.P_HP
	a.max_hp = Cfg.P_HP
	a.radius = 9.0
	_attach(a, true)
	return a


func _attach(a: Aircraft, muzzle := false) -> void:
	sim.add_child(a.root)
	a.fx = AircraftFx.new(muzzle)
	sim.add_child(a.fx)
	aircraft.append(a)
	a.vapor_trails = [trails.alloc(), trails.alloc()]


func _add(kind: String, team: String, model: String, label: String, pos: Vector3, fwd: Vector3, speed: float) -> Aircraft:
	var a := Aircraft.new(kind, team, Models.aircraft(model), label)
	a.pos = pos
	a.quat = MathX.quat_from_fwd_up(fwd.normalized(), Vector3.UP)
	a.speed = speed
	a.update_basis()
	_attach(a)
	return a


func spawn_fighter(pos: Vector3, fwd: Vector3, mode: String, skill := 0.55) -> Aircraft:
	var a := _add("fighter", "red", "enemy", "BANDIT", pos, fwd, 270.0)
	a.brain = AI.FighterBrain.new(mode, skill)
	a.hp = 100.0
	a.max_hp = 100.0
	a.radius = 11.0
	a.flares = 1
	return a


func spawn_scout(pos: Vector3, fwd: Vector3, label: String) -> Aircraft:
	var a := _add("scout", "red", "scout", label, pos, fwd, 135.0)
	a.brain = AI.ScoutBrain.new()
	a.hp = 320.0
	a.max_hp = 320.0
	a.radius = 18.0
	a.mission_target = true
	a.hp_floor_from_others = 0.3
	a.flares = 2
	return a


func spawn_drone(pos: Vector3, fwd: Vector3, mode: String, alt: float) -> Aircraft:
	var label := "DRONE A" if mode == "lock" else ("DRONE B" if mode == "guns" else "DRONE C")
	var a := _add("drone", "red", "drone", label, pos, fwd, 250.0 if mode == "evasive" else 130.0)
	a.brain = AI.DroneBrain.new(mode, alt)
	a.hp = 60.0 if mode == "guns" else 50.0
	a.max_hp = a.hp
	a.radius = 8.5
	if mode == "guns":
		a.ecm = true
		a.missile_jammer = true
	return a


func spawn_ace(pos: Vector3, fwd: Vector3) -> Aircraft:
	var a := _add("ace", "red", "ace", "ACE", pos, fwd, 400.0)
	a.brain = AI.AceBrain.new()
	a.hp = 900.0
	a.max_hp = 900.0
	a.radius = 11.5
	a.flares = 8
	a.hp_floor_from_others = 0.52
	return a


func spawn_wingmen() -> void:
	for w in wingmen:
		despawn(w)
	wingmen = []
	var names := ["JOKER 2", "JOKER 3", "JOKER 4"]
	for i in 3:
		var a := _add("wingman", "blue", "joker", names[i], player.pos, player.fwd, player.speed)
		a.callsign = "J%d" % (i + 2)
		a.brain = AI.WingmanBrain.new(WING_SLOTS[i], i)
		a.invulnerable = true
		a.radius = 9.0
		wingmen.append(a)
	place_wingmen_in_formation()


func place_wingmen_in_formation() -> void:
	var p := player
	for i in wingmen.size():
		var w := wingmen[i]
		w.pos = p.quat * (WING_SLOTS[i] as Vector3) + p.pos
		w.quat = p.quat
		w.speed = p.speed
		w.update_basis()


func unfreeze_wingmen_behind_player() -> void:
	var p := player
	for i in wingmen.size():
		var w := wingmen[i]
		w.frozen = false
		w.hidden = false
		w.pos = p.quat * (WING_SLOTS[i] as Vector3) + p.pos - p.fwd * 1400.0
		w.quat = p.quat
		w.speed = p.speed + 80.0
		w.update_basis()


func despawn(a: Aircraft) -> void:
	var i := aircraft.find(a)
	if i >= 0:
		aircraft.remove_at(i)
	if a.root.get_parent():
		a.root.get_parent().remove_child(a.root)
	if a != player:
		a.root.queue_free()
		if a.fx:
			a.fx.queue_free()
			a.fx = null
	elif a.fx:
		a.fx.stop()
	trails.free_trail(a.vapor_trails[0])
	trails.free_trail(a.vapor_trails[1])
	a.vapor_trails = [-1, -1]
	if target == a:
		target = null
		lock_progress = 0.0


func reset_world() -> void:
	for a in aircraft.duplicate():
		if a != player:
			despawn(a)
	wingmen = []
	weapons.clear()
	fx.clear()
	trails.clear()
	var p := player
	p.alive = true
	p.wreck = false
	p.hidden = false
	p.frozen = false
	p.hp = p.max_hp
	p.roll_visual = 0.0
	p.last_hit_time = -100.0
	if not aircraft.has(p):
		aircraft.append(p)
		sim.add_child(p.root)
	p.vapor_trails = [trails.alloc(), trails.alloc()]
	target = null
	lock_progress = 0.0
	locked = false
	missile_rails = [0.0, 0.0]
	pc.reset()
	formation = true
	wing_order = "cover"
	_vignette = 0.0


# ---------------------------------------------------------------- Flow

func to_title() -> void:
	mission.cancel()
	_set_paused(false)
	reset_world()
	state = "title"
	fleet.set_time(0.0)
	player.hidden = true
	player.pos = Vector3(0, -500, 0)
	set_controls(false)
	hud.set_visible_hud(false)
	set_cinematic(false)
	hud.show_card(false)
	screens.show_screen("title")
	rig.play(func(t: float) -> Dictionary:
		var c := fleet.carrier_pos()
		var a := 2.3 + t * 0.045
		return {"pos": Vector3(c.x + cos(a) * 560.0, 95.0 + sin(t * 0.12) * 25.0, c.z + sin(a) * 560.0), "look": Vector3(c.x - 40, 30, c.z - 60), "fov": 48.0})
	audio.set_track("calm", true)
	fade_in()


func start_mission(cp := "launch") -> void:
	touch.tilt.recalibrate()
	_apply_settings()
	screens.show_screen("")
	hud.show_card(false)
	state = "play"
	player.hidden = false
	mission_time = 0.0
	time = 0.0
	_fade_to(1.0, 0.0)
	mission.start(cp, cp != "launch")


func retry() -> void:
	_set_paused(false)
	screens.show_screen("")
	hud.show_card(false)
	state = "play"
	_fail_timer = -1.0
	time_scale = 1.0
	_slow_t = 0.0
	_fade_to(1.0, 0.0)
	mission.start(mission.checkpoint, true)


func restart() -> void:
	_set_paused(false)
	_fail_timer = -1.0
	_slow_t = 0.0
	start_mission("launch")


func pause() -> void:
	if state != "play":
		return
	state = "paused"
	input.release_all()
	screens.show_screen("pause")
	_set_paused(true)


func resume() -> void:
	if state != "paused":
		return
	state = "play"
	screens.show_screen("")
	_set_paused(false)


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	audio.pause_all(on)


func set_controls(on: bool) -> void:
	controls_enabled = on


func set_cinematic(on: bool) -> void:
	cinematic = on
	hud.set_cinematic(on)


func slowmo(scale: float, dur_real: float) -> void:
	if settings.reduced_motion:
		scale = maxf(scale, 0.6)
	_slow_scale = scale
	_slow_t = dur_real


func _fade_to(alpha: float, dur: float, white := false) -> void:
	if _fade_tween:
		_fade_tween.kill()
	hud.fade.color = Color(1, 1, 1, hud.fade.color.a) if white else Color(0, 0, 0, hud.fade.color.a)
	if dur <= 0.0:
		hud.fade.color.a = alpha
		return
	_fade_tween = create_tween().set_ignore_time_scale(true)
	_fade_tween.tween_property(hud.fade, "color:a", alpha, dur)


func fade_in() -> void:
	_fade_to(0.0, 0.9)


func flash_white() -> void:
	_fade_to(1.0, 0.0, true)
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_ignore_time_scale(true)
	_fade_tween.tween_interval(0.12)
	_fade_tween.tween_property(hud.fade, "color:a", 0.0, 0.5)


func flash_black() -> void:
	_fade_to(1.0, 0.4)


func show_card() -> void:
	hud.show_card(true)


func fail(reason: String, detail: String) -> void:
	if state != "play":
		return
	state = "failed"
	_fail_info = [reason, detail]
	mission.cancel()
	set_controls(false)
	hud.prompt("")
	hud.countdown(0)
	hud.banner_now("MISSION FAILED", reason, "red", 3.0)
	audio.set_track("none", true)
	audio.stop_speech()
	slowmo(0.35, 1.4)
	_fail_timer = 2.8
	log_event("fail " + reason)


func show_debrief() -> void:
	state = "debrief"
	hud.show_card(false)
	set_cinematic(false)
	hud.set_visible_hud(false)
	var s := score
	var is_best := s.total > settings.best
	if is_best:
		settings.best = int(round(s.total))
		settings.save_file()
	var acc := int(round(float(s.shots_hit) / maxf(1.0, s.shots_fired + s.missiles_fired) * 100.0)) if s.shots_fired > 0 else 0
	var ace_txt := "ESCAPED"
	if s.ace_bonus:
		ace_txt = "DESTROYED · UNBROKEN COMBO" if s.ace_combo_bonus else "DESTROYED"
	var rows := [
		["FLIGHT CHECK", "%s · %d/5 CLEAN" % [MathX.fmt_clock(s.tutorial_time, true), s.clean_count]],
		["HOT START", "x%.1f" % s.hot_start],
		["MISSILE KILLS", str(s.missile_kills)],
		["GUN KILLS", str(s.gun_kills)],
		["MAX COMBO", "x%d" % s.combo_max],
		["ACE", ace_txt],
		["ACCURACY", "%d%%" % acc],
		["HULL DAMAGE TAKEN", str(int(round(s.damage_taken)))],
		["MISSION TIME", MathX.fmt_clock(mission_time)],
		["SCORE", MathX.fmt_score(s.total) + ("  NEW BEST" if is_best else ""), "total"],
	]
	screens.set_debrief(s.rank(), rows)
	screens.show_screen("debrief")
	audio.set_track("calm", true)
	log_event("debrief score=%d rank=%s" % [int(s.total), s.rank()])


func _apply_settings() -> void:
	audio.voice_on = settings.voice
	if not settings.voice:
		audio.stop_speech()
	audio.set_muted(settings.mute)
	audio.set_music_volume(0.5 if settings.music else 0.0)
	rig.reduced_motion = settings.reduced_motion
	input.touch_assist = settings.assist
	touch.haptics = settings.haptics


func _on_toggle(key: String) -> void:
	settings.toggle(key)
	if key == "tilt":
		if settings.tilt:
			if not touch.tilt.enable():
				settings.toggle("tilt")
				screens.mark_unavailable("tilt")
		else:
			touch.tilt.disable()
	_apply_settings()
	audio.click()
	screens.sync()


func _on_action(name: String) -> void:
	audio.click()
	match name:
		"launch":
			if state == "title":
				start_mission()
		"resume":
			resume()
		"retry":
			retry()
		"restart":
			restart()
		"title":
			to_title()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if state == "play":
				pause()
			elif state == "paused":
				resume()
			elif state == "title":
				get_tree().quit()
			elif state == "debrief" or (state == "failed" and _fail_timer < 0.0):
				to_title()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if state == "play" and not OS.has_feature("selftest"):
				pause()


# ---------------------------------------------------------------- Main loop

func _process(delta: float) -> void:
	var raw := minf(0.05, maxf(0.0, delta / maxf(Engine.time_scale, 0.001)))
	input.poll()
	if bot.is_valid():
		bot.call(self, raw)
	tick(raw)


func tick(raw_dt: float) -> void:
	real_time += raw_dt
	var inp := controls
	if not inp.taps.is_empty() and state == "play" and controls_enabled:
		for t in inp.taps:
			pick_target_at(t)
	if state == "title" and inp.confirm:
		start_mission()
	elif state == "play" and inp.pause:
		pause()
	elif state == "paused" and inp.pause:
		resume()
	elif state == "failed" and _fail_timer < 0.0 and inp.confirm:
		retry()
	elif state == "debrief" and inp.confirm:
		restart()

	var live := state == "play" or state == "clear" or state == "failed"
	if _slow_t > 0.0:
		_slow_t -= raw_dt
		time_scale = _slow_scale
	else:
		time_scale = 1.0
	Engine.time_scale = time_scale if live else 1.0
	var vdt := 0.0
	if live:
		var dt := raw_dt * time_scale
		vdt = dt
		var steps := maxi(1, int(ceil(dt / Cfg.SIM_STEP - 1e-6)))
		var h := dt / steps
		for i in steps:
			_step(h)
			if i == 0:
				inp.consume_edges()
		if state == "play":
			mission_time += raw_dt
		if _fail_timer > 0.0:
			_fail_timer -= raw_dt
			if _fail_timer <= 0.0:
				_fail_timer = -1.0
				screens.set_fail_reason("%s — %s" % [_fail_info[0], _fail_info[1]])
				screens.show_screen("fail")
	elif state == "title" or state == "debrief":
		vdt = raw_dt
		fleet.update(raw_dt, real_time)
	else:
		inp.consume_edges()
	_render_frame(raw_dt, vdt)
	fps_avg = lerpf(fps_avg, 1.0 / maxf(raw_dt, 0.001), 0.05)


func _step(dt: float) -> void:
	time += dt
	mission.update(dt)
	fleet.update(dt, real_time)
	var p := player
	var inp: Controls = controls if controls_enabled else _neutral
	if p.alive:
		pc.update(p, inp, self, dt)
		if touch.boost_latched and (pc.boost_energy <= 0.01 or controls.brake or not controls_enabled):
			touch.unlatch_boost()
		if time - p.last_hit_time > Cfg.P_REGEN_DELAY and p.hp < p.max_hp:
			p.hp = minf(p.max_hp, p.hp + Cfg.P_REGEN_RATE * dt)
		if controls_enabled:
			_player_weapons(dt)
	elif p.wreck:
		_update_wreck(p, dt)
	_update_targeting(dt)
	if controls.order != 0 and controls_enabled and not formation:
		_order_wingmen(controls.order)
	for a in aircraft.duplicate():
		if a == p or a.frozen:
			continue
		if not a.alive:
			_update_wreck(a, dt)
			continue
		if a.brain:
			a.brain.update(a, self, dt)
		var gh := terrain.ground(a.pos.x, a.pos.z)
		if a.pos.y < gh + 2.0 or (a.kind != "scout" and terrain.hits_structure(a.pos, 3.0)):
			if a.invulnerable:
				a.pos.y = gh + 30.0
			else:
				var credit: bool = a.last_hit_by_player and time - a.last_hit_time < 4.0
				kill(a, a.last_hit_weapon if a.last_hit_weapon != "" else "missile", credit, "crash")
				continue
		if a.brain is AI.FighterBrain and (a.brain as AI.FighterBrain).mode == "flee" and a.pos.distance_to(p.pos) > 8500.0:
			despawn(a)
			continue
		a.whoosh_cooldown -= dt
		if p.alive and a.whoosh_cooldown <= 0.0 and a.pos.distance_squared_to(p.pos) < 170.0 * 170.0:
			a.whoosh_cooldown = 2.5
			audio.whoosh(0.35)
	weapons.update(dt, self)
	if state == "play":
		score.tick(dt)
	_enemy_launch_cd -= dt


func _order_wingmen(order: int) -> void:
	var o: String = ["cover", "scouts", "split"][order - 1]
	if o == wing_order:
		return
	wing_order = o
	hud.wing_order(o)
	audio.radio_blip()
	var lines := {"cover": "Copy. Covering you, lead.", "scouts": "Going after the scouts.", "split": "Splitting up. Four, take the scouts."}
	hud.radio("JOKER 2", lines[o], true)


func _player_weapons(dt: float) -> void:
	var p := player
	var inp := controls
	_gun_cd -= dt
	if inp.guns:
		var n := 0
		while _gun_cd <= 0.0 and n < 2:
			_gun_cd += 1.0 / Cfg.GUN_RATE
			n += 1
			var dir := p.fwd
			var t := target
			if t != null and t.targetable():
				var d := t.pos.distance_to(p.pos)
				var lead := (t.pos + t.vel * (d / (Cfg.GUN_SPEED + p.speed)) - p.pos).normalized()
				if d < 1500.0 and p.fwd.angle_to(lead) < Cfg.GUN_ASSIST_CONE:
					dir = MathX.rotate_toward(dir, lead, Cfg.GUN_ASSIST_MAX)
			dir += Vector3(randf_range(-Cfg.GUN_SPREAD, Cfg.GUN_SPREAD), randf_range(-Cfg.GUN_SPREAD, Cfg.GUN_SPREAD), randf_range(-Cfg.GUN_SPREAD, Cfg.GUN_SPREAD))
			dir = dir.normalized()
			_muzzle_side = -_muzzle_side
			var muzzle := p.pos + p.fwd * 9.0 + p.right * (1.1 * _muzzle_side) - p.up * 0.3
			weapons.fire_bullet(p, muzzle, dir, Cfg.GUN_SPEED, Cfg.GUN_DAMAGE, Cfg.GUN_LIFE)
			score.shots_fired += 1
		audio.gunshot(0.32)
	elif _gun_cd < 0.0:
		_gun_cd = 0.0
	if p.fx and p.fx.muzzle:
		p.fx.muzzle.emitting = inp.guns
	for i in 2:
		missile_rails[i] = maxf(0.0, missile_rails[i] - dt)
	if inp.missile:
		var idx := -1
		if missile_rails[_rail_idx] <= 0.0:
			idx = _rail_idx
		elif missile_rails[1 - _rail_idx] <= 0.0:
			idx = 1 - _rail_idx
		if idx >= 0:
			var t := target
			var tgt: Aircraft = t if locked and t != null and t.targetable() and not t.ecm else null
			var m := weapons.fire_missile(p, tgt, Cfg.PLAYER_MISSILE, Cfg.MSL_LAUNCH_BOOST)
			if m:
				m.pos += p.right * (-2.2 if idx == 0 else 2.2)
				missile_rails[idx] = Cfg.MSL_RELOAD
				_rail_idx = 1 - idx
				audio.missile_launch(0.5)
				score.missiles_fired += 1
				touch.vibrate(12)
				log_event("player missile " + ("at " + tgt.label if tgt else "dumbfire"))
		else:
			audio.dry()


func _target_score(a: Aircraft) -> float:
	var p := player
	var d := a.pos.distance_to(p.pos)
	var ang := p.fwd.angle_to(a.pos - p.pos)
	return ang * 3500.0 + d * 0.5 - (900.0 if a.mission_target else 0.0) - (900.0 if a.kind == "ace" else 0.0)


func _update_targeting(dt: float) -> void:
	var p := player
	if not p.alive:
		target = null
		lock_progress = 0.0
		locked = false
		return
	if target != null and not target.targetable():
		target = null
	var cands: Array[Aircraft] = []
	for a in aircraft:
		if a.team == "red" and a.targetable() and a.pos.distance_to(p.pos) < 15000.0:
			cands.append(a)
	if target == null and not cands.is_empty():
		var best := cands[0]
		var bs := INF
		for c in cands:
			var s := _target_score(c)
			if s < bs:
				bs = s
				best = c
		target = best
		lock_progress = 0.0
	if controls.target_next and controls_enabled and cands.size() > 1:
		var sorted := cands.duplicate()
		sorted.sort_custom(func(a: Aircraft, b: Aircraft) -> bool: return _target_score(a) < _target_score(b))
		var i := sorted.find(target)
		target = sorted[(i + 1) % sorted.size()]
		lock_progress = 0.0
		audio.click()
	var t := target
	var in_cone := false
	if t != null and not t.ecm:
		var d := t.pos.distance_to(p.pos)
		in_cone = d < Cfg.MSL_LOCK_RANGE and p.fwd.angle_to(t.pos - p.pos) < Cfg.MSL_LOCK_CONE
	var lock_time := Cfg.MSL_LOCK_TIME * (1.0 + maxf(0.0, (p.speed - 260.0) / 150.0)) * lock_penalty
	lock_progress = minf(1.0, lock_progress + dt / lock_time) if in_cone else maxf(0.0, lock_progress - dt * 3.0)
	var was := locked
	locked = lock_progress >= 1.0
	if locked and not was:
		touch.vibrate(8)


## Touch: select the enemy nearest a tap on screen.
func pick_target_at(pt: Vector2) -> bool:
	var best: Aircraft = null
	var bd := 72.0 * 72.0
	for a in aircraft:
		if a.team != "red" or not a.targetable():
			continue
		if rig.is_position_behind(a.pos):
			continue
		var s := rig.unproject_position(a.pos)
		var d2 := s.distance_squared_to(pt)
		if d2 < bd:
			bd = d2
			best = a
	if best == null:
		return false
	if best != target:
		target = best
		lock_progress = 0.0
		audio.click()
		touch.vibrate(6)
	return true


# ---------------------------------------------------------------- Combat events

func on_bullet_hit(a: Aircraft, owner: Aircraft, dmg: float, pos: Vector3) -> void:
	var by_player := owner == player
	if by_player:
		score.hit()
		if real_time - _last_hit_sound > 0.06:
			_last_hit_sound = real_time
			audio.hit_tick(0.12)
	fx.hit_sparks(pos)
	_damage(a, dmg, "gun", by_player)


func on_missile_hit(a: Aircraft, m: Missile) -> void:
	var by_player := m.owner == player
	fx.explosion(m.pos, 0.6)
	audio.explosion(_vol_of(m.pos) * 0.8, false)
	if by_player:
		score.missiles_hit += 1
		score.hit()
	_damage(a, m.damage, "missile", by_player)


func on_missile_ground(m: Missile) -> void:
	fx.explosion(m.pos, 0.5)
	if m.pos.y < 3.0:
		fx.splash(m.pos, 0.7)
	audio.explosion(_vol_of(m.pos) * 0.6, false)


func on_missile_jammed(_t: Aircraft, m: Missile) -> void:
	fx.hit_sparks(m.pos, true)
	if m.owner == player and real_time - _last_popup_jam > 2.0:
		_last_popup_jam = real_time
		hud.popup([{"text": "MISSILE JAMMED — USE GUNS", "kind": "bad"}])


func _damage(a: Aircraft, amount: float, weapon: String, by_player: bool) -> void:
	if not a.alive:
		return
	if a == player:
		_player_damaged(amount, weapon)
		return
	if a.invulnerable:
		return
	var before := a.hp
	a.hp -= amount * a.armor
	# Wingmen can wear a target down to a floor but never finish it (or heal it).
	if not by_player and a.hp_floor_from_others > 0.0:
		a.hp = maxf(a.hp, minf(before, a.hp_floor_from_others * a.max_hp))
	if weapon == "missile":
		log_event("hit %s %s %d hp=%d%s" % [a.label, weapon, int(before - a.hp), int(a.hp), "" if by_player else " (other)"])
	a.last_hit_time = time
	a.last_hit_weapon = weapon
	if by_player:
		a.last_hit_by_player = true
		a.last_hit_dist = a.pos.distance_to(player.pos)
	if a.brain and a.brain.has_method("on_hit"):
		a.brain.on_hit(a, self, weapon)
	mission.on_damaged(a)
	if a.hp <= 0.0:
		kill(a, weapon, by_player)


func _player_damaged(amount: float, weapon: String) -> void:
	var p := player
	if not controls_enabled and state != "play":
		return
	if god:
		amount = 0.0
	p.hp -= amount
	p.last_hit_time = time
	score.damaged(amount)
	audio.player_hit(weapon == "missile")
	touch.vibrate([70, 40, 90] if weapon == "missile" else 18)
	rig.add_trauma(0.75 if weapon == "missile" else 0.16)
	_vignette = maxf(_vignette, 1.0 if weapon == "missile" else 0.4)
	fx.hit_sparks(p.pos + p.right * randf_range(-4.0, 4.0), weapon == "missile")
	if weapon == "missile":
		fx.explosion(p.pos - p.fwd * 6.0, 0.4)
	if p.hp <= 0.0:
		_player_destroyed()


func _player_destroyed() -> void:
	var p := player
	p.alive = false
	p.wreck = true
	p.wreck_time = 0.0
	p.wreck_vel = p.vel * 0.6
	p.wreck_spin = MathX.rand_sign() * 2.5
	fx.explosion(p.pos, 1.6)
	fx.burning_debris(p.pos, p.vel, 4)
	audio.explosion(0.9, true)
	rig.add_trauma(1.0)
	fail("AIRCRAFT DESTROYED", "Joker 1 is down.")


func log_event(e: String) -> void:
	var line := "%.1f %s" % [time, e]
	events.append(line)
	if events.size() > 300:
		events.pop_front()
	if OS.has_feature("selftest") or OS.is_debug_build():
		print("[event] ", line)


func kill(a: Aircraft, weapon: String, by_player: bool, cause := "shot") -> void:
	if not a.alive:
		return
	log_event("kill %s by %s %s %s alt=%d" % [a.label, "player" if by_player else "other", weapon, cause, int(a.pos.y)])
	a.alive = false
	a.wreck = true
	a.wreck_time = 0.0
	a.wreck_vel = a.vel * 0.65
	a.wreck_spin = MathX.rand_sign() * randf_range(1.5, 4.0)
	var big := a.kind == "scout" or a.kind == "ace"
	fx.explosion(a.pos, 2.3 if big else 1.3)
	fx.burning_debris(a.pos, a.vel, 5 if big else 3)
	audio.explosion(_vol_of(a.pos), true)
	var d := a.pos.distance_to(player.pos)
	rig.add_trauma(0.4 if d < 500.0 else (0.15 if d < 1500.0 else 0.04))
	if target == a:
		target = null
		lock_progress = 0.0
	if by_player:
		var base := Cfg.S_SCOUT if a.kind == "scout" else (Cfg.S_ACE if a.kind == "ace" else -1)
		var label := "SCOUT DOWN" if a.kind == "scout" else ("ACE DESTROYED" if a.kind == "ace" else "")
		var lines := score.kill(weapon, a.last_hit_dist if a.last_hit_dist > 0.0 else d, base, label)
		hud.popup(lines)
		audio.combo_tick(score.combo)
		touch.vibrate([30, 30, 60] if big else 22)
	if a.kind == "ace":
		mission.on_ace_killed()
	mission.on_kill(a, by_player, weapon)


func _update_wreck(a: Aircraft, dt: float) -> void:
	a.wreck_time += dt
	a.wreck_vel.y -= 32.0 * dt
	a.wreck_vel *= exp(-0.3 * dt)
	a.pos += a.wreck_vel * dt
	a.quat = (a.quat * Quaternion(Vector3(0, 0, 1), a.wreck_spin * dt) * Quaternion(Vector3(1, 0, 0), -0.35 * dt)).normalized()
	a.update_basis()
	a.vel = a.wreck_vel
	a.throttle = 0.0
	var gh := terrain.ground(a.pos.x, a.pos.z)
	if a.pos.y <= gh + 1.0 or a.wreck_time > 9.0:
		if a.pos.y <= gh + 3.0:
			if gh <= 0.5:
				fx.splash(a.pos, 1.4)
			else:
				fx.explosion(a.pos, 0.8)
		if a == player:
			a.wreck = false
			a.hidden = true
		else:
			despawn(a)


func on_player_crash(kind: String) -> void:
	var dmg := 45.0 if kind == "structure" else 34.0
	hud.popup([{"text": "WATER IMPACT" if kind == "sea" else ("COLLISION" if kind == "structure" else "TERRAIN IMPACT"), "kind": "bad"}])
	if kind == "sea":
		fx.splash(player.pos, 1.2)
	else:
		fx.explosion(player.pos, 0.5)
	_player_damaged(dmg, "missile")


func on_player_barrel_roll() -> void:
	var p := player
	audio.whoosh(0.25)
	var evaded := 0
	for m in weapons.incoming_missiles(p):
		if m.pos.distance_to(p.pos) < 1100.0 and randf() < 0.8:
			weapons.spoof(m, p)
			evaded += 1
	if evaded > 0:
		weapons.drop_flares(p)
		hud.popup([{"text": "EVADED x%d" % evaded if evaded > 1 else "EVADED", "kind": "gold"}])


func on_ai_gun_shot(a: Aircraft) -> void:
	if real_time - _last_enemy_gun_sound < 0.07:
		return
	var d := a.pos.distance_to(player.pos)
	if d > 1500.0:
		return
	_last_enemy_gun_sound = real_time
	audio.enemy_gun((1.0 - d / 1500.0) * 0.22)


func can_launch_at(t: Aircraft) -> bool:
	if t == player:
		return controls_enabled and _enemy_launch_cd <= 0.0 and weapons.incoming_missiles(t).size() < 2
	return weapons.active_red_missiles() < 5


func fire_ai_missile(a: Aircraft, t: Aircraft) -> void:
	var m := weapons.fire_missile(a, t, Cfg.ENEMY_MISSILE if a.team == "red" else Cfg.PLAYER_MISSILE, 30.0)
	if m == null:
		return
	audio.missile_launch(_vol_of(a.pos) * 0.5)
	if t == player:
		_enemy_launch_cd = 2.5
		if real_time - _last_missile_radio > 14.0 and not hud.radio_busy():
			_last_missile_radio = real_time
			hud.radio("JOKER 2", "Missile on you, lead! Break!")


func on_flares(a: Aircraft) -> void:
	fx.flare_burst(a.pos)
	if a.pos.distance_to(player.pos) < 1500.0:
		audio.flare()


func on_scout_escaped(a: Aircraft) -> void:
	if a == mission.lead and a.alive:
		fail("LEAD SCOUT ESCAPED", "It crossed the boundary with the fleet's position.")


func on_ace_forced_low(_a: Aircraft) -> void:
	log_event("ace forced low")
	mission.on_ace_forced_low()


func on_ace_recovered(_a: Aircraft) -> void:
	hud.popup([{"text": "ACE RECOVERED", "kind": "bad"}])


func on_ace_enraged(_a: Aircraft) -> void:
	mission.on_ace_enraged()


func on_ace_dodge(_a: Aircraft) -> void:
	log_event("ace dodge")
	if real_time - _last_dodge_popup > 2.5:
		_last_dodge_popup = real_time
		hud.popup([{"text": "ACE DODGED — PRESSURE HIM LOW", "kind": "bad"}])


func _vol_of(pos: Vector3) -> float:
	var d := pos.distance_to(rig.global_position)
	return clampf(1.0 / (1.0 + d / 450.0), 0.0, 1.0)


# ---------------------------------------------------------------- Render

func _render_frame(raw_dt: float, vdt: float) -> void:
	var paused := state == "paused"
	fx.update(vdt)
	for a in aircraft:
		a.sync_mesh(real_time)
		if a.fx:
			a.fx.follow(a, not paused)
		if paused or a.frozen or a.hidden:
			continue
		# Wingtip vapour under load.
		if a.alive:
			var s := clampf((a.g_load - 12.0) / 18.0, 0.0, 1.0)
			var span: float = SPANS[a.kind]
			for k in 2:
				var side := -1.0 if k == 0 else 1.0
				trails.push(a.vapor_trails[k], a.pos + a.right * (side * span) - a.fwd * 2.0, s)
	if not paused:
		trails.update_mesh(rig.global_position)
	weapons.render()
	rig.update_rig(0.0 if paused else raw_dt, self)
	world.update(vdt, real_time, rig)
	var cloud := world.cloud_density_at(rig.global_position)
	hud.cloud_fog.color.a = clampf(cloud * 1.6, 0.0, 0.92)
	_vignette = maxf(0.0, _vignette - raw_dt * 1.8)
	var p := player
	var low_hull := 0.25 + 0.15 * sin(real_time * 6.0) if p.alive and state == "play" and p.hp < p.max_hp * 0.3 else 0.0
	hud.vignette.modulate.a = maxf(_vignette, low_hull)
	hud.update(0.0 if paused else raw_dt, self)
	# Audio.
	var active := (state == "play" or state == "clear") and p.alive and not p.hidden
	audio.update_engine(p.speed, p.throttle, pc.boosting, active, raw_dt)
	var t := target
	var lock_state := "none"
	if controls_enabled and t != null and not t.ecm:
		lock_state = "locked" if locked else ("locking" if lock_progress > 0.0 else "none")
	audio.set_lock_tone(lock_state)
	var close := false
	var incoming := weapons.incoming_missiles(p) if controls_enabled else ([] as Array[Missile])
	for m in incoming:
		if m.pos.distance_to(p.pos) < 900.0:
			close = true
	audio.set_missile_alert((2 if close else 1) if not incoming.is_empty() else 0)
	_update_touch_ui(raw_dt)
	_adapt_resolution(raw_dt)


func _update_touch_ui(dt: float) -> void:
	if not touch.enabled:
		touch.visible = false
		return
	var p := player
	var tg: Aircraft = target if target != null and target.targetable() else null
	var gun_hot := false
	if tg != null and p.alive:
		var d := tg.pos.distance_to(p.pos)
		if d < 1300.0:
			var lead := (tg.pos + tg.vel * (d / (Cfg.GUN_SPEED + p.speed)) - p.pos).normalized()
			gun_hot = p.fwd.angle_to(lead) < 0.035
	var evade := false
	for m in weapons.incoming_missiles(p):
		if m.pos.distance_to(p.pos) < 1300.0:
			evade = true
	touch.render({
		"live": state == "play",
		"controls": controls_enabled and not cinematic,
		"lock": lock_progress if tg != null and not tg.ecm else 0.0,
		"locked": locked and tg != null and not tg.ecm,
		"ecm": tg != null and tg.ecm,
		"rails": [_rail_fill(0), _rail_fill(1)],
		"boost": pc.boost_energy,
		"boosting": pc.boosting,
		"gun_hot": gun_hot,
		"evade": evade and controls_enabled,
		"orders": wing_order if not formation and hud.wing_order_shown != "" else "",
		"teach": touch_teach,
		"hint": "TAP TO LAUNCH" if skippable and state == "play" else "",
	}, dt)


func _rail_fill(i: int) -> float:
	return 1.0 if missile_rails[i] <= 0.0 else 1.0 - missile_rails[i] / Cfg.MSL_RELOAD


## Hold frame rate by trading render resolution (mainly for phones).
func _adapt_resolution(dt: float) -> void:
	if state == "paused" or state == "debrief" or dt > 0.25 or dt <= 0.0:
		return
	_perf_acc += dt
	_perf_n += 1
	if _perf_acc < 2.0:
		return
	var fps := _perf_n / _perf_acc
	_perf_acc = 0.0
	_perf_n = 0
	if fps < 48.0 and _render_scale > 0.7:
		_render_scale = maxf(0.7, _render_scale * 0.85)
		_perf_hold_until = real_time + 20.0
		_perf_good = 0
		_apply_render_scale()
		log_event("render scale down %.2f (fps %d)" % [_render_scale, int(fps)])
	elif fps > 57.0 and _render_scale < _render_scale_max and real_time > _perf_hold_until:
		_perf_good += 1
		if _perf_good >= 3:
			_render_scale = minf(_render_scale_max, _render_scale * 1.12)
			_perf_good = 0
			_apply_render_scale()
	else:
		_perf_good = 0


var render_scale: float:
	get:
		return _render_scale
