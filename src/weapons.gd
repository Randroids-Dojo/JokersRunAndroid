class_name Weapons
extends Node3D
## Guns (tracer bullets, segment-sphere hits), homing missiles with lead pursuit and smoke
## trails, flares and spoofing. Port of the web build's weapons.ts.

const MAX_BULLETS := 600
const MAX_MISSILES := 40

# Bullets as packed parallel arrays; the first `_count` entries are live.
var _b_pos := PackedVector3Array()
var _b_prev := PackedVector3Array()
var _b_vel := PackedVector3Array()
var _b_life := PackedFloat32Array()
var _b_dmg := PackedFloat32Array()
var _b_team := PackedByteArray()  # 0 blue, 1 red
var _b_owner: Array = []
var _count := 0

var missiles: Array[Missile] = []
var flares: Array[Flare] = []
var _flare_pool: Array[Flare] = []
var _tracers: MultiMeshInstance3D
var _mm: MultiMesh
var _buf := PackedFloat32Array()


func _ready() -> void:
	for arr in [_b_pos, _b_prev, _b_vel]:
		arr.resize(MAX_BULLETS)
	_b_life.resize(MAX_BULLETS)
	_b_dmg.resize(MAX_BULLETS)
	_b_team.resize(MAX_BULLETS)
	_b_owner.resize(MAX_BULLETS)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 0.45, 1.0)
	box.material = Models.basic(Color(1, 1, 1, 0.95), true, false)
	_mm.mesh = box
	_mm.instance_count = MAX_BULLETS
	_mm.visible_instance_count = 0
	_buf.resize(MAX_BULLETS * 16)
	_tracers = MultiMeshInstance3D.new()
	_tracers.multimesh = _mm
	_tracers.extra_cull_margin = 16384.0
	_tracers.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	add_child(_tracers)
	for i in MAX_MISSILES:
		var m := Missile.new()
		add_child(m.root)
		missiles.append(m)
	for i in 24:
		var f := Flare.new()
		add_child(f.node)
		_flare_pool.append(f)


func fire_bullet(owner: Aircraft, origin: Vector3, dir: Vector3, spd: float, damage: float, life: float) -> void:
	if _count >= MAX_BULLETS:
		return
	var i := _count
	_count += 1
	_b_pos[i] = origin
	_b_prev[i] = origin
	_b_vel[i] = dir * spd + owner.fwd * owner.speed
	_b_life[i] = life
	_b_dmg[i] = damage
	_b_team[i] = 0 if owner.team == "blue" else 1
	_b_owner[i] = owner


func _remove_bullet(i: int) -> void:
	var last := _count - 1
	if i != last:
		_b_pos[i] = _b_pos[last]
		_b_prev[i] = _b_prev[last]
		_b_vel[i] = _b_vel[last]
		_b_life[i] = _b_life[last]
		_b_dmg[i] = _b_dmg[last]
		_b_team[i] = _b_team[last]
		_b_owner[i] = _b_owner[last]
	_b_owner[last] = null
	_count -= 1


func fire_missile(owner: Aircraft, target: Aircraft, spec: Array, launch_bonus: float) -> Missile:
	for m in missiles:
		if m.active:
			continue
		m.launch(owner, target, spec, launch_bonus)
		return m
	return null


func drop_flares(owner: Aircraft) -> void:
	for i in 4:
		var f: Flare = null
		for c in _flare_pool:
			if c.life <= 0.0:
				f = c
				break
		if f == null:
			return
		f.pos = owner.pos - owner.fwd * 6.0
		f.vel = owner.fwd * (owner.speed * 0.35) + owner.right * ((-1.0 if i % 2 == 0 else 1.0) * randf_range(25.0, 60.0)) + owner.up * randf_range(-30.0, 10.0)
		f.life = randf_range(2.2, 3.2)
		f.start()
		flares.append(f)


## Break the lock and send the missile wide so it can no longer connect.
func spoof(m: Missile, from: Aircraft) -> void:
	m.target = null
	m.spoofed = true
	m.decoy = flares[flares.size() - 1] if flares.size() > 0 else null
	var side := (m.pos - from.pos).cross(from.up).normalized()
	if side.length_squared() > 0.5:
		m.dir = (m.dir + side * 0.25).normalized()


func update(dt: float, g: Game) -> void:
	var aircraft := g.aircraft
	# Bullets.
	var i := 0
	while i < _count:
		var prev := _b_pos[i]
		var v := _b_vel[i]
		v.y -= 4.0 * dt
		_b_vel[i] = v
		var p := prev + v * dt
		_b_prev[i] = prev
		_b_pos[i] = p
		_b_life[i] -= dt
		if _b_life[i] <= 0.0:
			_remove_bullet(i)
			continue
		var team := _b_team[i]
		var hit := false
		var reach := v.length() * dt + 40.0
		for a in aircraft:
			if (team == 0) == (a.team == "blue") or not a.alive or a.hidden or a.frozen:
				continue
			if absf(a.pos.x - p.x) > reach or absf(a.pos.z - p.z) > reach or absf(a.pos.y - p.y) > reach:
				continue
			if MathX.seg_hits_sphere(prev, p, a.pos, a.radius * (1.15 if team == 0 else 0.8)):
				g.on_bullet_hit(a, _b_owner[i], _b_dmg[i], p)
				hit = true
				break
		if hit:
			_remove_bullet(i)
			continue
		var gh := g.terrain.ground(p.x, p.z)
		if p.y < gh:
			if randf() < 0.35:
				if gh <= 0.1:
					g.fx.splash(p, 0.15)
				else:
					g.fx.dust(p)
			_remove_bullet(i)
			continue
		i += 1
	# Flares.
	for k in range(flares.size() - 1, -1, -1):
		var f := flares[k]
		f.life -= dt
		f.vel.y -= 25.0 * dt
		f.vel *= exp(-1.2 * dt)
		f.pos += f.vel * dt
		f.node.global_position = f.pos
		if f.life <= 0.0:
			f.stop()
			flares.remove_at(k)
	# Missiles.
	for m in missiles:
		if not m.active:
			continue
		m.age += dt
		m.life -= dt
		m.speed = minf(m.max_speed, m.speed + m.accel * dt)
		var t := m.target
		if t != null and (not t.alive or t.hidden or t.frozen):
			m.target = null
		if m.target != null:
			var tgt := m.target
			var to_t := tgt.pos - m.pos
			var dist := to_t.length()
			# Missiles that overshoot lose their lock.
			if to_t.dot(m.dir) < -0.2 * dist and dist > 60.0:
				m.target = null
			else:
				var closing := maxf(80.0, m.speed - tgt.vel.dot(to_t) / maxf(dist, 1.0))
				var t_go := clampf(dist / closing, 0.0, 3.0)
				var aim := tgt.pos + tgt.vel * (t_go * 0.9)
				var desired := (aim - m.pos).normalized()
				var turn := m.turn * 0.3 if m.age < 0.2 else m.turn
				m.dir = MathX.rotate_toward(m.dir, desired, turn * dt)
				if not m.evade_checked and dist < 650.0 and tgt.brain != null and tgt.brain.has_method("on_missile_incoming"):
					m.evade_checked = true
					if tgt.brain.on_missile_incoming(tgt, m, g):
						spoof(m, tgt)
				if tgt.missile_jammer and dist < 320.0:
					spoof(m, tgt)
					m.dir = (m.dir + tgt.up * 0.6).normalized()
					g.on_missile_jammed(tgt, m)
		elif m.decoy != null:
			var dd := (m.decoy.pos - m.pos).normalized()
			m.dir = MathX.rotate_toward(m.dir, dd, m.turn * 0.6 * dt)
		var mprev := m.pos
		m.pos += m.dir * (m.speed * dt)
		var detonated := false
		if not m.spoofed and m.age >= 0.15:
			for a in aircraft:
				if a.team == m.team or not a.alive or a.hidden or a.frozen:
					continue
				if MathX.seg_hits_sphere(mprev, m.pos, a.pos, a.radius * 0.6 + m.proximity):
					g.on_missile_hit(a, m)
					detonated = true
					break
		if not detonated:
			var gh := g.terrain.ground(m.pos.x, m.pos.z)
			if m.pos.y < gh + 1.0 or g.terrain.hits_structure(m.pos, 1.0):
				g.on_missile_ground(m)
				detonated = true
			elif m.life <= 0.0:
				g.fx.explosion(m.pos, 0.35)
				detonated = true
		if detonated:
			m.deactivate()
		else:
			m.sync()


## Per render frame: rebuild tracer instances (one bulk buffer upload).
func render() -> void:
	var n := _count
	for i in n:
		var v := _b_vel[i]
		var sp := v.length()
		var dir := v / maxf(sp, 1.0)
		var length := minf(34.0, sp * 0.026)
		var basis := Basis(Quaternion(Vector3(0, 0, 1), dir))
		basis.z *= length
		var o := _b_pos[i] - v * 0.013
		var k := i * 16
		_buf[k] = basis.x.x
		_buf[k + 1] = basis.y.x
		_buf[k + 2] = basis.z.x
		_buf[k + 3] = o.x
		_buf[k + 4] = basis.x.y
		_buf[k + 5] = basis.y.y
		_buf[k + 6] = basis.z.y
		_buf[k + 7] = o.y
		_buf[k + 8] = basis.x.z
		_buf[k + 9] = basis.y.z
		_buf[k + 10] = basis.z.z
		_buf[k + 11] = o.z
		if _b_team[i] == 0:
			_buf[k + 12] = 1.6
			_buf[k + 13] = 1.25
			_buf[k + 14] = 0.55
		else:
			_buf[k + 12] = 1.6
			_buf[k + 13] = 0.4
			_buf[k + 14] = 0.25
		_buf[k + 15] = 0.95
	_mm.buffer = _buf
	_mm.visible_instance_count = n


func clear() -> void:
	for i in _count:
		_b_owner[i] = null
	_count = 0
	for m in missiles:
		m.deactivate()
	for f in flares:
		f.stop()
	flares.clear()
	_mm.visible_instance_count = 0


func incoming_missiles(target: Aircraft) -> Array[Missile]:
	var out: Array[Missile] = []
	for m in missiles:
		if m.active and m.target == target:
			out.append(m)
	return out


func active_red_missiles() -> int:
	var n := 0
	for m in missiles:
		if m.active and m.team == "red":
			n += 1
	return n
