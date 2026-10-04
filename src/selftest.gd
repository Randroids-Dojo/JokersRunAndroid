class_name SelfTest
extends Node
## Automated on-device verification (export feature "selftest", or `-- --selftest[=mode]` on
## desktop). Drives the real input pipeline with synthetic multi-touch events, checks the
## game's reactions, then lets the test bot fly the mission. Results go to the log as
## "SELFTEST PASS/FAIL ..." lines and screenshots to user://shots/.
## Modes: "touch" (controls only), "full" (controls + whole mission), "cp:<name>" (one
## checkpoint onward), "soak" (bot flies for performance numbers).

var g: Game
var mode := "full"
var speed := 1.0
var _fails := 0
var _passes := 0
var _bot := Bot.new()
var _shot_i := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--selftest="):
			mode = a.substr(11)
		elif a.begins_with("--speed="):
			speed = float(a.substr(8))
	# On a debuggable device build the mode can be set without rebuilding:
	#   adb shell run-as com.randroids.jokersrun sh -c 'echo diag > files/selftest_mode.txt'
	if FileAccess.file_exists("user://selftest_mode.txt"):
		mode = FileAccess.get_file_as_string("user://selftest_mode.txt").strip_edges()
	DirAccess.make_dir_recursive_absolute("user://shots")
	_log("start mode=%s speed=%.1f os=%s renderer=%s" % [mode, speed, OS.get_name(), RenderingServer.get_current_rendering_method()])
	_run.call_deferred()


func _log(s: String) -> void:
	print("SELFTEST ", s)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_passes += 1
		_log("PASS %s %s" % [name, detail])
	else:
		_fails += 1
		_log("FAIL %s %s" % [name, detail])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _wait_until(test: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not test.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			return false
		await get_tree().process_frame
	return true


var _label: Label


## Big on-screen caption so recorded device video can be matched to diag steps.
func caption(text: String) -> void:
	if _label == null:
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_label = Label.new()
		_label.add_theme_font_size_override("font_size", 22)
		_label.add_theme_color_override("font_color", Color(1, 0, 1))
		_label.position = Vector2(300, 4)
		layer.add_child(_label)
	_label.text = text
	_log("caption " + text)


## Pixel statistics of the current frame: share of flat light-grey (the device "white
## blob" colour), saturated green, and the mean colour.
func frame_stats(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	var grey := 0
	var green := 0
	var sum := Vector3.ZERO
	for y in range(0, h, 9):
		for x in range(0, w, 9):
			var c := img.get_pixel(x, y)
			n += 1
			sum += Vector3(c.r, c.g, c.b)
			if absf(c.r - 0.898) < 0.025 and absf(c.g - 0.902) < 0.025 and absf(c.b - 0.902) < 0.025:
				grey += 1
			if c.g > 0.8 and c.r < 0.45 and c.b < 0.25:
				green += 1
	var m := sum / maxf(n, 1)
	_log("stats %s grey=%.3f green=%.3f mean=(%.2f,%.2f,%.2f)" % [tag, float(grey) / n, float(green) / n, m.x, m.y, m.z])


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_i += 1
	var path := "user://shots/%02d_%s.png" % [_shot_i, name]
	img.save_png(path)
	_log("shot %s" % ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- Synthetic touch

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _to_window(pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _to_window(pos)
	e.relative = rel
	Input.parse_input_event(e)


## Synthetic events enter at window (screen pixel) coordinates, like real touches.
func _to_window(p: Vector2) -> Vector2:
	var vp := get_viewport()
	return vp.get_final_transform() * p


## Index 0 so the engine also emulates a mouse click (that is how real taps reach the GUI).
func _tap(pos: Vector2, hold := 0.06, index := 0) -> void:
	_touch(index, pos, true)
	await _wait(hold)
	_touch(index, pos, false)
	await get_tree().process_frame


func _btn_center(name: String) -> Vector2:
	var b: Dictionary = g.touch._btn[name]
	return (b.rect as Rect2).get_center() if b.has("rect") else b.c


func _screen_button(screen: Control, label: String) -> Control:
	for n in screen.find_children("*", "", true, false):
		if n is Screens.Btn and (n as Screens.Btn).text.begins_with(label):
			return n
	return null


func _press_ui(screen: Control, label: String) -> bool:
	var b := _screen_button(screen, label)
	if b == null:
		_log("no button " + label)
		return false
	var c := b.get_global_rect().get_center()
	await _tap(c, 0.08)
	return true


# ---------------------------------------------------------------- Sequences

func _run() -> void:
	g = get_parent() as Game
	await _wait(2.0)
	_check("title_state", g.state == "title", g.state)
	await shot("title")
	g.touch.set_enabled(true)
	await _wait(0.5)
	await shot("title_touch")
	if mode.begins_with("cp:"):
		await _checkpoint_run(mode.substr(3))
	elif mode == "soak":
		await _soak()
	elif mode == "shots":
		await _reference_shots()
	elif mode == "screens":
		await _screen_shots()
	elif mode == "diag":
		await _diag()
	elif mode == "matrix":
		await _matrix()
	elif mode == "matrix2":
		await _matrix2()
	else:
		await _touch_suite()
		if mode == "full":
			await _mission_run()
	_log("DONE passes=%d fails=%d fps=%.1f scale=%.2f" % [_passes, _fails, g.fps_avg, g.get_viewport().scaling_3d_scale])
	if OS.has_feature("selftest_quit") or "--quit" in OS.get_cmdline_user_args():
		get_tree().quit(1 if _fails > 0 else 0)


func _touch_suite() -> void:
	# Title -> LAUNCH through the GUI (emulated mouse from touch).
	var ok := await _press_ui(g.screens.title, "LAUNCH")
	await _wait(0.3)
	_check("launch_button", ok and g.state == "play", g.state)
	await _wait(1.6)
	await shot("opening")
	# The deck shot is skippable with a tap.
	_check("skippable_hint", g.skippable, "")
	await _tap(Vector2(g._view_size.x * 0.6, g._view_size.y * 0.4))
	var launched := await _wait_until(func() -> bool: return g.controls_enabled, 6.0)
	_check("tap_skips_to_launch", launched, "")
	await _wait(0.8)
	await shot("launched")
	# Stick: touch on the left half and drag up and right.
	var base := Vector2(g._view_size.x * 0.18, g._view_size.y * 0.62)
	_touch(0, base, true)
	await get_tree().process_frame
	for i in 10:
		var p := base + Vector2(3.0 * i, -6.0 * i)
		_drag(0, p, Vector2(3, -6))
		await get_tree().process_frame
	await _wait(0.2)
	_check("stick_y", g.touch.y > 0.5, "y=%.2f" % g.touch.y)
	_check("stick_x", g.touch.x > 0.2, "x=%.2f" % g.touch.x)
	_check("assist_turn", g.controls.assist and g.controls.turn > 0.2, "turn=%.2f" % g.controls.turn)
	_check("pitch_from_stick", g.controls.pitch > 0.5, "pitch=%.2f" % g.controls.pitch)
	await shot("stick")
	# Multi-touch: hold GUN with a second finger while steering.
	var shots0 := g.score.shots_fired
	_touch(1, _btn_center("gun"), true)
	await _wait(0.5)
	_check("gun_held_multitouch", g.controls.guns and g.score.shots_fired > shots0, "shots=%d" % (g.score.shots_fired - shots0))
	await shot("guns")
	_touch(1, _btn_center("gun"), false)
	_touch(0, base + Vector2(27, -54), false)
	await _wait(0.3)
	_check("stick_release", absf(g.touch.x) < 0.01 and absf(g.touch.y) < 0.01, "")
	# Boost: a tap latches, another tap cancels.
	await _tap(_btn_center("boost"))
	await _wait(0.3)
	_check("boost_latch", g.touch.boost_latched and g.pc.boosting, "")
	await _tap(_btn_center("boost"))
	await _wait(0.2)
	_check("boost_unlatch", not g.touch.boost_latched, "")
	# Brake held.
	_touch(2, _btn_center("brake"), true)
	await _wait(0.3)
	_check("brake_hold", g.controls.brake and g.pc.braking, "")
	_touch(2, _btn_center("brake"), false)
	await _wait(0.2)
	# Roll button.
	await _tap(_btn_center("roll"))
	await _wait(0.1)
	_check("barrel_roll", g.pc.roll_time > 0.0 or g.pc.last_roll_at > g.time - 1.0, "")
	# Missile button fires a (dumbfire) missile.
	var m0 := g.score.missiles_fired
	await _tap(_btn_center("msl"))
	await _wait(0.2)
	_check("missile_fire", g.score.missiles_fired > m0, "")
	# Pause button, then resume through the menu.
	await _tap(_btn_center("pause"))
	await _wait(0.4)
	_check("pause_button", g.state == "paused" and get_tree().paused, g.state)
	await shot("pause")
	await _press_ui(g.screens.pause, "RESUME")
	await _wait(0.3)
	_check("resume", g.state == "play" and not get_tree().paused, g.state)
	# Tilt steering path (sensor-dependent; only checks it can be toggled).
	g._on_toggle("tilt")
	_log("tilt available=%s" % str(g.settings.tilt))
	if g.settings.tilt:
		g._on_toggle("tilt")


func _mission_run() -> void:
	g.god = true
	g.bot = func(game: Game, dt: float) -> void: _bot.drive(game, dt)
	var last_phase := ""
	var phase_t0 := Time.get_ticks_msec()
	var shots_taken := {}
	var t0 := Time.get_ticks_msec()
	var perf_t := Time.get_ticks_msec()
	var frames := 0
	while g.state != "debrief":
		await get_tree().process_frame
		frames += 1
		if Time.get_ticks_msec() - perf_t >= 10000:
			_log("perf fps=%.1f scale3d=%.2f aircraft=%d" % [frames * 1000.0 / (Time.get_ticks_msec() - perf_t), get_viewport().scaling_3d_scale, g.aircraft.size()])
			perf_t = Time.get_ticks_msec()
			frames = 0
		var ph := g.mission.phase
		if ph != last_phase:
			_log("phase '%s' at %.0fs score=%d" % [ph, (Time.get_ticks_msec() - t0) / 1000.0, int(g.score.total)])
			last_phase = ph
			phase_t0 = Time.get_ticks_msec()
		# Screenshots a few seconds into each phase.
		if not shots_taken.has(ph) and Time.get_ticks_msec() - phase_t0 > 6000:
			shots_taken[ph] = true
			await shot("phase_" + ph.get_slice("·", 0).strip_edges().replace(" ", "_").to_lower())
		# Keep the run bounded: after a while in one phase, help the bot finish its target.
		if Time.get_ticks_msec() - phase_t0 > 90000 and g.target and g.target.alive and g.controls_enabled:
			_log("assist kill " + g.target.label)
			g.kill(g.target, "missile", true)
			phase_t0 = Time.get_ticks_msec() - 60000
		if g.state == "failed":
			_check("no_fail", false, g._fail_info[0])
			await _wait(3.5)
			g.retry()
		if Time.get_ticks_msec() - t0 > 30 * 60 * 1000:
			_check("mission_timeout", false, ph)
			return
		if g.state == "clear" and not shots_taken.has("clear"):
			shots_taken["clear"] = true
			await _wait(1.0)
			await shot("mission_clear")
		if g.hud._card.visible and not shots_taken.has("card"):
			shots_taken["card"] = true
			await _wait(2.5)
			await shot("next_mission_card")
	g.bot = Callable()
	await _wait(1.0)
	await shot("debrief")
	_check("mission_complete", g.state == "debrief", "score=%d rank=%s time=%.0fs" % [int(g.score.total), g.score.rank(), (Time.get_ticks_msec() - t0) / 1000.0])


func _checkpoint_run(cp: String) -> void:
	g.god = true
	g.start_mission(cp)
	g.bot = func(game: Game, dt: float) -> void: _bot.drive(game, dt)
	await _wait(8.0)
	await shot("cp_" + cp)
	await _mission_run()


func _soak() -> void:
	g.god = true
	g.start_mission("scouts")
	g.bot = func(game: Game, dt: float) -> void: _bot.drive(game, dt)
	for i in 12:
		await _wait(5.0)
		_log("soak t=%ds fps=%.1f scale=%.2f aircraft=%d" % [(i + 1) * 5, g.fps_avg, g.get_viewport().scaling_3d_scale, g.aircraft.size()])
	await shot("soak")


## Same sequence as tools/web_shots.mjs, for side-by-side comparison with the web build.
func _reference_shots() -> void:
	for cp in ["launch", "training", "scouts", "chase", "ace", "final"]:
		g.god = true
		g.start_mission(cp)
		await _wait(2.5 if cp == "launch" else 8.0)
		await shot("cp_" + cp)
		if cp == "launch":
			g.bot = func(game: Game, dt: float) -> void: _bot.drive(game, dt)
			await _wait(9.0)
			await shot("cp_launch_fly")
			g.bot = Callable()


## Same sequence as tools/web_screens.mjs.
func _screen_shots() -> void:
	g.start_mission("training")
	await _wait(3.0)
	g.pause()
	await _wait(0.5)
	await shot("pause")
	g.resume()
	await _wait(0.5)
	g.fail("AIRCRAFT DESTROYED", "Joker 1 is down.")
	await _wait(1.2)
	await shot("fail_banner")
	await _wait(2.5)
	await shot("fail")
	g.score.total = 123450
	g.show_debrief()
	await _wait(0.8)
	await shot("debrief")


## Fixed camera views of the transparent effects (storm, wake, cloud field) with MSAA on and
## off, for diagnosing GPU-specific rendering problems.
func _diag() -> void:
	_log("gpu name=%s vendor=%s api=%s method=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_method()])
	# 1. The title orbit, where the device showed white walls.
	for i in 8:
		caption("DIAG title %d" % i)
		await _wait(1.0)
		await frame_stats("title%d" % i)
	g.world._lightning_t = 1e9
	var c := g.fleet.carrier_pos()
	var cl: Array = g.world.clouds.clusters[0]
	var views := {
		"storm": [c + Vector3(0, 120, 300), Vector3(-9000, 1800, 26000)],
		"wake": [c + Vector3(260, 140, 1100), c + Vector3(0, 0, 400)],
		"clouds": [(cl[0] as Vector3) + Vector3(0, 300, 2600), cl[0]],
		"terrain": [Vector3(3200, 700, 2600), Vector3(9000, 200, -1500)],
		"coast": [c + Vector3(-400, 95, 500), c + Vector3(6000, 300, -3000)],
	}
	var vp := get_viewport()
	for msaa in [Viewport.MSAA_2X, Viewport.MSAA_DISABLED]:
		vp.msaa_3d = msaa
		for name in views:
			var v: Array = views[name]
			g.rig.play(func(_t: float) -> Dictionary: return {"pos": v[0], "look": v[1], "fov": 60.0})
			caption("DIAG %s msaa%d" % [name, msaa])
			await _wait(2.5)
			await frame_stats("%s_msaa%d" % [name, msaa])
			await shot("diag_%s_msaa%d" % [name, msaa])
	vp.msaa_3d = Viewport.MSAA_2X
	for hide in ["terrain", "clouds", "storm", "ocean"]:
		var node: Node3D = g.terrain if hide == "terrain" else g.world.get(hide)
		node.visible = false
		var v2: Array = views["coast"]
		g.rig.play(func(_t: float) -> Dictionary: return {"pos": v2[0], "look": v2[1], "fov": 60.0})
		caption("DIAG coast without %s" % hide)
		await _wait(2.5)
		await frame_stats("coast_no_%s" % hide)
		node.visible = true
	# 2. Fly the opening the way a player would (bot), sampling the frames.
	caption("DIAG flight")
	g.god = true
	g.start_mission("launch")
	g.bot = func(game: Game, dt: float) -> void: _bot.drive(game, dt)
	await _wait(5.0)
	g.controls.skip = true
	for i in 40:
		await _wait(1.5)
		caption("DIAG flight %d" % i)
		await frame_stats("flight%d" % i)
	g.bot = Callable()


## A row of identical test objects, one material/feature variant each, in front of a fixed
## camera over open sea. Used to find which feature a device GPU mis-renders.
func _matrix() -> void:
	_log("gpu name=%s vendor=%s api=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	var root := Node3D.new()
	g.add_child(root)
	g.screens.show_screen("")
	var cam := Vector3(0, 100, 5105)
	var mats: Array = []
	var white := Color(1, 1, 1, 0.75)
	mats.append(["basic_mix_tm", Models.basic(white, false, true)])
	mats.append(["basic_add", Models.basic(Color("ff9a3c", 0.9), true, false)])
	for f in ["basic_novary", "basic_depth", "basic_vary_opaque", "basic_cullback"]:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/diag/%s.gdshader" % f)
		m.set_shader_parameter("color", white)
		mats.append([f, m])
	var std := StandardMaterial3D.new()
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.albedo_color = white
	mats.append(["std_transparent", std])
	mats.append(["flat_opaque", Geo.material()])
	var x := -132.0
	for i in mats.size():
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(14, 14, 14)
		mi.mesh = box
		mi.material_override = mats[i][1]
		root.add_child(mi)
		mi.global_position = Vector3(x, 100, 5000)
		_log("matrix slot %d x=%d %s" % [i, int(x), mats[i][0]])
		x += 24.0
	# Wake mesh stood upright, a burner, a particle emitter.
	var wk := Models.wake(10, 30)
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(wk)
	holder.global_position = Vector3(x, 85, 5000)
	holder.rotation = Vector3(PI / 2.0, 0, 0)
	_log("matrix slot %d x=%d wake_mesh" % [mats.size(), int(x)])
	x += 24.0
	var jet := Models.aircraft("enemy")
	root.add_child(jet.root)
	(jet.root as Node3D).global_position = Vector3(x, 100, 5000)
	(jet.root as Node3D).rotation = Vector3(0, PI / 2.0, 0)
	for b in jet.burners:
		(b as Node3D).scale = Vector3(1, 1, 4)
	_log("matrix slot %d x=%d jet_with_burners" % [mats.size() + 1, int(x)])
	x += 24.0
	var em := Fx.emitter(false, 40, 2.0, 4.0, 10.0, Color(0.95, 0.95, 0.95, 0.8), Color(0.9, 0.9, 0.9, 0.0), false)
	em.initial_velocity_max = 2.0
	root.add_child(em)
	em.global_position = Vector3(x, 100, 5000)
	em.emitting = true
	_log("matrix slot %d x=%d particles_mix" % [mats.size() + 2, int(x)])
	g.rig.play(func(_t: float) -> Dictionary: return {"pos": cam, "look": Vector3(0, 100, 5000), "fov": 75.0})
	for msaa in [Viewport.MSAA_2X, Viewport.MSAA_DISABLED]:
		get_viewport().msaa_3d = msaa
		caption("MATRIX msaa%d" % msaa)
		await _wait(6.0)
		await frame_stats("matrix_msaa%d" % msaa)
		await shot("matrix_msaa%d" % msaa)
	get_viewport().msaa_3d = Viewport.MSAA_2X


## Many transparent objects whose transforms change every frame (wakes, burners, particles),
## to check whether moving transparent instances are mis-transformed on a device.
func _matrix2() -> void:
	_log("gpu name=%s method=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	g.screens.show_screen("")
	var root := Node3D.new()
	g.add_child(root)
	var movers: Array = []
	for i in 40:
		var holder := Node3D.new()
		root.add_child(holder)
		var wk := Models.wake(6, 20)
		holder.add_child(wk)
		movers.append(holder)
	var burners: Array = []
	for i in 10:
		var jet := Models.aircraft("enemy")
		root.add_child(jet.root)
		burners.append(jet)
	var cam := Vector3(0, 100, 5105)
	g.rig.play(func(_t: float) -> Dictionary: return {"pos": cam, "look": Vector3(0, 100, 5000), "fov": 75.0})
	caption("MATRIX2 moving transparents")
	var t := 0.0
	for frame in 600:
		t += get_process_delta_time()
		for i in movers.size():
			var m: Node3D = movers[i]
			m.global_position = Vector3(-120 + (i % 10) * 26, 70 + (i / 10) * 18 + sin(t * 2.0 + i) * 3.0, 5000)
			m.rotation = Vector3(PI / 2.0 + sin(t + i) * 0.3, 0, 0)
		for i in burners.size():
			var j: Dictionary = burners[i]
			(j.root as Node3D).global_position = Vector3(-110 + i * 24, 140 + cos(t * 1.5 + i) * 4.0, 5000)
			(j.root as Node3D).rotation = Vector3(0, PI / 2.0 + t * 0.5, 0)
			for b in j.burners:
				(b as Node3D).scale = Vector3(1, 1, 2.0 + sin(t * 9.0 + i) * 1.5)
		if frame % 60 == 0:
			await frame_stats("matrix2_%d" % (frame / 60))
		await get_tree().process_frame
