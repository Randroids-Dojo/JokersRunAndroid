class_name Fx
extends Node3D
## Visual effects on native CPUParticles3D: explosions (flash, fireball, sparks, smoke), hit
## sparks, splashes, dust, flares, burning debris and explosion flash lighting. Mirrors the
## web build's effects.ts emitters.

const BOOM_POOL := 10
const SPARK_POOL := 14
const SPLASH_POOL := 8
const DUST_POOL := 10
const DEBRIS_POOL := 14

static var mat_add: ShaderMaterial
static var mat_mix: ShaderMaterial
static var quad: QuadMesh

var ground_at: Callable = func(_x: float, _z: float) -> float: return 0.0

var _booms: Array = []  # each: {root, flash, fire, sparks, smoke}
var _boom_i := 0
var _sparks: Array[CPUParticles3D] = []
var _spark_i := 0
var _splashes: Array[CPUParticles3D] = []
var _splash_i := 0
var _dusts: Array[CPUParticles3D] = []
var _dust_i := 0
var _flare_bursts: Array[CPUParticles3D] = []
var _flare_i := 0
var _debris: Array = []  # {node, fire, smoke, vel, life, alive}
var _ring_bursts: Array[CPUParticles3D] = []
var _ring_i := 0
var _lights: Array = [Vector4(0, -1e4, 0, 0), Vector4(0, -1e4, 0, 0), Vector4(0, -1e4, 0, 0)]
var _light_t := [0.0, 0.0, 0.0]
var _light_peak := [0.0, 0.0, 0.0]


static func ensure_materials() -> void:
	if mat_add:
		return
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	mat_add = ShaderMaterial.new()
	mat_add.shader = load("res://shaders/particle_add.gdshader")
	mat_add.set_shader_parameter("tex", load("res://assets/tex/soft.png"))
	mat_mix = ShaderMaterial.new()
	mat_mix.shader = load("res://shaders/particle_mix.gdshader")
	mat_mix.set_shader_parameter("tex", load("res://assets/tex/soft.png"))


static func grad(c0: Color, c1: Color, mid := -1.0, cm := Color()) -> Gradient:
	var g := Gradient.new()
	if mid >= 0.0:
		g.offsets = PackedFloat32Array([0.0, mid, 1.0])
		g.colors = PackedColorArray([c0, cm, c1])
	else:
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([c0, c1])
	return g


static func ramp(v0: float, v1: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, v0))
	c.add_point(Vector2(1.0, v1))
	return c


## Factory shared by every emitter in the game. Sizes are world metres (quad width).
static func emitter(additive: bool, amount: int, lifetime: float, size0: float, size1: float, c0: Color, c1: Color, one_shot: bool) -> CPUParticles3D:
	ensure_materials()
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.material_override = mat_add if additive else mat_mix
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.emitting = false
	var m := maxf(size0, size1)
	p.scale_amount_min = m
	p.scale_amount_max = m
	p.scale_amount_curve = ramp(size0 / m, size1 / m)
	p.color_ramp = grad(c0, c1)
	p.gravity = Vector3.ZERO
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.extra_cull_margin = 400.0
	clear_gpu_buffer(p)
	return p


## Godot allocates a particle node's GPU instance buffer uninitialised and marks every
## instance visible until the node first simulates. Desktop drivers hand back zeroed memory,
## but on phones the leftovers draw as huge coloured quads, so write zeros (zero scale =
## invisible) straight away. `amount` must not change afterwards: that reallocates.
static func clear_gpu_buffer(p: CPUParticles3D) -> void:
	var z := PackedFloat32Array()
	z.resize(p.amount * 20)
	RenderingServer.multimesh_set_buffer(p.get_base(), z)


func _ready() -> void:
	ensure_materials()
	for i in BOOM_POOL:
		var r := Node3D.new()
		add_child(r)
		var flash := emitter(true, 1, 0.18, 30.0, 70.0, Color(1, 0.95, 0.8, 1), Color(1, 0.6, 0.2, 0), true)
		flash.initial_velocity_min = 0.0
		flash.initial_velocity_max = 0.0
		var fire := emitter(true, 30, 1.0, 7.0, 24.0, Color(1, 0.85, 0.45, 1), Color(0.85, 0.22, 0.04, 0), true)
		fire.lifetime_randomness = 0.45
		fire.gravity = Vector3(0, 6, 0)
		var sparks := emitter(true, 18, 1.2, 2.5, 1.2, Color(1, 0.8, 0.4, 1), Color(1, 0.35, 0.1, 0), true)
		sparks.lifetime_randomness = 0.5
		sparks.gravity = Vector3(0, -50, 0)
		var smoke := emitter(false, 20, 4.5, 12.0, 60.0, Color(0.23, 0.23, 0.23, 0.75), Color(0.48, 0.48, 0.5, 0.0), true)
		smoke.lifetime_randomness = 0.45
		smoke.gravity = Vector3(0, 5, 0)
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		for e in [smoke, fire, sparks, flash]:
			r.add_child(e)
		_booms.append({"root": r, "flash": flash, "fire": fire, "sparks": sparks, "smoke": smoke})
	for i in SPARK_POOL:
		# Alternate small (6) and big (11) bursts; resizing an emitter at runtime would
		# reallocate its GPU buffer.
		var s := emitter(true, 6 if i % 2 == 0 else 11, 0.35, 4.0, 0.6, Color(1, 0.9, 0.55, 1), Color(1, 0.45, 0.1, 0), true)
		s.lifetime_randomness = 0.5
		s.initial_velocity_min = 40.0
		s.initial_velocity_max = 120.0
		add_child(s)
		_sparks.append(s)
	for i in SPLASH_POOL:
		var s := emitter(false, 24, 2.8, 6.0, 26.0, Color(0.95, 0.95, 0.95, 0.85), Color(0.8, 0.85, 0.9, 0.0), true)
		s.lifetime_randomness = 0.45
		s.spread = 28.0
		s.gravity = Vector3(0, -45, 0)
		add_child(s)
		_splashes.append(s)
	for i in DUST_POOL:
		var s := emitter(false, 3, 1.2, 3.0, 10.0, Color(0.45, 0.43, 0.38, 0.6), Color(0.5, 0.48, 0.45, 0.0), true)
		s.initial_velocity_min = 3.0
		s.initial_velocity_max = 8.0
		s.spread = 30.0
		add_child(s)
		_dusts.append(s)
	for i in 8:
		var s := emitter(true, 1, 0.14, 18.0, 4.0, Color(1, 1, 0.9, 1), Color(1, 0.8, 0.5, 0), true)
		s.initial_velocity_max = 0.0
		add_child(s)
		_flare_bursts.append(s)
	for i in 3:
		var rb := emitter(true, 30, 0.6, 9.0, 1.0, Color(1, 0.85, 0.4, 1), Color(1, 0.6, 0.1, 0), true)
		rb.initial_velocity_min = 0.0
		rb.initial_velocity_max = 0.0
		rb.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		rb.emission_ring_axis = Vector3(0, 0, 1)
		rb.emission_ring_height = 0.0
		rb.local_coords = false
		add_child(rb)
		_ring_bursts.append(rb)
	for i in DEBRIS_POOL:
		var n := Node3D.new()
		add_child(n)
		var f := emitter(true, 10, 0.3, 4.5, 1.5, Color(1, 0.75, 0.3, 1), Color(0.9, 0.25, 0.05, 0), false)
		f.initial_velocity_max = 0.0
		var sm := emitter(false, 60, 2.2, 3.0, 14.0, Color(0.15, 0.15, 0.15, 0.6), Color(0.3, 0.3, 0.32, 0.0), false)
		sm.initial_velocity_min = 1.0
		sm.initial_velocity_max = 4.0
		sm.gravity = Vector3(0, 3, 0)
		n.add_child(f)
		n.add_child(sm)
		_debris.append({"node": n, "fire": f, "smoke": sm, "vel": Vector3.ZERO, "life": 0.0, "alive": false, "big": false})


func flash(pos: Vector3, peak: float) -> void:
	var slot := 0
	for i in 3:
		if _light_t[i] <= 0.0:
			slot = i
			break
		if _light_peak[i] * _light_t[i] < _light_peak[slot] * _light_t[slot]:
			slot = i
	_light_t[slot] = 1.0
	_light_peak[slot] = peak
	_lights[slot] = Vector4(pos.x, pos.y, pos.z, peak)


func explosion(pos: Vector3, s := 1.0) -> void:
	var b: Dictionary = _booms[_boom_i]
	_boom_i = (_boom_i + 1) % BOOM_POOL
	(b.root as Node3D).global_position = pos
	var flash_e: CPUParticles3D = b.flash
	flash_e.scale_amount_min = 70.0 * s
	flash_e.scale_amount_max = 70.0 * s
	var fire: CPUParticles3D = b.fire
	fire.initial_velocity_min = 25.0 * s
	fire.initial_velocity_max = 85.0 * s
	fire.damping_min = 40.0 * s
	fire.damping_max = 90.0 * s
	fire.scale_amount_min = 24.0 * s
	fire.scale_amount_max = 30.0 * s
	var sparks: CPUParticles3D = b.sparks
	sparks.initial_velocity_min = 120.0 * s
	sparks.initial_velocity_max = 240.0 * s
	sparks.damping_min = 40.0
	sparks.damping_max = 90.0
	var smoke: CPUParticles3D = b.smoke
	smoke.initial_velocity_min = 15.0 * s
	smoke.initial_velocity_max = 45.0 * s
	smoke.damping_min = 12.0 * s
	smoke.damping_max = 30.0 * s
	smoke.scale_amount_min = 45.0 * s
	smoke.scale_amount_max = 75.0 * s
	smoke.emission_sphere_radius = 4.0 * s
	for k in ["flash", "fire", "sparks", "smoke"]:
		var e: CPUParticles3D = b[k]
		e.restart()
		e.emitting = true
	flash(pos, 40.0 * s)


func burning_debris(pos: Vector3, vel: Vector3, count: int) -> void:
	for i in count:
		for d in _debris:
			if d.alive:
				continue
			var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			d.alive = true
			d.big = i == 0
			d.vel = vel * 0.4 + dir * randf_range(40.0, 110.0)
			d.life = randf_range(2.5, 5.0)
			(d.node as Node3D).global_position = pos
			(d.fire as CPUParticles3D).emitting = true
			(d.smoke as CPUParticles3D).emitting = true
			(d.smoke as CPUParticles3D).scale_amount_max = 18.0 if d.big else 11.0
			break


## Sparkle burst around a checkpoint ring as the player flies through it.
func ring_burst(pos: Vector3, basis: Basis, radius: float) -> void:
	var e := _ring_bursts[_ring_i]
	_ring_i = (_ring_i + 1) % _ring_bursts.size()
	e.global_transform = Transform3D(basis.orthonormalized(), pos)
	e.emission_ring_radius = radius
	e.emission_ring_inner_radius = radius
	e.restart()
	e.emitting = true


func hit_sparks(pos: Vector3, big := false) -> void:
	# Even slots hold 6-particle emitters, odd slots 11.
	_spark_i = (_spark_i + 1) % (SPARK_POOL / 2)
	var s := _sparks[_spark_i * 2 + (1 if big else 0)]
	s.global_position = pos
	s.scale_amount_max = 5.0 if big else 3.5
	s.scale_amount_min = s.scale_amount_max
	s.restart()
	s.emitting = true


func splash(pos: Vector3, s := 1.0) -> void:
	var e := _splashes[_splash_i]
	_splash_i = (_splash_i + 1) % SPLASH_POOL
	e.global_position = Vector3(pos.x, 1.0, pos.z)
	e.initial_velocity_min = 30.0 * s
	e.initial_velocity_max = 90.0 * s
	e.scale_amount_min = 26.0 * s
	e.scale_amount_max = 26.0 * s
	e.restart()
	e.emitting = true


func dust(pos: Vector3) -> void:
	var e := _dusts[_dust_i]
	_dust_i = (_dust_i + 1) % DUST_POOL
	e.global_position = pos + Vector3(0, 1, 0)
	e.restart()
	e.emitting = true


func flare_burst(pos: Vector3) -> void:
	var e := _flare_bursts[_flare_i]
	_flare_i = (_flare_i + 1) % _flare_bursts.size()
	e.global_position = pos
	e.restart()
	e.emitting = true


func update(dt: float) -> void:
	for d in _debris:
		if not d.alive:
			continue
		d.life -= dt
		d.vel.y -= 30.0 * dt
		d.vel *= exp(-0.4 * dt)
		var n: Node3D = d.node
		n.global_position += d.vel * dt
		var gh: float = ground_at.call(n.global_position.x, n.global_position.z)
		if n.global_position.y <= gh or d.life <= 0.0:
			if n.global_position.y <= gh + 2.0:
				if gh <= 0.5:
					splash(n.global_position, 0.8 if d.big else 0.4)
				else:
					dust(n.global_position)
			d.alive = false
			(d.fire as CPUParticles3D).emitting = false
			(d.smoke as CPUParticles3D).emitting = false
	for i in 3:
		if _light_t[i] > 0.0:
			_light_t[i] = maxf(0.0, _light_t[i] - dt * 3.2)
			var l: Vector4 = _lights[i]
			l.w = _light_peak[i] * _light_t[i] * _light_t[i]
			_lights[i] = l
		else:
			_lights[i] = Vector4(0, -1e4, 0, 0)
	RenderingServer.global_shader_parameter_set("flash0", _lights[0])
	RenderingServer.global_shader_parameter_set("flash1", _lights[1])
	RenderingServer.global_shader_parameter_set("flash2", _lights[2])


func clear() -> void:
	for e in _ring_bursts:
		e.emitting = false
	for b in _booms:
		for k in ["flash", "fire", "sparks", "smoke"]:
			(b[k] as CPUParticles3D).emitting = false
	for d in _debris:
		d.alive = false
		(d.fire as CPUParticles3D).emitting = false
		(d.smoke as CPUParticles3D).emitting = false
	for i in 3:
		_light_t[i] = 0.0
