class_name Fleet
extends Node3D
## The carrier group steams north (-Z). Positions are a pure function of fleet time so
## checkpoints can restore them exactly.

const OFFSETS := [["carrier", 0.0, 0.0, 1.0], ["destroyer", -620.0, -700.0, 1.0], ["destroyer", 560.0, 520.0, 1.0], ["destroyer", -480.0, 1100.0, 1.25]]
const CATAPULT_X := 8.0
const CATAPULT_Y := 24.2
const CATAPULT_Z_START := -40.0
const CATAPULT_Z_END := -168.0

var ships: Array[Node3D] = []
var carrier: Node3D
var time := 0.0
var _radar: Node3D
var steam: CPUParticles3D


func _ready() -> void:
	for o in OFFSETS:
		var s: Node3D = Models.carrier() if o[0] == "carrier" else Models.destroyer()
		s.scale = Vector3.ONE * float(o[3])
		var wk := Models.wake(44.0 if o[0] == "carrier" else 20.0, 900.0 if o[0] == "carrier" else 520.0)
		wk.position.z = 140.0 if o[0] == "carrier" else 70.0
		s.add_child(wk)
		s.set_meta("offset", Vector3(o[1], 0, o[2]))
		add_child(s)
		ships.append(s)
	carrier = ships[0]
	_radar = carrier.get_node("radar")
	for p in [[-26, 118, 0.5], [-18, 126, 0.5], [-30, 96, 0.4], [25, 72, -0.4], [22, -8, PI]]:
		var m := Models.aircraft("joker")
		var r: Node3D = m.root
		r.position = Vector3(p[0], 24.2, p[1])
		r.rotation.y = p[2]
		for b in m.burners:
			(b as Node3D).visible = false
		carrier.add_child(r)
	steam = Fx.emitter(false, 40, 1.6, 3.0, 12.0, Color(0.95, 0.95, 0.95, 0.5), Color(0.9, 0.9, 0.92, 0.0), false)
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	steam.emission_box_extents = Vector3(3, 0.5, 6)
	steam.direction = Vector3(0, 1, 0)
	steam.spread = 25.0
	steam.initial_velocity_min = 4.0
	steam.initial_velocity_max = 9.0
	steam.position = Vector3(CATAPULT_X + 2.0, 23.2, CATAPULT_Z_START - 10.0)
	carrier.add_child(steam)
	set_time(0.0)


func carrier_pos() -> Vector3:
	return Vector3(0, 0, -Cfg.FLEET_SPEED * time)


func set_time(t: float) -> void:
	time = t
	var base := carrier_pos()
	for s in ships:
		var o: Vector3 = s.get_meta("offset")
		s.position = Vector3(base.x + o.x, s.position.y, base.z + o.z)


func update(dt: float, real_time: float) -> void:
	set_time(time + dt)
	for i in ships.size():
		var s := ships[i]
		s.rotation.z = sin(real_time * 0.5 + i) * 0.006
		s.rotation.x = sin(real_time * 0.37 + i * 2.0) * 0.004
		s.position.y = sin(real_time * 0.6 + i) * 0.4
	if _radar:
		_radar.rotation.y = real_time * 2.0


## World position of a point on the carrier deck (carrier-local coordinates).
func deck_point(x: float, y: float, z: float) -> Vector3:
	return carrier_pos() + Vector3(x, y, z)
