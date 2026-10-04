class_name Missile
extends RefCounted
## One pooled missile: body mesh, exhaust flame and a world-space smoke trail.

var active := false
var pos := Vector3.ZERO
var dir := Vector3(0, 0, -1)
var speed := 0.0
var max_speed := 640.0
var accel := 320.0
var turn := 2.6
var life := 0.0
var damage := 100.0
var proximity := 14.0
var target: Aircraft = null
var owner: Aircraft = null
var team := "blue"
var age := 0.0
var evade_checked := false
## Fooled by flares or a dodge: the fuse ignores aircraft from now on.
var spoofed := false
var decoy: Flare = null
var root: Node3D
var flame: Node3D
var smoke: CPUParticles3D
var glow: CPUParticles3D


func _init() -> void:
	var m := Models.missile()
	root = m.root
	flame = m.flame
	root.visible = false
	smoke = Fx.emitter(false, 170, 3.0, 2.2, 16.0, Color(0.93, 0.94, 0.95, 0.65), Color(0.8, 0.82, 0.86, 0.0), false)
	smoke.lifetime_randomness = 0.3
	smoke.initial_velocity_max = 2.0
	smoke.gravity = Vector3(0, 1.5, 0)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 1.5
	smoke.position = Vector3(0, 0, 3.5)
	root.add_child(smoke)
	glow = Fx.emitter(true, 10, 0.07, 4.0, 1.5, Color(1, 0.85, 0.5, 1), Color(1, 0.4, 0.1, 0), false)
	glow.initial_velocity_max = 0.0
	glow.position = Vector3(0, 0, 2.0)
	root.add_child(glow)


func launch(p_owner: Aircraft, p_target: Aircraft, spec: Array, launch_bonus: float) -> void:
	active = true
	max_speed = spec[0]
	accel = spec[1]
	turn = spec[2]
	life = spec[3]
	damage = spec[4]
	proximity = spec[5]
	owner = p_owner
	team = p_owner.team
	target = p_target
	decoy = null
	evade_checked = false
	spoofed = false
	age = 0.0
	speed = p_owner.speed + launch_bonus
	dir = p_owner.fwd
	pos = p_owner.pos - p_owner.up * 1.6 + p_owner.right * randf_range(-2.0, 2.0)
	root.visible = true
	sync()
	smoke.emitting = true
	glow.emitting = true


func sync() -> void:
	root.global_transform = Transform3D(Basis(MathX.quat_from_fwd_up(dir, Vector3.UP)), pos)
	flame.scale = Vector3(1, 1, 2.5 + randf() * 1.5)


func deactivate() -> void:
	active = false
	root.visible = false
	target = null
	if smoke:
		smoke.emitting = false
		glow.emitting = false
