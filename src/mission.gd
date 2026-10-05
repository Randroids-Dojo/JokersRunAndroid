class_name Mission
extends RefCounted
## Mission 1 "Joker's Run": the scripted campaign level (port of mission.ts). Sequences are
## coroutines that wait on the sim clock; cancel() bumps the generation so every pending wait
## returns false and its coroutine unwinds.

signal _stepped

const RADIUS := 58.0
const CHECKPOINTS := ["launch", "training", "scouts", "chase", "ace", "final"]

var g: Game
var gen := 0
var checkpoint := "launch"
var phase := ""
## Sim-time clock used by _sleep().
var clock := 0.0
var per_frame: Callable = Callable()

## Each ring: {pos, normal, label, kind, obj, prev_side, done}
var rings: Array = []
var ring_idx := 0
var ring_root := Node3D.new()
var tutorial_clock := 0.0
var tutorial_running := false

var scouts: Array[Aircraft] = []
var lead: Aircraft = null
var last: Aircraft = null
var ace: Aircraft = null
var scout_kills := 0
var data_timer := 90.0
var upload_warned := false
var wave_timer := 0.0
var waves := 0
var dogfight := false
var final_timer := -1.0
var last_count := 99
var ace_time := 0.0
var stage2_time := 0.0
var combo_broke_during_ace := false
var ace_active := false
var ace_killed := false
var last_radio := 0.0
var _cp := {"scout_kills": 0, "ace_killed": false}


func _init(game: Game) -> void:
	g = game
	g.add_child(ring_root)
	g.score.combo_broken.connect(func() -> void:
		if ace_active:
			combo_broke_during_ace = true)


# ---------------------------------------------------------------- Scheduling

func _until(test: Callable) -> bool:
	var my := gen
	while not test.call():
		await _stepped
		if gen != my:
			return false
	return gen == my


func _sleep(sec: float) -> bool:
	var end := clock + sec
	return await _until(func() -> bool: return clock >= end)


func cancel() -> void:
	gen += 1
	per_frame = Callable()
	# Wake every waiter so it sees the new generation and unwinds.
	_stepped.emit()


func update(dt: float) -> void:
	clock += dt
	if per_frame.is_valid():
		per_frame.call(dt)
	_update_rings()
	_update_uploads(dt)
	_update_dogfight(dt)
	_update_ace(dt)
	_update_final(dt)
	if tutorial_running:
		tutorial_clock += dt
		g.hud.timer("FLIGHT CHECK", tutorial_clock, true, true)
	_stepped.emit()


func _radio(who: String, text: String, priority := false) -> void:
	g.hud.radio(who, text, priority)
	last_radio = clock


## A key/button cap for prompts, in BBCode.
func key(k: String) -> String:
	var inv: bool = g.settings.invert_pitch
	if g.input.using_touch:
		var t := {
			"pitch_up": "STICK ↓" if inv else "STICK ↑", "left": "STICK ←", "boost": "BOOST",
			"brake": "BRAKE", "roll": "ROLL", "missile": "MSL", "guns": "GUN", "target": "TGT",
		}
		return "[bgcolor=#ffd25a26][color=#ffd25a][b] %s [/b][/color][/bgcolor]" % t[k]
	var pad := g.input.using_pad
	var map := {}
	if pad:
		map = {"pitch_up": "L-STICK ↓" if inv else "L-STICK ↑", "left": "L-STICK ←", "boost": "RT", "brake": "LT", "roll": "B", "missile": "A", "guns": "X", "target": "Y"}
	else:
		map = {"pitch_up": "S" if inv else "W", "left": "A", "boost": "SHIFT", "brake": "X", "roll": "A A", "missile": "F", "guns": "SPACE", "target": "TAB"}
	return _kbd(map[k])


static func _kbd(text: String) -> String:
	return "[bgcolor=#ffffff1f][b] %s [/b][/bgcolor]" % text


static func _step(text: String) -> String:
	return "[font_size=9][color=#ffffff99]%s[/color][/font_size]\n" % text


static func _big(text: String) -> String:
	return "[i][color=#ffd25a]%s[/color][/i]\n" % text


func active_checkpoint() -> Dictionary:
	if not tutorial_running or ring_idx >= rings.size():
		return {}
	var r: Dictionary = rings[ring_idx]
	return {"pos": r.pos, "label": r.label, "normal": r.normal, "kind": r.kind}


# ---------------------------------------------------------------- Entry

func start(cp: String, retry: bool) -> void:
	cancel()
	if retry:
		g.score.restore()
	else:
		g.score.reset()
	if cp == "launch":
		_cp = {"scout_kills": 0, "ace_killed": false}
	scout_kills = _cp.scout_kills
	ace_killed = _cp.ace_killed
	_reset_flags()
	_run(cp)


func _reset_flags() -> void:
	tutorial_running = false
	_clear_rings()
	scouts = []
	lead = null
	last = null
	ace = null
	dogfight = false
	ace_active = false
	upload_warned = false
	waves = 0
	wave_timer = 0.0
	last_count = 99
	g.uploads_active = false
	g.show_boundary = false
	g.lock_penalty = 1.0
	g.boost_regen_mult = 1.0
	g.formation = true
	g.hud.timer(null)
	g.hud.subtimer("")
	g.hud.countdown(0)
	g.hud.boss(null)
	g.hud.scouts(null)
	g.hud.wing_order("")
	g.hud.prompt("")
	g.hud.clear_banners()
	g.hud.clear_radio()
	g.audio.stop_speech()
	g.hud.set_radar_range(4500.0)
	g.hud.set_visible_hud(true)
	g.touch_teach = ""
	g.skippable = false
	g.set_cinematic(false)
	g.rig.play(Callable())
	final_timer = -1.0


func _save(cp: String) -> void:
	checkpoint = cp
	_cp = {"scout_kills": scout_kills, "ace_killed": ace_killed}
	g.score.save()


func _run(cp: String) -> void:
	var my := gen
	var fresh := true
	if cp == "launch":
		_save("launch")
		await _opening()
		if gen != my:
			return
		await _tutorial()
		if gen != my:
			return
		cp = "training"
		fresh = false
	if cp == "training":
		_save("training")
		await _training(fresh)
		if gen != my:
			return
		cp = "scouts"
		fresh = false
	if cp == "scouts":
		_save("scouts")
		await _warning(fresh)
		if gen != my:
			return
		await _scout_phase()
		if gen != my:
			return
		cp = "chase"
		fresh = false
	if cp == "chase":
		_save("chase")
		await _chase(fresh)
		if gen != my:
			return
		cp = "ace"
		fresh = false
	if cp == "ace":
		_save("ace")
		await _reinforcements(fresh)
		if gen != my:
			return
		await _ace_fight()
		if gen != my:
			return
		cp = "final"
		fresh = false
	if cp == "final":
		_save("final")
		await _final_scout(fresh)
		if gen != my:
			return
	await _mission_clear()


# ---------------------------------------------------------------- Opening + Phase 1

func _opening() -> void:
	var p := g.player
	g.reset_world()
	g.fleet.set_time(0.0)
	g.set_controls(false)
	g.set_cinematic(true)
	g.hud.set_visible_hud(true)
	g.spawn_wingmen()
	# Wingmen already airborne ahead of the carrier.
	var wing_start := [Vector3(-260, 260, -900), Vector3(240, 300, -1150), Vector3(30, 340, -1500)]
	for i in g.wingmen.size():
		var w := g.wingmen[i]
		w.pos = g.fleet.carrier_pos() + wing_start[i]
		w.quat = Quaternion.IDENTITY
		w.speed = 150.0
		w.update_basis()
	var st := {"launch_t": -1.0}
	var launch_dur := 1.7
	var place_on_deck := func() -> void:
		var lt: float = st.launch_t
		var z := Fleet.CATAPULT_Z_START if lt < 0.0 else lerpf(Fleet.CATAPULT_Z_START, Fleet.CATAPULT_Z_END, pow(minf(1.0, lt / launch_dur), 2.0))
		p.pos = g.fleet.deck_point(Fleet.CATAPULT_X, Fleet.CATAPULT_Y, z)
		p.quat = Quaternion.IDENTITY
		p.speed = 0.0 if lt < 0.0 else (2.0 * (Fleet.CATAPULT_Z_START - Fleet.CATAPULT_Z_END) * minf(1.0, lt / launch_dur)) / launch_dur + 18.0
		p.throttle = 0.35 if lt < 0.0 else 1.0
		p.update_basis()
	g.pc.autopilot = func(_a: Aircraft, _dt: float) -> void:
		place_on_deck.call()
		p.vel = Vector3.ZERO
	place_on_deck.call()
	g.fleet.steam.emitting = true
	per_frame = func(dt: float) -> void:
		if st.launch_t >= 0.0:
			st.launch_t += dt
	# Low deck shot, slowly creeping forward.
	g.rig.play(func(t: float) -> Dictionary:
		var base := p.pos
		if st.launch_t < 0.0:
			return {"pos": Vector3(base.x - 16 + t * 0.6, base.y + 4.5, base.z + 26 - t * 1.2), "look": Vector3(base.x + 2, base.y + 2.5, base.z - 40), "fov": 62.0}
		return {"pos": Vector3(base.x - 10, base.y + 5, base.z + 34), "look": Vector3(base.x, base.y + 2, base.z - 60), "fov": 62.0})
	g.rig.snap()
	g.audio.set_track("calm", true)
	g.fade_in()
	g.hud.banner("MISSION 01", "JOKER'S RUN", "info", 3.0)
	var t0 := clock
	if not await _sleep(0.9):
		return
	_radio("HALCYON", "We're almost safe. Keep the skies clear until we reach the coast.")
	g.skippable = true
	if not await _until(func() -> bool: return clock - t0 > 4.6 or g.controls.skip):
		return
	g.skippable = false
	g.hud.banner_now("LAUNCH", "JOKER 1 CLEARED", "gold", 1.6)
	g.audio.catapult()
	if not await _sleep(0.35):
		return
	st.launch_t = 0.0
	g.fleet.steam.emitting = false
	g.rig.play(Callable())
	g.rig.snap()
	g.set_cinematic(false)
	if not await _until(func() -> bool: return st.launch_t >= launch_dur):
		return
	# Off the bow: hand over control with a slight nose-up.
	g.pc.autopilot = Callable()
	p.quat = Quaternion(Vector3(1, 0, 0), 0.1)
	p.speed = 150.0
	p.update_basis()
	g.pc.reset()
	g.set_controls(true)
	per_frame = Callable()


func _tutorial() -> void:
	var p := g.player
	phase = "PHASE 1 · LAUNCH"
	g.hud.phase(phase)
	g.hud.objective("FLIGHT CHECK — FLY THROUGH THE CHECKPOINTS")
	var L := p.pos
	L.y = 30.0
	var defs := [
		[Vector3(0, 380, -2100), "CLIMB", "climb"],
		[Vector3(-1500, 60, -700), "BANK LEFT", "bank"],
		[Vector3(-2800, 40, 900), "BOOST", "boost"],
		[Vector3(-350, -120, 2100), "BRAKE", "brake"],
		[Vector3(1650, -60, 1500), "ROLL", "roll"],
	]
	var prev := L
	rings = []
	for d in defs:
		var pos: Vector3 = prev + d[0]
		var normal := (pos - prev).normalized()
		var obj := Models.ring(RADIUS, d[1], UiKit.bold)
		var root: Node3D = obj.root
		ring_root.add_child(root)
		root.global_transform = Transform3D(Basis(Quaternion(Vector3(0, 0, 1), normal)), pos)
		prev = pos
		rings.append({"pos": pos, "normal": normal, "label": d[1], "kind": d[2], "obj": obj, "prev_side": -1.0, "done": false})
	ring_idx = 0
	_style_rings()
	tutorial_clock = 0.0
	tutorial_running = true
	g.hud.subtimer("PAR 01:15")
	g.score.clean_count = 0
	for i in rings.size():
		ring_idx = i
		_style_rings()
		_ring_prompt(i)
		if not await _until(func() -> bool: return rings.size() > i and rings[i].done):
			return
	tutorial_running = false
	g.hud.prompt("")
	g.touch_teach = ""
	g.hud.timer(null)
	g.hud.subtimer("")
	var t := tutorial_clock
	g.score.tutorial_time = t
	var time_bonus := clampf((115.0 - t) / (115.0 - 55.0), 0.0, 1.0) * 0.5
	var mult := roundf((1.0 + g.score.clean_count * 0.1 + time_bonus) * 10.0) / 10.0
	g.score.hot_start = minf(2.0, mult)
	g.show_hot_start = true
	g.audio.bonus()
	g.hud.banner("FLIGHT CHECK COMPLETE", "TIME %s · CLEAN %d/5" % [MathX.fmt_clock(t, true), g.score.clean_count], "info", 2.4)
	g.hud.banner("HOT START x%.1f" % g.score.hot_start, "SCORE MULTIPLIER FOR THIS MISSION", "gold", 2.6)
	_radio("JOKER 2", "Looking sharp, lead.")
	if not await _sleep(2.0):
		return
	_clear_rings()


func _ring_prompt(i: int) -> void:
	var step := _step("CHECKPOINT %d / 5" % (i + 1))
	var touch := g.input.using_touch
	var assisted: bool = touch and g.settings.assist
	var pad := g.input.using_pad
	var kind: String = rings[i].kind
	var lines := {
		"climb": step + _big("CLIMB") + "Pull the nose up with " + key("pitch_up"),
		"bank": (step + _big("BANK LEFT") + "Hold " + key("left") + " and the jet banks and turns for you") if assisted else (step + _big("BANK LEFT") + "Roll left " + key("left") + " then pull " + key("pitch_up") + " to carve the turn"),
		"boost": (step + _big("BOOST") + "Tap " + key("boost") + " to light the afterburner, tap again to cancel") if touch else (step + _big("BOOST") + "Hold " + key("boost") + " — pass through while boosting"),
		"brake": step + _big("BRAKE") + "Hold " + key("brake") + " — slow below 630 km/h and turn tight",
		"roll": (step + _big("ROLL") + "Tap " + key("roll") + " to barrel roll through") if touch else (step + _big("ROLL") + "Double-tap " + (key("roll") if pad else _kbd("A") + " or " + _kbd("D")) + " to barrel roll through"),
	}
	var teach := {"climb": "stick", "bank": "stick", "boost": "boost", "brake": "brake", "roll": "roll"}
	g.touch_teach = teach[kind]
	g.hud.prompt(lines[kind])


## The input device changed (touch <-> keyboard/pad): reword the current checkpoint prompt.
func refresh_prompt() -> void:
	if tutorial_running and ring_idx < rings.size() and not rings[ring_idx].done:
		_ring_prompt(ring_idx)


func _style_rings() -> void:
	for i in rings.size():
		var r: Dictionary = rings[i]
		var active: bool = i == ring_idx and not r.done
		var obj: Dictionary = r.obj
		(obj.root as Node3D).visible = not r.done and i <= ring_idx + 1
		Models.set_opacity(obj.ring_mat, 0.95 if active else 0.3)
		Models.set_opacity(obj.disc_mat, 1.0 if active else 0.2)
		(obj.label as Label3D).visible = active


func _clear_rings() -> void:
	for r in rings:
		(r.obj.root as Node3D).queue_free()
	rings = []
	tutorial_running = false


func _update_rings() -> void:
	if not tutorial_running or ring_idx >= rings.size():
		return
	var r: Dictionary = rings[ring_idx]
	if r.done:
		return
	var pulse := 1.0 + sin(g.real_time * 5.0) * 0.04
	(r.obj.ring as Node3D).scale = Vector3(pulse, pulse, pulse)
	var rel: Vector3 = g.player.pos - r.pos
	var side := rel.dot(r.normal)
	var prev_side: float = r.prev_side
	if signf(side) != signf(prev_side) and absf(prev_side) < 500.0:
		var radial := (rel - (r.normal as Vector3) * side).length()
		if radial < RADIUS + 10.0:
			_pass_ring(r, radial)
	r.prev_side = side


func _pass_ring(r: Dictionary, radial: float) -> void:
	var p := g.player
	r.done = true
	var clean := false
	var clean_label := ""
	match r.kind:
		"climb":
			clean = p.vel.y > 12.0
			clean_label = "CLEAN CLIMB"
		"bank":
			clean = g.pc.left_bank_at > g.time - 4.0
			clean_label = "CLEAN BANK"
		"boost":
			clean = g.pc.boosting
			clean_label = "FULL BOOST"
		"brake":
			clean = p.speed < 175.0
			clean_label = "CLEAN BRAKE"
		"roll":
			clean = g.pc.last_roll_at > g.time - 3.5 or g.pc.roll_time > 0.0
			clean_label = "CLEAN ROLL"
	var lines: Array = [{"text": "CHECKPOINT", "points": Cfg.S_CHECKPOINT, "kind": "bonus"}]
	var pts := float(Cfg.S_CHECKPOINT)
	if clean:
		lines.append({"text": clean_label, "points": Cfg.S_CLEAN, "kind": "gold"})
		pts += Cfg.S_CLEAN
		g.score.clean_count += 1
	if radial < 18.0:
		lines.append({"text": "BULLSEYE", "points": Cfg.S_BULLSEYE, "kind": "bonus"})
		pts += Cfg.S_BULLSEYE
	g.score.add(pts)
	g.hud.popup(lines)
	g.audio.chime(ring_idx)
	g.fx.ring_burst(r.pos, (r.obj.root as Node3D).global_transform.basis, RADIUS)
	(r.obj.root as Node3D).visible = false
	if ring_idx + 1 < rings.size():
		ring_idx += 1
		_style_rings()


# ---------------------------------------------------------------- Phase 2

func _training(fresh: bool) -> void:
	var p := g.player
	if fresh:
		g.reset_world()
		g.fleet.set_time(95.0)
		g.spawn_wingmen()
		p.pos = Vector3(-1500, 650, 1300)
		p.quat = Quaternion(Vector3(0, 0, -1), Vector3(0.45, 0, -1).normalized())
		p.speed = 235.0
		p.update_basis()
		g.place_wingmen_in_formation()
		g.set_controls(true)
		g.show_hot_start = true
		g.rig.snap()
		g.audio.set_track("calm", true)
		g.fade_in()
	phase = "PHASE 2 · TARGET PRACTICE"
	g.hud.phase(phase)
	g.hud.objective("DESTROY 3 DRONES  0 / 3")
	g.formation = true
	g.score.combo_frozen = true
	g.hud.banner("TARGET PRACTICE", "THREE TRAINING DRONES DEPLOYED", "info", 2.4)
	_radio("HALCYON", "Drones away. Three targets, Joker.")
	if not await _sleep(1.2):
		return
	var modes := ["lock", "guns", "evasive"]
	for i in 3:
		var fwd := MathX.horizontal(p.fwd)
		var side := Vector3(-fwd.z, 0, fwd.x) * (MathX.rand_sign() * randf_range(150.0, 350.0))
		var alt := clampf(p.pos.y, 450.0, 1600.0)
		var pos := p.pos + fwd * (1500.0 if i == 2 else 1700.0) + side
		pos.y = alt + randf_range(-40.0, 80.0)
		var heading := fwd.rotated(Vector3.UP, 0.6 if i == 0 else randf_range(-0.8, 0.8))
		var d := g.spawn_drone(pos, heading, modes[i], alt)
		g.target = d
		g.audio.radio_blip()
		g.touch_teach = ["msl", "gun", "brake"][i]
		if i == 0:
			g.hud.prompt(_big("LOCK ON") + "Keep the drone inside the dashed circle until the diamond turns red, then fire " + key("missile"))
		if i == 1:
			g.hud.prompt(_big("GUNS ONLY") + "This drone jams missiles. Close in, line the gun cross up with the lead circle, fire " + key("guns"))
			_radio("HALCYON", "Number two jams missiles. Guns only.")
		if i == 2:
			g.hud.prompt(_big("FAST MOVER") + "Evasive drone. Brake " + key("brake") + " to turn tighter. Any weapon.")
			_radio("HALCYON", "Last one's quick. Stay on him.")
		if not await _until(func() -> bool: return not d.alive):
			return
		g.hud.objective("DESTROY 3 DRONES  %d / 3" % (i + 1), false)
		if not await _sleep(1.4):
			return
	g.hud.prompt("")
	g.touch_teach = ""
	g.hud.banner("COMBO x%d" % maxi(3, g.score.combo), "", "combo", 1.6)
	g.hud.banner("TRAINING COMPLETE", "", "gold", 2.2)
	if not await _sleep(1.2):
		return
	_radio("JOKER 2", "Not bad. Looks like you remember how to shoot.")
	await _sleep(4.2)


# ---------------------------------------------------------------- Phase 3/4

func _warning(fresh: bool) -> void:
	var p := g.player
	if fresh:
		g.reset_world()
		g.fleet.set_time(190.0)
		g.spawn_wingmen()
		p.pos = Vector3(-300, 900, -1800)
		p.quat = Quaternion.IDENTITY
		p.speed = 235.0
		p.update_basis()
		g.place_wingmen_in_formation()
		g.set_controls(true)
		g.show_hot_start = true
		g.rig.snap()
		g.fade_in()
	g.score.combo = 0
	g.score.combo_timer = 0.0
	g.hud.prompt("")
	g.hud.objective("")
	g.hud.phase("")
	# Radar fills with red contacts out of the west.
	var fwd := MathX.horizontal(p.fwd)
	var center := p.pos + Vector3(-1, 0, 0) * 7600.0 + fwd * 1400.0
	center.y = 1700.0
	var heading := Vector3(1, 0, 0.12).normalized()
	var names := ["SCOUT-1", "SCOUT-2", "SCOUT-3"]
	scouts = []
	for i in 3:
		var pos := center + Vector3(i * 500 - 500, i * 60, (i - 1) * 1100)
		var s := g.spawn_scout(pos, heading, names[i])
		s.upload = [0.02, 0.06, 0.0][i]
		scouts.append(s)
	for i in 6:
		var ward := scouts[i % 3]
		var off := Vector3((-1.0 if i < 3 else 1.0) * randf_range(220.0, 380.0), randf_range(40.0, 160.0), randf_range(-200.0, 260.0))
		var f := g.spawn_fighter(ward.pos + off, heading, "escort", 0.55)
		var b: AI.FighterBrain = f.brain
		b.escort_of = ward
		b.escort_offset = off
		f.tag = "escort"
	g.hud.set_radar_range(11000.0)
	g.hud.ping()
	g.audio.klaxon()
	g.audio.set_track("combat", true)
	g.hud.banner_now("WARNING", "UNKNOWN AIRCRAFT APPROACHING", "warning", 3.4)
	_radio("LANTERN", "Multiple contacts, bearing two-seven-zero. They're not ours!", true)
	await _sleep(3.6)


func _scout_phase() -> void:
	phase = "PHASE 3 · STOP THE SCOUTS"
	g.hud.phase(phase)
	g.hud.objective("DESTROY THE SCOUTS BEFORE THEY ESCAPE")
	g.formation = false
	g.wing_order = "cover"
	g.hud.wing_order("cover")
	g.uploads_active = true
	g.show_boundary = true
	g.score.combo_frozen = false
	g.hud.set_radar_range(7000.0)
	data_timer = 90.0
	g.hud.banner("STOP THE SCOUTS", "DATA TRANSMISSION 01:30", "info", 2.6)
	_radio("JOKER 3", "Recon planes, three of them. Escorts too.")
	if g.input.using_touch:
		g.hud.prompt("Scouts are uploading the fleet's position. Damage jams them; escort kills buy time.\nOrder your wingmen with the blue buttons.")
	else:
		g.hud.prompt("Scouts are uploading the fleet's position. Damage interrupts them. Escort kills buy time.\nWingmen: " + _kbd("1") + " cover me · " + _kbd("2") + " attack scouts · " + _kbd("3") + " split")
	g.touch_teach = "orders"
	if not await _sleep(6.5):
		return
	g.hud.prompt("")
	g.touch_teach = ""
	# Phase 4: fighters dive on the player.
	phase = "PHASE 4 · DOGFIGHT"
	g.hud.phase(phase)
	_spawn_divers(4)
	_radio("JOKER 2", "Two on your six!", true)
	var released := 0
	for a in g.aircraft:
		if a.tag == "escort" and released < 2:
			(a.brain as AI.FighterBrain).mode = "engage"
			a.tag = "hunter"
			released += 1
	dogfight = true
	wave_timer = 14.0
	if not await _until(func() -> bool: return scout_kills >= 1):
		return
	dogfight = false


func _spawn_divers(n: int) -> void:
	var p := g.player
	var back := -MathX.horizontal(p.fwd)
	for i in n:
		var pos := p.pos + back * (1700.0 + i * 120.0) + Vector3((i - (n - 1) / 2.0) * 220.0, 900.0 + i * 60.0, 0)
		var dir := (p.pos - pos).normalized()
		var f := g.spawn_fighter(pos, dir, "engage", 0.5 + i * 0.08)
		f.speed = 330.0
		f.tag = "hunter"


func _update_dogfight(dt: float) -> void:
	if not dogfight:
		return
	wave_timer -= dt
	var hunters := 0
	for a in g.aircraft:
		if a.alive and a.team == "red" and a.kind == "fighter" and a.tag == "hunter":
			hunters += 1
	if hunters < 2 and wave_timer <= 0.0 and waves < 4:
		waves += 1
		wave_timer = 16.0
		var p := g.player
		var ang := randf_range(0.0, TAU)
		var dir := Vector3(cos(ang), 0, sin(ang))
		for i in 3:
			var pos := p.pos + dir * (3200.0 + i * 150.0) + Vector3(i * 160.0, randf_range(200.0, 600.0), 0)
			pos.y = maxf(pos.y, 500.0)
			var f := g.spawn_fighter(pos, (p.pos - pos).normalized(), "engage", 0.55)
			f.tag = "hunter"
		g.hud.ping()
		if clock - last_radio > 4.0:
			_radio("LANTERN", "More bandits inbound!")


func _update_uploads(dt: float) -> void:
	if not g.uploads_active:
		if not scouts.is_empty():
			_push_scout_rows()
		return
	var max_up := 0.0
	for s in scouts:
		if not s.alive or s.frozen or s.hidden:
			continue
		if s.upload_pause > 0.0:
			s.upload_pause -= dt
		else:
			s.upload = minf(1.0, s.upload + dt / 90.0)
		max_up = maxf(max_up, s.upload)
	data_timer = (1.0 - max_up) * 90.0
	g.hud.timer("DATA TRANSMISSION", data_timer)
	if not upload_warned and max_up > 0.6:
		upload_warned = true
		_radio("JOKER 3", "Don't let them transmit!")
	_push_scout_rows()
	if data_timer <= 0.0:
		g.fail("DATA TRANSMITTED", "The scouts finished their upload. The fleet's position is out.")


func _push_scout_rows() -> void:
	var rows: Array = []
	for s in scouts:
		var st := "up"
		if not s.alive:
			st = "down"
		elif s.hidden:
			st = "dark"
		elif s.upload_pause > 0.0:
			st = "paused"
		rows.append({"name": s.label, "upload": s.upload, "state": st})
	g.hud.scouts(rows)


func _alive_scouts() -> int:
	var n := 0
	for s in scouts:
		if s.alive:
			n += 1
	return n


## Called by Game when anything dies.
func on_kill(a: Aircraft, by_player: bool, _weapon: String) -> void:
	if a.kind == "scout":
		scout_kills += 1
		g.slowmo(0.3, 0.9)
		if not scouts.is_empty() and _alive_scouts() == 2 and g.uploads_active:
			g.hud.banner_now("SCOUT DOWN", "%d REMAINING" % _alive_scouts(), "gold", 1.8)
	if g.uploads_active and a.team == "red" and a.kind == "fighter":
		for s in scouts:
			if s.alive:
				s.upload = maxf(0.0, s.upload - 10.0 / 90.0)
		if by_player:
			g.hud.popup([{"text": "+10 SEC", "kind": "time"}])
	if a.kind == "fighter" and not by_player and a.team == "red" and clock - last_radio > 5.0 and randf() < 0.6:
		_radio(["JOKER 2", "JOKER 3", "JOKER 4"][randi() % 3], "Splash one!")
	if a.kind == "fighter" and by_player and clock - last_radio > 8.0 and randf() < 0.3:
		_radio("JOKER 3", ["Good kill!", "Nice shooting, lead.", "That's another one."][randi() % 3])


func on_damaged(a: Aircraft) -> void:
	if a.kind == "scout" and g.uploads_active:
		a.upload_pause = 2.5


# ---------------------------------------------------------------- Phase 5

func _chase(fresh: bool) -> void:
	var p := g.player
	var route := g.terrain.chase_route()
	if fresh:
		g.reset_world()
		g.fleet.set_time(260.0)
		g.spawn_wingmen()
		g.audio.set_track("combat", true)
		g.show_hot_start = true
		var names := ["SCOUT-1", "SCOUT-2", "SCOUT-3"]
		scouts = []
		for i in 3:
			var s := g.spawn_scout(Vector3(0, 1600, -2000 - i * 400), Vector3(1, 0, 0), names[i])
			s.upload = 0.55
			scouts.append(s)
		scouts[2].alive = false
		g.despawn(scouts[2])
		lead = scouts[0]
		last = scouts[1]
	else:
		var alive: Array[Aircraft] = []
		for s in scouts:
			if s.alive:
				alive.append(s)
		alive.sort_custom(func(a: Aircraft, b: Aircraft) -> bool: return a.pos.distance_to(p.pos) < b.pos.distance_to(p.pos))
		lead = alive[0] if alive.size() > 0 else null
		last = alive[1] if alive.size() > 1 else null
	g.uploads_active = false
	g.hud.timer(null)
	var ld := lead
	if ld == null:
		return
	if not fresh:
		if not await _sleep(0.9):
			return
		_radio("JOKER 2", "Scout breaking east!", true)
		# Brief cut to the lead scout peeling off and diving.
		g.set_cinematic(true)
		var sb0: AI.ScoutBrain = ld.brain
		sb0.cruise_alt = 200.0
		sb0.heading = Vector3(1, 0, 0.05).normalized()
		g.rig.play(func(t: float) -> Dictionary:
			var hf := MathX.horizontal(ld.fwd)
			var hr := Vector3(-hf.z, 0, hf.x)
			return {"pos": ld.pos + hf * (-75.0 + t * 6.0) + hr * 38.0 + Vector3(0, 16, 0), "look": ld.pos + hf * 25.0, "fov": 52.0})
		g.hud.banner_now("SCOUT BREAKING EAST", "", "red", 2.0)
		if not await _sleep(2.3):
			return
		g.flash_white()
		if not await _sleep(0.15):
			return
	# Set piece: the lead scout runs the cliffs, canyon and bridge.
	for a in g.aircraft:
		if a == p or a == ld:
			continue
		a.frozen = true
	g.weapons.clear()
	var start_idx := 0
	for i in route.size():
		if (route[i][0] as Vector3).x >= 4300.0:
			start_idx = i
			break
	var sb: AI.ScoutBrain = ld.brain
	sb.mode = "chase"
	sb.route = route
	sb.route_idx = start_idx + 1
	sb.evade_chance = 0.8
	ld.pos = route[start_idx][0]
	ld.quat = Quaternion(Vector3(0, 0, -1), ((route[start_idx + 1][0] as Vector3) - (route[start_idx][0] as Vector3)).normalized())
	ld.speed = 285.0
	ld.hp = 230.0
	ld.max_hp = 230.0
	ld.flares = 7
	ld.label = "LEAD SCOUT"
	ld.update_basis()
	var p_idx := 0
	for i in route.size():
		if (route[i][0] as Vector3).x >= 3150.0:
			p_idx = i
			break
	p.pos = (route[p_idx][0] as Vector3) + Vector3(0, 70, 0)
	p.quat = Quaternion(Vector3(0, 0, -1), ((route[p_idx + 1][0] as Vector3) - (route[p_idx][0] as Vector3)).normalized())
	p.speed = 300.0
	p.update_basis()
	g.pc.reset()
	g.pc.boost_energy = 1.0
	g.boost_regen_mult = 2.2
	g.lock_penalty = 1.8
	g.target = ld
	g.set_cinematic(false)
	g.rig.play(Callable())
	g.rig.snap()
	g.set_controls(true)
	if fresh:
		g.fade_in()
	phase = "PHASE 5 · THE CHASE"
	g.hud.phase(phase)
	g.hud.objective("INTERCEPT THE LEAD SCOUT")
	g.show_boundary = true
	g.hud.set_radar_range(5000.0)
	_radio("JOKER 3", "We'll keep the rest busy. Go!")
	g.hud.prompt("Missiles struggle at high speed and in the canyon.\nBoost " + key("boost") + " to close, then finish it with guns " + key("guns") + ".")
	var st := {"prompt_t": 7.0}
	g.touch_teach = "gun"
	per_frame = func(dt: float) -> void:
		st.prompt_t -= dt
		if st.prompt_t <= 0.0:
			g.hud.prompt("")
			g.touch_teach = ""
		var remain := maxf(0.0, Cfg.BOUNDARY_X - ld.pos.x)
		g.hud.subtimer("LEAD SCOUT → BOUNDARY  %.1f KM" % (remain / 1000.0))
	if not await _until(func() -> bool: return not ld.alive):
		return
	per_frame = Callable()
	g.hud.prompt("")
	g.hud.subtimer("")
	g.hud.banner_now("TRANSMISSION STOPPED", "LEAD SCOUT DOWN", "gold", 2.6)
	g.lock_penalty = 1.0
	g.boost_regen_mult = 1.0


# ---------------------------------------------------------------- Phase 6/7

func _reinforcements(fresh: bool) -> void:
	var p := g.player
	if fresh:
		g.reset_world()
		g.fleet.set_time(330.0)
		g.spawn_wingmen()
		g.show_hot_start = true
		var x := 14300.0
		p.pos = Vector3(x, 600, Terrain.canyon_z(x))
		p.quat = Quaternion(Vector3(0, 0, -1), Vector3(1, 0, 0))
		p.speed = 260.0
		p.update_basis()
		g.set_controls(true)
		g.rig.snap()
		g.audio.set_track("combat", true)
		g.fade_in()
		var names := ["SCOUT-1", "SCOUT-2", "SCOUT-3"]
		scouts = []
		for i in 3:
			var s := g.spawn_scout(Vector3(9000, 300, 4000 + i * 300), Vector3(1, 0, 0), names[i])
			s.upload = 0.6
			scouts.append(s)
		scouts[0].alive = false
		g.despawn(scouts[0])
		scouts[2].alive = false
		g.despawn(scouts[2])
		last = scouts[1]
		if not await _sleep(0.5):
			return
	else:
		if not await _sleep(2.4):
			return
	phase = "PHASE 6 · REINFORCEMENTS"
	g.hud.phase(phase)
	g.hud.objective("")
	# Everything left in the old fight is far behind; the last scout went dark.
	for a in g.aircraft.duplicate():
		if a.team == "red" and a != last:
			g.despawn(a)
	if last != null and last.alive:
		last.hidden = true
		last.frozen = true
	g.unfreeze_wingmen_behind_player()
	g.formation = true
	_radio("JOKER 2", "Right behind you, lead. Lost the last scout in the clouds.")
	# Escorts ahead break formation and scatter.
	var fwd := MathX.horizontal(p.fwd)
	var escorts: Array[Aircraft] = []
	for i in 3:
		var pos := p.pos + fwd * (2600.0 + i * 90.0) + Vector3((i - 1) * 140.0, 250.0 + i * 30.0, 0)
		var f := g.spawn_fighter(pos, fwd, "engage", 0.5)
		f.tag = "escort"
		escorts.append(f)
	if not await _sleep(2.0):
		return
	for i in escorts.size():
		var e := escorts[i]
		var b: AI.FighterBrain = e.brain
		var away := e.pos + Vector3((i - 1) * 3000.0, 0, -3000.0 if i == 1 else 0.0)
		b.flee(e.pos - (away - e.pos), e)
	_radio("JOKER 3", "Escorts are breaking formation... why?")
	if not await _sleep(2.6):
		return
	g.hud.banner_now("WARNING", "ENEMY ACE APPROACHING", "warning", 3.2)
	g.audio.klaxon()
	g.hud.ping()
	g.audio.set_track("boss", true)
	if not await _sleep(2.2):
		return
	var pos := p.pos + MathX.horizontal(p.fwd) * 3300.0 + Vector3(0, 1700, 0)
	ace = g.spawn_ace(pos, (p.pos - pos).normalized())
	g.target = ace
	_radio("JOKER 2", "That one's different.", true)
	await _sleep(0.5)


func _ace_fight() -> void:
	var a := ace
	if a == null:
		return
	phase = "PHASE 7 · ACE"
	g.hud.phase(phase)
	g.hud.objective("SHOOT DOWN THE ACE")
	g.formation = false
	ace_time = 0.0
	stage2_time = 0.0
	combo_broke_during_ace = false
	ace_active = true
	g.hud.prompt(_step("OPTIONAL") + "Destroy the ace without breaking your combo.\nStay on his tail to build [b]PRESSURE[/b] and force him low.")
	var st := {"prompt_t": 7.0}
	per_frame = func(dt: float) -> void:
		st.prompt_t -= dt
		if st.prompt_t <= 0.0:
			g.hud.prompt("")
			st.prompt_t = 1e9
	if not await _until(func() -> bool: return not a.alive or stage2_time > 28.0 or ace_time > 100.0):
		return
	per_frame = Callable()
	g.hud.prompt("")
	ace_active = false
	if not a.alive:
		await _sleep(2.6)


func _update_ace(dt: float) -> void:
	var a := ace
	if a == null or not a.alive:
		if a != null and not a.alive:
			g.hud.boss(null)
		return
	var b: AI.AceBrain = a.brain
	if ace_active or a.targetable():
		ace_time += dt
		if b.stage == 2:
			stage2_time += dt
	var low := b.forced_low_t > 0.0
	var status := ""
	if low:
		status = "FORCED LOW — ATTACK NOW"
	elif b.stage == 2:
		status = "HEAD-ON ATTACKS"
	elif a.pos.y > 1300.0:
		status = "HIGH ENERGY — HARD TO HIT"
	g.hud.boss({"hp": a.hp / a.max_hp, "pressure": b.forced_low_t / 9.0 if low else b.pressure, "stage": b.stage, "status": status, "low": low})


func on_ace_killed() -> void:
	ace_killed = true
	g.score.ace_bonus = true
	g.hud.banner_now("ACE DESTROYED", "+" + MathX.fmt_score(Cfg.S_ACE), "gold", 2.8)
	if not combo_broke_during_ace:
		g.score.ace_combo_bonus = true
		var bonus := roundf(Cfg.S_ACE_COMBO * g.score.hot_start)
		g.score.add(bonus)
		g.hud.popup([{"text": "UNBROKEN COMBO", "points": bonus, "kind": "gold"}])
	_radio("JOKER 3", "Splash the ace!", true)
	g.slowmo(0.25, 1.2)


func on_ace_enraged() -> void:
	g.hud.banner_now("ACE ENRAGED", "HE IS COMING HEAD-ON", "red", 2.2)
	_radio("JOKER 4", "He's coming straight at you!", true)


func on_ace_forced_low() -> void:
	g.hud.popup([{"text": "ACE FORCED LOW", "kind": "gold"}])
	if clock - last_radio > 4.0:
		_radio("JOKER 2", "He's losing altitude. Hit him now!")


# ---------------------------------------------------------------- Phase 8

func _final_scout(fresh: bool) -> void:
	var p := g.player
	if fresh:
		g.reset_world()
		g.fleet.set_time(420.0)
		g.spawn_wingmen()
		g.show_hot_start = true
		p.pos = Vector3(15200, 1100, -2600)
		p.quat = Quaternion(Vector3(0, 0, -1), Vector3(0.3, 0, -1).normalized())
		p.speed = 260.0
		p.update_basis()
		g.place_wingmen_in_formation()
		g.set_controls(true)
		g.rig.snap()
		g.fade_in()
		var names := ["SCOUT-1", "SCOUT-2", "SCOUT-3"]
		scouts = []
		for i in 3:
			var s := g.spawn_scout(Vector3(9000, 300, 4000 + i * 300), Vector3(1, 0, 0), names[i])
			s.upload = 0.7
			scouts.append(s)
		for i in [0, 2]:
			scouts[i].alive = false
			g.despawn(scouts[i])
		last = scouts[1]
		last.hidden = true
		last.frozen = true
		if not ace_killed:
			var pos := p.pos - p.fwd * 1800.0 + Vector3(400, 300, 0)
			ace = g.spawn_ace(pos, p.fwd)
			ace.hp = ace.max_hp * 0.48
			var ab: AI.AceBrain = ace.brain
			ab.stage = 2
			ab.state = "attack"
		g.formation = false
	var ls := last
	if ls == null or not ls.alive:
		return
	var fwd := MathX.horizontal(p.fwd)
	var dir := fwd.rotated(Vector3.UP, MathX.rand_sign() * randf_range(0.8, 1.2))
	var pos := p.pos + dir * 3000.0
	pos.y = g.terrain.ground(pos.x, pos.z) + 230.0
	ls.pos = pos
	ls.quat = Quaternion(Vector3(0, 0, -1), dir)
	ls.speed = 225.0
	ls.hp = 220.0
	ls.max_hp = 220.0
	ls.flares = 5
	ls.hidden = false
	ls.frozen = false
	ls.label = "LAST SCOUT"
	ls.update_basis()
	var sb: AI.ScoutBrain = ls.brain
	sb.start_final(ls, dir)
	sb.evade_chance = 0.65
	g.target = ls
	phase = "PHASE 8 · FINAL SCOUT"
	g.hud.phase(phase)
	g.hud.objective("FINAL TARGET ESCAPING")
	g.hud.banner_now("FINAL TARGET ESCAPING", "TRANSMISSION IN 00:25", "red", 2.4)
	g.hud.ping()
	g.audio.set_track("final", true)
	_radio("LANTERN", "Last scout's running low. It's about to transmit!", true)
	final_timer = 25.0
	last_count = 99
	g.hud.set_radar_range(6000.0)
	if not await _until(func() -> bool: return not ls.alive):
		return
	final_timer = -1.0
	g.hud.countdown(0)
	g.hud.timer(null)


func _update_final(dt: float) -> void:
	if final_timer < 0.0 or last == null or not last.alive or last.hidden or last.frozen:
		return
	final_timer -= dt
	g.hud.timer("FINAL TRANSMISSION", maxf(0.0, final_timer), true)
	var n := int(ceil(final_timer))
	if n <= 10 and n >= 1:
		g.hud.countdown(n)
		if n != last_count:
			last_count = n
			g.audio.countdown_beep(n <= 3)
	if final_timer <= 0.0:
		final_timer = -1.0
		g.hud.countdown(0)
		g.fail("TRANSMISSION COMPLETE", "The last scout got its data out.")


# ---------------------------------------------------------------- Clear + epilogue

func _mission_clear() -> void:
	var p := g.player
	final_timer = -1.0
	g.uploads_active = false
	g.show_boundary = false
	g.hud.timer(null)
	g.hud.countdown(0)
	g.hud.prompt("")
	g.hud.boss(null)
	g.hud.objective("")
	g.slowmo(0.3, 1.2)
	g.hud.banner_now("MISSION CLEAR", "", "gold", 3.6)
	g.audio.set_track("none", true)
	g.audio.explosion(0.25, true)
	g.state = "clear"
	if ace != null and ace.alive:
		(ace.brain as AI.AceBrain).retreat()
	for a in g.aircraft:
		if a.team == "red" and a.kind == "fighter" and a.brain is AI.FighterBrain:
			(a.brain as AI.FighterBrain).flee(p.pos, a)
	if not await _sleep(1.4):
		return
	g.set_controls(false)
	g.formation = true
	# Autopilot: level off and turn for home.
	g.pc.autopilot = func(a: Aircraft, dt: float) -> void:
		var home := g.fleet.carrier_pos() - a.pos
		home.y = 0.0
		home = home.normalized()
		home.y = clampf((900.0 - a.pos.y) / 1500.0, -0.2, 0.25)
		home = AI.avoid_terrain(a, g, home, 150.0)
		AI.steer(a, home, 0.45, dt, 230.0, 0.5)
		a.throttle = 0.4
	_radio("HALCYON", "All scouts destroyed.")
	if ace != null and ace.alive:
		_radio("JOKER 3", "The ace is bugging out.")
	g.set_cinematic(true)
	g.rig.play(func(t: float) -> Dictionary:
		var hf := MathX.horizontal(p.fwd)
		var hr := Vector3(-hf.z, 0, hf.x)
		return {"pos": p.pos + hr * (-70.0 - t * 3.0) + hf * (45.0 - t * 7.0) + Vector3(0, 14, 0), "look": p.pos + hf * 12.0, "fov": 48.0})
	if not await _until(func() -> bool: return not g.hud.radio_busy()):
		return
	if not await _sleep(1.8):
		return
	_radio("HALCYON", "Carrier is still safe.")
	if not await _until(func() -> bool: return not g.hud.radio_busy()):
		return
	if not await _sleep(1.0):
		return
	_radio("HALCYON", "Enemy forces were closer than expected.")
	if not await _until(func() -> bool: return not g.hud.radio_busy()):
		return
	_radio("LANTERN", "We may have been detected anyway.")
	# Cut: high over the carrier, then pan to the storm front.
	g.flash_black()
	if not await _sleep(0.6):
		return
	var storm := Vector3(-9000, 1800, 26000)
	g.rig.play(func(t: float) -> Dictionary:
		var c := g.fleet.carrier_pos()
		var look_carrier := c + Vector3(0, 20, 60)
		var k := clampf((t - 3.4) / 4.6, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		return {"pos": Vector3(c.x + 520, 720 - t * 12, c.z - 760 + t * 30), "look": look_carrier.lerp(storm, e), "fov": lerpf(36.0, 58.0, e)})
	g.fade_in()
	if not await _sleep(8.5):
		return
	g.audio.stinger()
	g.show_card()
	if not await _sleep(4.5):
		return
	g.show_debrief()
