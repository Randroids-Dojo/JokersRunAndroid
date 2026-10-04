class_name Flare
extends RefCounted
## A decoy flare: falling bright point with a smoke trail. Spoofed missiles chase these.

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var life := 0.0
var node := Node3D.new()
var _fire: CPUParticles3D
var _smoke: CPUParticles3D


func _init() -> void:
	_fire = Fx.emitter(true, 14, 0.18, 6.0, 2.0, Color(1, 0.95, 0.75, 1), Color(1, 0.6, 0.25, 0), false)
	_fire.initial_velocity_max = 0.0
	node.add_child(_fire)
	_smoke = Fx.emitter(false, 30, 1.6, 2.0, 9.0, Color(0.9, 0.9, 0.9, 0.45), Color(0.8, 0.8, 0.8, 0.0), false)
	_smoke.initial_velocity_max = 2.0
	_smoke.gravity = Vector3(0, 1, 0)
	node.add_child(_smoke)


func start() -> void:
	node.global_position = pos
	_fire.emitting = true
	_smoke.emitting = true


func stop() -> void:
	life = 0.0
	_fire.emitting = false
	_smoke.emitting = false
