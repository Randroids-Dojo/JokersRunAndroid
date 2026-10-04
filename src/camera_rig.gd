class_name CameraRig
extends Camera3D
## Chase camera with lagged attitude, speed stretch, look-at-target blend, scripted shots
## and trauma shake (port of camera.ts).

## Callable(t: float) -> Dictionary {pos, look, up, fov}, or invalid for the chase cam.
var shot: Callable = Callable()
var shot_t := 0.0
var trauma := 0.0
var fov_now := 68.0
var look_blend := 0.0
var reduced_motion := false
var _cam_quat := Quaternion.IDENTITY
var _snap_next := true
var _shake_t := 0.0


func _ready() -> void:
	fov = 68.0
	near = 2.0
	far = 45000.0
	current = true


func snap() -> void:
	_snap_next = true


func play(s: Callable) -> void:
	shot = s
	shot_t = 0.0
	if not s.is_valid():
		_snap_next = true


func add_trauma(x: float) -> void:
	trauma = minf(1.0, trauma + x * (0.25 if reduced_motion else 1.0))


func _place(pos: Vector3, look: Vector3, up: Vector3) -> void:
	var t := Transform3D(Basis.IDENTITY, pos)
	if (look - pos).length_squared() > 1e-6:
		var u := up
		if absf((look - pos).normalized().dot(u.normalized())) > 0.999:
			u = Vector3(0, 0, 1)
		t = t.looking_at(look, u)
	global_transform = t


func update_rig(dt: float, g: Game) -> void:
	if shot.is_valid():
		shot_t += dt
		var f: Dictionary = shot.call(shot_t)
		_place(f.pos, f.look, f.get("up", Vector3.UP))
		fov_now = f.get("fov", 68.0)
	else:
		var p := g.player
		if _snap_next:
			_cam_quat = p.quat
			_snap_next = false
		else:
			_cam_quat = _cam_quat.slerp(p.quat, 1.0 - exp(-7.5 * dt))
		var stretch := (p.speed - 235.0) * 0.032
		var back := 25.0 + stretch
		var fwd := _cam_quat * Vector3(0, 0, -1)
		var up := _cam_quat * Vector3.UP
		var pos := _cam_quat * Vector3(0, 6.4, back) + p.pos
		var look := p.pos + fwd * 70.0 + up * 3.0
		var t := g.target
		var want_look := g.controls.look and t != null and t.targetable() and g.controls_enabled
		look_blend = MathX.damp(look_blend, 1.0 if want_look else 0.0, 6.0, dt)
		if look_blend > 0.01 and t != null:
			var dir := (t.pos - p.pos).normalized()
			var alt_pos := p.pos - dir * 34.0 + Vector3(0, 9, 0)
			pos = pos.lerp(alt_pos, look_blend)
			look = look.lerp(t.pos, look_blend)
			up = up.lerp(Vector3.UP, look_blend).normalized()
		var gh := g.terrain.ground(pos.x, pos.z)
		if pos.y < gh + 3.0:
			pos.y = gh + 3.0
		_place(pos, look, up)
		var boost_fov := 9.0 if g.pc.boosting else (-5.0 if g.pc.braking else 0.0)
		fov_now = MathX.damp(fov_now, 68.0 + boost_fov, 3.5, dt)
	if trauma > 0.0:
		_shake_t += dt * 30.0
		var s := trauma * trauma
		var amp := 0.3 if reduced_motion else 1.4
		global_position += Vector3(MathX.noise2(_shake_t, 1.3) * s * amp, MathX.noise2(_shake_t, 7.1) * s * amp, 0)
		rotate_object_local(Vector3(0, 0, 1), MathX.noise2(_shake_t, 3.7) * s * 0.03)
		trauma = maxf(0.0, trauma - dt * 1.5)
	if absf(fov - fov_now) > 0.01:
		fov = fov_now
