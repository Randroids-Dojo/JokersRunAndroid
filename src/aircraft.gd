class_name Aircraft
extends RefCounted
## Shared aircraft state (player, wingmen, fighters, scouts, drones, ace).

static var _next_id := 1

var id: int
var kind: String  # player | wingman | fighter | scout | drone | ace
var team: String  # blue | red
var label: String
var callsign := ""
var root: Node3D
var burners: Array[Node3D] = []
var radome: Node3D
var fx: AircraftFx

var pos := Vector3.ZERO
var quat := Quaternion.IDENTITY
var vel := Vector3.ZERO
var fwd := Vector3(0, 0, -1)
var up := Vector3.UP
var right := Vector3.RIGHT
var speed := 200.0
var throttle := 0.5
var hp := 100.0
var max_hp := 100.0
var radius := 11.0
var alive := true
var hidden := false
var frozen := false
var invulnerable := false
## Damage from non-player sources cannot push hp below this fraction.
var hp_floor_from_others := 0.0
var mission_target := false
var ecm := false
var missile_jammer := false
var armor := 1.0
var brain: RefCounted = null
var flares := 0
var flare_cooldown := 0.0
var gun_cooldown := 0.0
var missile_cooldown := 0.0
var upload := 0.0
var upload_pause := 0.0
var last_hit_time := -100.0
var last_hit_weapon := ""
var last_hit_by_player := false
var last_hit_dist := 0.0
var wreck := false
var wreck_time := 0.0
var wreck_spin := 0.0
var wreck_vel := Vector3.ZERO
var whoosh_cooldown := 0.0
var g_load := 0.0
## Visual roll offset (barrel rolls).
var roll_visual := 0.0
## Free-form tag used by the mission script.
var tag := ""
## Wingtip vapour trail ids in the shared Trails batch.
var vapor_trails := [-1, -1]


func _init(p_kind: String, p_team: String, model: Dictionary, p_label: String) -> void:
	id = _next_id
	_next_id += 1
	kind = p_kind
	team = p_team
	label = p_label
	root = model.root
	for b in model.burners:
		burners.append(b)
	radome = model.radome


func update_basis() -> void:
	fwd = quat * Vector3(0, 0, -1)
	up = quat * Vector3.UP
	right = quat * Vector3.RIGHT
	vel = fwd * speed


func targetable() -> bool:
	return alive and not hidden and not frozen


func sync_mesh(time: float) -> void:
	var vis := not hidden and not frozen
	root.visible = vis
	if not vis:
		return
	var basis := Basis(quat)
	if roll_visual != 0.0:
		basis = basis * Basis(Vector3(0, 0, 1), -roll_visual)
	root.global_transform = Transform3D(basis, pos)
	var flick := 0.85 + 0.15 * sin(time * 60.0 + id)
	for b in burners:
		var length := (1.2 + throttle * 4.2) * flick if alive else 0.001
		b.scale = Vector3(1, 1, length)
	if radome:
		radome.rotation.y = time * 1.6
