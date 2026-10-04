class_name PlayerController
extends RefCounted
## Player flight model: smoothed stick, coordinated banking, boost/brake energy, barrel roll,
## assisted steering for touch, terrain and bridge collisions. Port of the web player.ts.

const X := Vector3(1, 0, 0)
const Y := Vector3(0, 1, 0)
const Z := Vector3(0, 0, 1)

var pitch_cmd := 0.0
var roll_cmd := 0.0
var yaw_cmd := 0.0
var boost_energy := 1.0
var boosting := false
var braking := false
var _boost_regen_wait := 0.0
var roll_time := 0.0
var roll_dir := 0.0
var roll_cooldown := 0.0
var last_roll_at := -100.0
var left_bank_at := -100.0
var pitch_rate_now := 0.0
## Callable(a: Aircraft, dt: float) that owns the aircraft for this step, or null.
var autopilot: Callable = Callable()
var collision_cooldown := 0.0
var last_ground := 0.0


func reset() -> void:
	pitch_cmd = 0.0
	roll_cmd = 0.0
	yaw_cmd = 0.0
	boost_energy = 1.0
	boosting = false
	braking = false
	roll_time = 0.0
	roll_cooldown = 0.0
	autopilot = Callable()
	collision_cooldown = 0.0


func bank_angle(a: Aircraft) -> float:
	return asin(clampf(-a.right.y, -1.0, 1.0))


func update(a: Aircraft, input: Controls, g: Game, dt: float) -> void:
	if autopilot.is_valid():
		autopilot.call(a, dt)
		return
	var inv := -1.0 if g.settings.invert_pitch else 1.0
	var pitch_in := input.pitch * inv
	var roll_in := input.roll
	if input.assist:
		# Assisted steering: the stick points where you want to go.
		var full_bank := atan2(-a.right.y, a.up.y)
		var target := clampf(input.turn, -1.0, 1.0) * 1.22
		var err := wrapf(target - full_bank, -PI, PI)
		roll_in = clampf(err * 2.2, -1.0, 1.0)
		var pull := absf(input.turn) * 0.8 * maxf(0.0, cos(err)) if a.up.y > 0.1 else 0.0
		var nose := asin(clampf(a.fwd.y, -1.0, 1.0))
		var want_nose := clampf(input.pitch * inv, -1.0, 1.0) * 1.15
		var elev := clampf((want_nose - nose) * 3.0, -1.0, 1.0) / maxf(cos(full_bank), 0.35)
		pitch_in = clampf(pull + elev, -1.0, 1.0)
	pitch_cmd = MathX.damp(pitch_cmd, pitch_in, 9.0, dt)
	roll_cmd = MathX.damp(roll_cmd, roll_in, 12.0, dt)
	yaw_cmd = MathX.damp(yaw_cmd, input.yaw, 6.0, dt)

	# Throttle.
	braking = input.brake
	var want_boost := input.boost and not braking
	boosting = want_boost and boost_energy > 0.01
	if boosting:
		boost_energy = maxf(0.0, boost_energy - Cfg.P_BOOST_DRAIN * dt)
		_boost_regen_wait = Cfg.P_BOOST_REGEN_DELAY
	else:
		_boost_regen_wait -= dt
		if _boost_regen_wait <= 0.0:
			boost_energy = minf(1.0, boost_energy + Cfg.P_BOOST_REGEN * dt * g.boost_regen_mult)
	var target_speed := Cfg.P_BOOST if boosting else (Cfg.P_BRAKE if braking else Cfg.P_CRUISE)
	var rate := 0.9 if boosting else (1.8 if braking else 0.55)
	a.speed = MathX.damp(a.speed, target_speed, rate, dt)
	a.speed -= a.fwd.y * 22.0 * dt
	a.speed = clampf(a.speed, Cfg.P_MIN_SPEED, Cfg.P_MAX_SPEED)
	a.throttle = 1.0 if boosting else (0.05 if braking else 0.45)

	var tf: float
	if a.speed < Cfg.P_CRUISE:
		tf = lerpf(1.3, 1.0, (a.speed - Cfg.P_BRAKE) / (Cfg.P_CRUISE - Cfg.P_BRAKE))
	else:
		tf = lerpf(1.0, 0.78, (a.speed - Cfg.P_CRUISE) / (Cfg.P_BOOST - Cfg.P_CRUISE))
	var turn_factor := clampf(tf, 0.75, 1.32)

	var q := a.quat
	pitch_rate_now = pitch_cmd * Cfg.P_PITCH_RATE * turn_factor
	q = q * Quaternion(X, pitch_rate_now * dt)
	q = q * Quaternion(Z, -roll_cmd * Cfg.P_ROLL_RATE * dt)
	q = q * Quaternion(Y, -yaw_cmd * Cfg.P_YAW_RATE * dt)

	# Barrel roll: a fast 360 with a sideways jink.
	roll_cooldown -= dt
	if input.roll_tap != 0 and roll_time <= 0.0 and roll_cooldown <= 0.0:
		roll_time = Cfg.P_ROLL_DURATION
		roll_dir = float(input.roll_tap)
		roll_cooldown = Cfg.P_ROLL_COOLDOWN
		last_roll_at = g.time
		g.on_player_barrel_roll()
	if roll_time > 0.0:
		var t := 1.0 - roll_time / Cfg.P_ROLL_DURATION
		a.roll_visual = roll_dir * t * TAU
		a.pos += a.right * (roll_dir * Cfg.P_ROLL_JINK * sin(t * PI) * dt)
		roll_time -= dt
		if roll_time <= 0.0:
			a.roll_visual = 0.0

	a.quat = q
	a.update_basis()
	var bank := bank_angle(a)
	if bank < -0.45:
		left_bank_at = g.time
	var horiz := sqrt(maxf(0.0, 1.0 - a.fwd.y * a.fwd.y))
	q = Quaternion(Y, -sin(bank) * Cfg.P_BANK_TURN * turn_factor * horiz * dt) * q
	# Gentle auto-level when hands are off.
	if not input.assist and absf(input.roll) < 0.05 and absf(input.pitch) < 0.05 and absf(bank) < 0.9 and a.up.y > 0.2 and roll_time <= 0.0:
		q = q * Quaternion(Z, bank * 1.1 * dt)
	a.quat = q.normalized()
	a.update_basis()
	a.g_load = absf(pitch_rate_now) * a.speed / 9.81

	# Ceiling.
	if a.pos.y > Cfg.P_CEILING and a.fwd.y > 0.0:
		a.quat = (Quaternion(a.right, -0.6 * dt) * a.quat).normalized()
		a.update_basis()
	# Area limit: gently steer back.
	var r := Vector2(a.pos.x - g.area_center.x, a.pos.z - g.area_center.z).length()
	g.out_of_area = r > Cfg.AREA_RADIUS
	if g.out_of_area:
		var want := atan2(g.area_center.x - a.pos.x, -(g.area_center.z - a.pos.z))
		var cur := atan2(a.fwd.x, -a.fwd.z)
		var d := wrapf(want - cur, -PI, PI)
		a.quat = (Quaternion(Y, -clampf(d, -1.0, 1.0) * 0.5 * dt) * a.quat).normalized()
		a.update_basis()

	a.pos += a.vel * dt
	_collide(a, g, dt)


func _collide(a: Aircraft, g: Game, dt: float) -> void:
	collision_cooldown -= dt
	var gh := g.terrain.ground(a.pos.x, a.pos.z)
	last_ground = gh
	var hit_ground := a.pos.y < gh + 3.0
	var hit_struct := g.terrain.hits_structure(a.pos, 4.0)
	if not hit_ground and not hit_struct:
		return
	if hit_ground:
		a.pos.y = gh + 8.0
	if collision_cooldown <= 0.0:
		collision_cooldown = 0.6
		var kind := "terrain"
		if hit_struct:
			kind = "structure"
		elif gh <= 0.5:
			kind = "sea"
		g.on_player_crash(kind)
	# Shove the nose upward and away, whatever the attitude.
	var climb := Vector3(a.fwd.x, 0, a.fwd.z)
	if climb.length_squared() < 1e-4:
		climb = Vector3(0, 0, -1)
	climb = (climb.normalized() * 0.8 + Vector3(0, 0.6, 0)).normalized()
	a.quat = (Quaternion(a.fwd, climb) * a.quat).normalized()
	a.update_basis()
	if hit_struct:
		a.pos += a.fwd * -12.0 + Vector3(0, 10, 0)
