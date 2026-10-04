class_name AircraftFx
extends Node3D
## Per-aircraft emitters: battle-damage smoke, burning wreck fire/smoke trail, muzzle flash.

var damage_smoke: CPUParticles3D
var wreck_fire: CPUParticles3D
var wreck_smoke: CPUParticles3D
var muzzle: CPUParticles3D


func _init(with_muzzle := false) -> void:
	damage_smoke = Fx.emitter(false, 50, 2.0, 4.0, 26.0, Color(0.18, 0.18, 0.18, 0.55), Color(0.35, 0.35, 0.36, 0.0), false)
	damage_smoke.initial_velocity_max = 3.0
	damage_smoke.gravity = Vector3(0, 4, 0)
	add_child(damage_smoke)
	wreck_fire = Fx.emitter(true, 14, 0.35, 9.0, 3.0, Color(1, 0.75, 0.3, 1), Color(0.9, 0.25, 0.05, 0), false)
	wreck_fire.initial_velocity_max = 0.0
	add_child(wreck_fire)
	wreck_smoke = Fx.emitter(false, 100, 3.0, 6.0, 26.0, Color(0.14, 0.14, 0.14, 0.65), Color(0.3, 0.3, 0.32, 0.0), false)
	wreck_smoke.initial_velocity_max = 4.0
	wreck_smoke.gravity = Vector3(0, 3, 0)
	add_child(wreck_smoke)
	if with_muzzle:
		muzzle = Fx.emitter(true, 6, 0.06, 3.5, 1.0, Color(1, 0.9, 0.6, 1), Color(1, 0.6, 0.2, 0), false)
		muzzle.initial_velocity_max = 0.0
		muzzle.local_coords = true
		add_child(muzzle)


func follow(a: Aircraft, vdt_live: bool) -> void:
	global_position = a.pos - a.fwd * 8.0
	var severity := 0.0
	if a.alive and not a.invulnerable and a.hp < a.max_hp * 0.5:
		severity = clampf(1.0 - a.hp / (a.max_hp * 0.5), 0.0, 1.0)
	var vis := a.targetable() or a.wreck
	damage_smoke.emitting = vdt_live and vis and severity > 0.0
	if damage_smoke.emitting:
		damage_smoke.color_ramp.colors = PackedColorArray([Color(0.18, 0.18, 0.18, 0.45 * severity + 0.15), Color(0.35, 0.35, 0.36, 0.0)])
	wreck_fire.emitting = vdt_live and a.wreck
	wreck_smoke.emitting = vdt_live and a.wreck
	if muzzle:
		muzzle.global_position = a.pos + a.fwd * 9.5
		if not a.alive or a.hidden:
			muzzle.emitting = false


func stop() -> void:
	damage_smoke.emitting = false
	wreck_fire.emitting = false
	wreck_smoke.emitting = false
	if muzzle:
		muzzle.emitting = false
