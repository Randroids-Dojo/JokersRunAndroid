class_name AI
extends RefCounted
## AI pilots: fighters/escorts, recon scouts, training drones, wingmen and the two-stage ace.
## Line-for-line port of the web build's ai.ts.


## Turn-rate-limited steering with automatic coordinated banking.
static func steer(a: Aircraft, desired: Vector3, turn_rate: float, dt: float, target_speed: float, accel := 0.8) -> void:
	var d := desired.normalized()
	var f := a.fwd
	var n := MathX.rotate_toward(f, d, turn_rate * dt)
	var lat := (n - f) * (a.speed / maxf(dt, 1e-4))
	var u := Vector3(0, 9.81, 0) + lat
	u -= n * u.dot(n)
	if u.length_squared() < 1e-6:
		u = a.up
	u = u.normalized()
	var b := a.up.lerp(u, 1.0 - exp(-5.0 * dt))
	b -= n * b.dot(n)
	if b.length_squared() < 1e-6:
		b = u
	b = b.normalized()
	a.quat = MathX.quat_from_fwd_up(n, b)
	a.speed = MathX.damp(a.speed, target_speed, accel, dt)
	a.g_load = lat.length() / 9.81
	a.update_basis()
	a.pos += a.vel * dt


## Bend `desired` upward when the terrain ahead is too close.
static func avoid_terrain(a: Aircraft, g: Game, desired: Vector3, margin: float) -> Vector3:
	var worst := 0.0
	for t in [0.5, 1.2, 2.2, 3.4]:
		var px: float = a.pos.x + a.vel.x * t
		var pz: float = a.pos.z + a.vel.z * t
		var py: float = a.pos.y + a.vel.y * t
		var clearance := py - (g.terrain.ground(px, pz) + margin)
		if clearance < 0.0:
			worst = maxf(worst, -clearance / margin)
	var here := a.pos.y - g.terrain.ground(a.pos.x, a.pos.z)
	if here < margin * 0.5:
		worst = maxf(worst, 1.5)
	var out := desired
	if worst > 0.0:
		out = out.normalized()
		out.y = maxf(out.y, 0.0) + minf(2.5, worst * 1.5)
		out = out.normalized()
	if a.pos.y > 4800.0 and out.y > 0.0:
		out.y *= 0.2
		out = out.normalized()
	return out


static func lead_point(a: Aircraft, t: Aircraft, projectile_speed: float) -> Vector3:
	var dist := a.pos.distance_to(t.pos)
	var tf := clampf(dist / projectile_speed, 0.0, 2.5)
	return t.pos + t.vel * tf


static func drop_flares(a: Aircraft, g: Game, cooldown := 2.5) -> bool:
	if a.flares > 0 and a.flare_cooldown <= 0.0:
		a.flares -= 1
		a.flare_cooldown = cooldown
		g.weapons.drop_flares(a)
		g.on_flares(a)
		return true
	return false


class GunSpec:
	var range_ := 900.0
	var cone := 0.07
	var rate := 10.0
	var damage := 2.0
	var spread := 0.012
	var burst_on := 0.9
	var burst_off := 1.6

	func _init(r: float, c: float, rt: float, dmg: float, sp: float, on: float, off: float) -> void:
		range_ = r
		cone = c
		rate = rt
		damage = dmg
		spread = sp
		burst_on = on
		burst_off = off


class GunControl:
	var _burst := 0.0
	var _on := false

	func fire(a: Aircraft, g: Game, target: Aircraft, spec: GunSpec, dt: float) -> void:
		a.gun_cooldown -= dt
		_burst -= dt
		if _burst <= 0.0:
			_on = not _on
			_burst = spec.burst_on if _on else spec.burst_off * randf_range(0.7, 1.3)
		if not _on or a.gun_cooldown > 0.0:
			return
		if a.pos.distance_to(target.pos) > spec.range_:
			return
		var aim := AI.lead_point(a, target, 950.0 + a.speed)
		var t := (aim - a.pos).normalized()
		if a.fwd.angle_to(t) > spec.cone:
			return
		a.gun_cooldown = 1.0 / spec.rate
		t = t.lerp(a.fwd, 0.25)
		t += Vector3(randf_range(-spec.spread, spec.spread), randf_range(-spec.spread, spec.spread), randf_range(-spec.spread, spec.spread))
		t = t.normalized()
		g.weapons.fire_bullet(a, a.pos + a.fwd * 11.0, t, 950.0, spec.damage, 1.35)
		g.on_ai_gun_shot(a)


class MissileControl:
	var lock_t := 0.0

	func fire(a: Aircraft, g: Game, target: Aircraft, dt: float, cooldown: float, range_ := 2700.0, lock_needed := 1.4) -> void:
		a.missile_cooldown -= dt
		var dist := a.pos.distance_to(target.pos)
		var t := (target.pos - a.pos).normalized()
		if dist < range_ and dist > 350.0 and a.fwd.angle_to(t) < 0.42:
			lock_t += dt
		else:
			lock_t = maxf(0.0, lock_t - dt * 2.0)
		if lock_t >= lock_needed and a.missile_cooldown <= 0.0 and g.can_launch_at(target):
			g.fire_ai_missile(a, target)
			a.missile_cooldown = cooldown * randf_range(0.8, 1.25)
			lock_t = 0.0


# ---------------------------------------------------------------- Fighter

class FighterBrain:
	var mode: String  # engage | escort | flee
	var target: Aircraft = null
	var escort_of: Aircraft = null
	var escort_offset := Vector3.ZERO
	var skill: float
	var turn_rate := 1.05
	var evade_chance := 0.22
	var player_bias := 0.75
	var _evade_t := 0.0
	var _evade_dir := 1.0
	var _evade_switch := 0.0
	var _extend_t := 0.0
	var _threat_t := 0.0
	var _retarget_t := 0.0
	var _flee_dir := Vector3.ZERO
	var _gun := GunControl.new()
	var _msl := MissileControl.new()
	var _spec := GunSpec.new(900.0, 0.07, 10.0, 2.0, 0.012, 0.9, 1.6)

	func _init(p_mode: String, p_skill := 0.6) -> void:
		mode = p_mode
		skill = p_skill

	func flee(from: Vector3, a: Aircraft) -> void:
		mode = "flee"
		var d := a.pos - from
		d.y = 0.0
		_flee_dir = d.normalized()
		_flee_dir.y = 0.25
		_flee_dir = _flee_dir.normalized()

	func _pick_target(a: Aircraft, g: Game) -> void:
		var p := g.player
		var best: Aircraft = p if p.alive else null
		if randf() > player_bias:
			var bd := INF
			for w in g.wingmen:
				if not w.targetable():
					continue
				var d := w.pos.distance_to(a.pos)
				if d < bd:
					bd = d
					best = w
		target = best
		_retarget_t = randf_range(6.0, 11.0)

	func update(a: Aircraft, g: Game, dt: float) -> void:
		a.flare_cooldown -= dt
		var desired: Vector3
		var speed := 270.0
		var turn := turn_rate
		if mode == "flee":
			desired = AI.avoid_terrain(a, g, _flee_dir, 150.0)
			AI.steer(a, desired, 0.9, dt, 390.0, 0.5)
			a.throttle = 1.0
			return
		_retarget_t -= dt
		if target == null or not target.targetable() or _retarget_t <= 0.0:
			_pick_target(a, g)
		var tgt := target
		if mode == "escort" and escort_of != null and escort_of.targetable():
			var ward := escort_of
			var threat: Aircraft = null
			var td := 2600.0
			for b in g.aircraft:
				if b.team != "blue" or not b.targetable():
					continue
				var d := b.pos.distance_to(ward.pos)
				if d < td:
					td = d
					threat = b
			var from_ward := a.pos.distance_to(ward.pos)
			if threat == null or from_ward > 4200.0:
				var slot := ward.quat * escort_offset + ward.pos
				desired = slot - a.pos + ward.fwd * 400.0
				var along := (slot - a.pos).dot(ward.fwd)
				speed = ward.speed + clampf(along * 0.5, -60.0, 140.0)
				desired = AI.avoid_terrain(a, g, desired, 150.0)
				AI.steer(a, desired, 0.9, dt, speed, 1.2)
				a.throttle = 0.4
				return
			tgt = threat
		if tgt == null:
			AI.steer(a, a.fwd, turn, dt, speed)
			return
		var p := g.player
		var tp := a.pos - p.pos
		var pd := tp.length()
		tp /= maxf(pd, 1.0)
		var chased := pd < 1300.0 and p.alive and p.fwd.dot(tp) > 0.93 and a.fwd.dot(tp) > 0.2
		_threat_t = _threat_t + dt if chased else maxf(0.0, _threat_t - dt)
		if _threat_t > 1.6 - skill and _evade_t <= 0.0 and randf() < dt * 1.5:
			_evade_t = randf_range(2.2, 3.6)
			_evade_dir = MathX.rand_sign()
			_evade_switch = randf_range(0.8, 1.5)
		if _evade_t > 0.0:
			_evade_t -= dt
			_evade_switch -= dt
			if _evade_switch <= 0.0:
				_evade_dir = -_evade_dir
				_evade_switch = randf_range(0.9, 1.6)
			desired = a.fwd * 0.5 + a.right * (_evade_dir * 1.4) + a.up * 0.6
			speed = 300.0
			turn *= 1.15
		elif _extend_t > 0.0:
			_extend_t -= dt
			desired = a.fwd + MathX.horizontal(a.fwd) * 0.5
			desired.y += 0.08
			speed = 340.0
		else:
			desired = AI.lead_point(a, tgt, a.speed * 1.6) - a.pos
			var dist := a.pos.distance_to(tgt.pos)
			speed = clampf(tgt.speed + (80.0 if dist > 1200.0 else 20.0), 200.0, 360.0)
			if dist < 220.0 and a.fwd.dot(tgt.fwd) < 0.5:
				_extend_t = randf_range(1.8, 3.2)
		desired = AI.avoid_terrain(a, g, desired, 140.0)
		AI.steer(a, desired, turn, dt, speed)
		a.throttle = 0.9 if speed > 300.0 else 0.45
		if tgt.alive and _evade_t <= 0.0:
			_gun.fire(a, g, tgt, _spec, dt)
			_msl.fire(a, g, tgt, dt, 12.0)

	func on_missile_incoming(a: Aircraft, m: Missile, g: Game) -> bool:
		_evade_t = randf_range(2.0, 3.0)
		_evade_dir = -1.0 if (m.pos - a.pos).dot(a.right) > 0.0 else 1.0
		_evade_switch = 3.0
		var flared := AI.drop_flares(a, g)
		return randf() < evade_chance + (0.25 if flared else 0.0)


# ---------------------------------------------------------------- Scout

class ScoutBrain:
	var mode := "cruise"  # cruise | chase | final
	var heading := Vector3(1, 0, 0.12).normalized()
	var cruise_alt := 1700.0
	var route: Array = []  # Array of [Vector3 pos, float speed]
	var route_idx := 0
	var evade_chance := 0.45
	var _t := randf_range(0.0, 100.0)
	var _jink_t := 0.0
	var _jink_dir := Vector3.ZERO
	var _final_dir := Vector3.ZERO

	func start_final(a: Aircraft, away: Vector3) -> void:
		mode = "final"
		_final_dir = Vector3(away.x, 0, away.z).normalized()
		a.speed = 225.0

	func update(a: Aircraft, g: Game, dt: float) -> void:
		_t += dt
		a.flare_cooldown -= dt
		var desired: Vector3
		if mode == "chase":
			while route_idx < route.size() - 1:
				var pt: Vector3 = route[route_idx][0]
				var tt := pt - a.pos
				if tt.length() < 200.0 or tt.dot(a.fwd) < 0.0:
					route_idx += 1
				else:
					break
			var look: Array = route[mini(route.size() - 1, route_idx + 1)]
			desired = ((look[0] as Vector3) - a.pos).normalized() + a.right * (sin(_t * 1.3) * 0.04)
			AI.steer(a, desired, 1.25, dt, look[1], 0.7)
			a.throttle = 0.9
			if route_idx >= route.size() - 2:
				g.on_scout_escaped(a)
			return
		if mode == "final":
			desired = _final_dir + Vector3(-_final_dir.z, 0, _final_dir.x) * (sin(_t * 0.7) * 0.35)
			var gh := g.terrain.ground(a.pos.x, a.pos.z)
			desired.y = clampf((gh + 230.0 - a.pos.y) / 500.0, -0.35, 0.35)
			if _jink_t > 0.0:
				_jink_t -= dt
				desired += _jink_dir
			desired = AI.avoid_terrain(a, g, desired, 90.0)
			AI.steer(a, desired, 0.85, dt, 245.0, 0.5)
			a.throttle = 0.8
			return
		desired = heading + Vector3(-heading.z, 0, heading.x) * (sin(_t * 0.25) * 0.25)
		desired.y = clampf((cruise_alt - a.pos.y) / 700.0, -0.25, 0.25)
		if _jink_t > 0.0:
			_jink_t -= dt
			desired += _jink_dir
		desired = AI.avoid_terrain(a, g, desired, 200.0)
		AI.steer(a, desired, 0.5, dt, 135.0, 0.4)
		a.throttle = 0.35

	func on_hit(a: Aircraft, _g: Game, _weapon: String) -> void:
		if _jink_t <= 0.0 and mode != "chase":
			_jink_t = 1.4
			_jink_dir = a.right * (MathX.rand_sign() * 0.6)
			_jink_dir.y = randf_range(-0.15, 0.2)

	func on_missile_incoming(a: Aircraft, _m: Missile, g: Game) -> bool:
		var cd := 0.7 if mode == "chase" else (1.4 if mode == "final" else 2.5)
		var flared := AI.drop_flares(a, g, cd)
		if not flared:
			return randf() < evade_chance * 0.4
		return randf() < evade_chance


# ---------------------------------------------------------------- Training drones

class DroneBrain:
	var mode: String  # lock | guns | evasive
	var alt: float
	var _t := 0.0
	var _pick_t := 0.0
	var _wish := Vector3.ZERO
	var _evade_t := 0.0
	var _evade_dir := 1.0

	func _init(p_mode: String, p_alt: float) -> void:
		mode = p_mode
		alt = p_alt

	func update(a: Aircraft, g: Game, dt: float) -> void:
		_t += dt
		var desired: Vector3
		var to_p := g.player.pos - a.pos
		var dist := to_p.length()
		if mode == "lock":
			desired = a.fwd.rotated(Vector3.UP, 0.08)
			desired.y = clampf((alt - a.pos.y) / 500.0, -0.2, 0.2)
			var far := dist > 3800.0
			if far:
				desired = to_p.normalized()
			AI.steer(a, desired, 0.4 if far else 0.12, dt, 120.0, 0.5)
			a.throttle = 0.3
			return
		if mode == "guns":
			desired = MathX.horizontal(a.fwd).rotated(Vector3.UP, sin(_t * 0.6) * 0.35)
			desired.y = clampf((alt - a.pos.y) / 500.0, -0.2, 0.2) + sin(_t * 0.9) * 0.08
			if dist > 3000.0:
				desired = to_p.normalized()
			AI.steer(a, desired, 0.55, dt, 145.0, 0.5)
			a.throttle = 0.35
			return
		_pick_t -= dt
		if _pick_t <= 0.0:
			_pick_t = randf_range(1.0, 1.8)
			_wish = (a.fwd.rotated(Vector3.UP, randf_range(-1.2, 1.2)) + Vector3(0, randf_range(-0.35, 0.4), 0)).normalized()
		desired = _wish
		if dist > 3000.0:
			desired = to_p.normalized()
		if _evade_t > 0.0:
			_evade_t -= dt
			desired = a.fwd + a.right * (_evade_dir * 1.5)
		desired.y += clampf((alt - a.pos.y) / 900.0, -0.3, 0.3)
		desired = AI.avoid_terrain(a, g, desired, 150.0)
		AI.steer(a, desired, 1.45, dt, 255.0, 0.8)
		a.throttle = 0.9

	func on_missile_incoming(a: Aircraft, m: Missile, _g: Game) -> bool:
		if mode != "evasive":
			return false
		_evade_t = 1.8
		_evade_dir = -1.0 if (m.pos - a.pos).dot(a.right) > 0.0 else 1.0
		return randf() < 0.4


# ---------------------------------------------------------------- Wingman

class WingmanBrain:
	var slot: Vector3
	var role: int
	var target: Aircraft = null
	var _retarget_t := 0.0
	var _gun := GunControl.new()
	var _msl := MissileControl.new()
	var _spec := GunSpec.new(800.0, 0.06, 9.0, 2.4, 0.01, 1.0, 1.4)

	func _init(p_slot: Vector3, p_role: int) -> void:
		slot = p_slot
		role = p_role

	func _pick(a: Aircraft, g: Game) -> void:
		var want_scouts := g.wing_order == "scouts" or (g.wing_order == "split" and role == 2)
		var any_scout := false
		for x in g.aircraft:
			if x.kind == "scout" and x.targetable():
				any_scout = true
				break
		var best: Aircraft = null
		var bd := INF
		for b in g.aircraft:
			if b.team != "red" or not b.targetable():
				continue
			var is_scout := b.kind == "scout"
			if want_scouts != is_scout and not (want_scouts and not any_scout):
				continue
			var ref := a.pos if want_scouts else g.player.pos
			var d := b.pos.distance_to(ref) + (4000.0 if b.kind == "ace" else 0.0)
			if d < bd:
				bd = d
				best = b
		target = best
		_retarget_t = randf_range(4.0, 7.0)

	func update(a: Aircraft, g: Game, dt: float) -> void:
		var p := g.player
		_retarget_t -= dt
		if not g.formation and (target == null or not target.targetable() or _retarget_t <= 0.0):
			_pick(a, g)
		var desired: Vector3
		if g.formation or target == null:
			var s := p.quat * slot + p.pos
			desired = s - a.pos + p.fwd * 260.0
			var along := (s - a.pos).dot(p.fwd)
			var far := a.pos.distance_to(s)
			var speed := clampf(p.speed + along * 0.8 + (150.0 if far > 1500.0 else 0.0), 120.0, 480.0)
			desired = AI.avoid_terrain(a, g, desired, 90.0)
			AI.steer(a, desired, 1.2 if far > 600.0 else 2.0, dt, speed, 2.2)
			a.throttle = clampf((speed - 180.0) / 220.0, 0.1, 1.0)
			return
		var t := target
		desired = AI.lead_point(a, t, a.speed * 1.7) - a.pos
		var dist := a.pos.distance_to(t.pos)
		var spd := clampf(t.speed + (90.0 if dist > 900.0 else 10.0), 180.0, 380.0)
		desired = AI.avoid_terrain(a, g, desired, 120.0)
		AI.steer(a, desired, 1.1, dt, spd)
		a.throttle = 0.9 if spd > 300.0 else 0.45
		_gun.fire(a, g, t, _spec, dt)
		if t.kind != "ace":
			_msl.fire(a, g, t, dt, 16.0, 2400.0, 1.8)


# ---------------------------------------------------------------- Ace

class AceBrain:
	var stage := 1
	var state := "entry"  # entry | loop | evade | attack | joustOut | joustIn | retreat
	var state_t := 0.0
	var pressure := 0.0
	var forced_low_t := 0.0
	var enrage_shield := 0.0
	var evade_chance := 0.72
	var retreating := false
	var _evade_dir := 1.0
	var _roll_t := 0.0
	var _roll_dir := 1.0
	var _gun := GunControl.new()
	var _msl := MissileControl.new()
	var _spec := GunSpec.new(1300.0, 0.06, 14.0, 2.1, 0.013, 1.0, 1.1)

	func retreat() -> void:
		retreating = true
		state = "retreat"

	func update(a: Aircraft, g: Game, dt: float) -> void:
		a.flare_cooldown -= dt
		state_t += dt
		var p := g.player
		var desired: Vector3
		var rel := p.pos - a.pos
		var dist := rel.length()
		rel /= maxf(dist, 1.0)
		if state == "retreat":
			desired = -rel
			desired.y = 0.35
			AI.steer(a, desired, 0.9, dt, 430.0, 0.6)
			a.throttle = 1.0
			return
		# Pressure builds while the player holds the ace in their sights from behind.
		var player_behind := a.fwd.dot(rel) < -0.4 and p.fwd.dot(-rel) > 0.88 and dist < 1800.0
		if forced_low_t > 0.0:
			forced_low_t -= dt
			if forced_low_t <= 0.0:
				g.on_ace_recovered(a)
		else:
			pressure = clampf(pressure + (0.11 if player_behind else -0.025) * dt, 0.0, 1.0)
			if pressure >= 1.0:
				pressure = 0.0
				forced_low_t = 6.5
				g.on_ace_forced_low(a)
		if stage == 1 and a.hp <= a.max_hp * 0.5:
			stage = 2
			state = "joustOut"
			state_t = 0.0
			a.hp = a.max_hp * 0.5
			forced_low_t = 0.0
			pressure = 0.0
			enrage_shield = 2.5
			g.on_ace_enraged(a)
		if enrage_shield > 0.0:
			enrage_shield -= dt
			a.hp = maxf(a.hp, a.max_hp * 0.5)
		var low := forced_low_t > 0.0
		if low:
			a.armor = 1.15
			evade_chance = 0.35
		elif stage == 1:
			a.armor = 0.45 if a.pos.y > 1300.0 else 0.7
			evade_chance = 0.78
		else:
			a.armor = 0.8
			evade_chance = 0.55
		var speed := 330.0
		var turn := 1.32 if stage == 1 else 1.5
		var fire := false
		if low:
			desired = MathX.horizontal(a.fwd) + a.right * (sin(g.time * 0.9) * 0.4)
			desired.y = clampf((_low_alt(a, g) - a.pos.y) / 350.0, -0.9, 0.15)
			speed = 255.0
			turn = 0.95
			fire = dist < 900.0
		else:
			match state:
				"entry":
					desired = p.pos + p.vel * 0.6 - a.pos
					speed = 400.0
					fire = true
					if (dist < 280.0 and state_t > 2.0) or state_t > 10.0:
						_next(a, player_behind)
				"loop":
					desired = a.fwd + a.up * 1.5
					speed = 320.0
					turn = 1.15
					if state_t > 2.8:
						_next(a, player_behind)
				"evade":
					if fmod(state_t, 1.3) < dt:
						_evade_dir = -_evade_dir
					desired = a.fwd * 0.4 + a.right * (_evade_dir * 1.5) + a.up * 0.7
					speed = 340.0
					turn *= 1.15
					if state_t > 2.6:
						_next(a, player_behind)
				"attack":
					desired = AI.lead_point(a, p, a.speed * 1.5) - a.pos
					speed = clampf(p.speed + 40.0, 260.0, 400.0)
					fire = true
					if state_t > (5.0 if stage == 1 else 4.0) or (player_behind and state_t > 1.5):
						_next(a, player_behind)
				"joustOut":
					desired = -rel
					desired.y = clampf((1100.0 - a.pos.y) / 800.0, -0.3, 0.4)
					speed = 380.0
					if dist > 2300.0 or state_t > 7.0:
						state = "joustIn"
						state_t = 0.0
				"joustIn":
					desired = p.pos + p.vel * 0.5 - a.pos
					speed = 400.0
					turn = 1.7
					fire = true
					if dist < 260.0 or (state_t > 3.0 and a.fwd.dot(rel) < 0.0) or state_t > 12.0:
						_next(a, player_behind)
				_:
					desired = a.fwd
		# Barrel roll visual for dodges.
		if _roll_t > 0.0:
			_roll_t -= dt
			a.roll_visual = _roll_dir * (1.0 - _roll_t / 0.6) * TAU
			a.pos += a.right * (_roll_dir * 50.0 * dt)
			if _roll_t <= 0.0:
				a.roll_visual = 0.0
		desired = AI.avoid_terrain(a, g, desired, 90.0 if low else 160.0)
		AI.steer(a, desired, turn, dt, speed, 0.9)
		a.throttle = 1.0 if speed > 340.0 else 0.55
		if fire and p.alive:
			_gun.fire(a, g, p, _spec, dt)
			_msl.fire(a, g, p, dt, 8.0 if stage == 1 else 5.5, 2600.0, 1.0 if stage == 1 else 0.8)

	func _low_alt(a: Aircraft, g: Game) -> float:
		return g.terrain.ground(a.pos.x + a.vel.x * 2.0, a.pos.z + a.vel.z * 2.0) + 260.0

	func _next(a: Aircraft, player_behind: bool) -> void:
		state_t = 0.0
		if stage == 2:
			if randf() < 0.65:
				state = "joustOut"
			else:
				state = "evade" if player_behind else "attack"
			return
		if player_behind:
			state = "evade" if randf() < 0.6 else "loop"
		elif a.pos.y < 1500.0:
			state = "loop"
		else:
			state = "attack" if randf() < 0.7 else "loop"

	func on_hit(_a: Aircraft, _g: Game, weapon: String) -> void:
		if forced_low_t <= 0.0:
			pressure = clampf(pressure + (0.12 if weapon == "missile" else 0.01), 0.0, 1.0)

	func on_missile_incoming(a: Aircraft, m: Missile, g: Game) -> bool:
		if retreating:
			return true
		if randf() < evade_chance:
			_roll_t = 0.6
			_roll_dir = -1.0 if (m.pos - a.pos).dot(a.right) > 0.0 else 1.0
			if a.flares <= 0:
				a.flares = 1
			AI.drop_flares(a, g)
			g.on_ace_dodge(a)
			return true
		return false
