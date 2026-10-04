class_name Bot
extends RefCounted
## Test pilot for automated runs. It only writes the same control fields the keyboard and
## gamepad feed (pitch, roll, yaw, boost, brake, guns, missile, roll_tap), so it exercises
## the real flight model, lock-on, weapons and mission scripting (port of debugbot.ts).

var enabled := true
var _missile_t := 0.0
var _rolled_ring := -1
var _evade_t := 0.0


func drive(g: Game, dt: float) -> void:
	if not enabled or not g.controls_enabled or not g.player.alive or g.state != "play":
		return
	var p := g.player
	var inp := g.controls
	var cp := g.mission.active_checkpoint()
	var t: Aircraft = g.target if g.target != null and g.target.targetable() else null
	var ring_kind := ""
	var aim: Vector3
	if not cp.is_empty():
		ring_kind = cp.kind
		var d: float = (cp.pos as Vector3).distance_to(p.pos)
		aim = cp.pos
		if d > 500.0:
			aim -= (cp.normal as Vector3) * minf(600.0, d * 0.4)
	elif t:
		var d := t.pos.distance_to(p.pos)
		aim = t.pos + t.vel * minf(1.5, d / (1150.0 + p.speed))
	else:
		aim = p.pos + p.fwd * 1000.0
		aim.y = maxf(aim.y, 700.0)
	var dist := aim.distance_to(p.pos)
	var dir := (aim - p.pos).normalized()
	var local := p.quat.inverse() * dir
	var lx := local.x
	var ly := local.y
	var lf := -local.z
	var off := atan2(Vector2(lx, ly).length(), lf)
	var roll_err := atan2(lx, ly)
	var bank := g.pc.bank_angle(p)
	var pitch := 0.0
	var roll := 0.0
	var yaw := 0.0
	if off < 0.12:
		pitch = clampf(ly * 14.0, -1.0, 1.0)
		yaw = clampf(lx * 14.0, -1.0, 1.0)
		roll = clampf(-bank * 1.2, -0.6, 0.6)
	else:
		roll = clampf(roll_err * 2.4, -1.0, 1.0)
		if absf(roll_err) < 1.1:
			pitch = clampf(off * 3.0, 0.35, 1.0)
		elif absf(roll_err) > 2.5:
			pitch = -0.2
		else:
			pitch = 0.15
	var agl := p.pos.y - g.terrain.ground(p.pos.x, p.pos.z)
	var ahead := g.terrain.ground(p.pos.x + p.vel.x * 2.0, p.pos.z + p.vel.z * 2.0)
	if (agl < 140.0 and p.vel.y < 0.0) or p.pos.y + p.vel.y * 2.0 < ahead + 80.0:
		roll = clampf(-bank * 2.0, -1.0, 1.0)
		pitch = 1.0 if absf(bank) < 1.2 and p.up.y > 0.0 else 0.0
	if g.settings.invert_pitch:
		pitch = -pitch
	inp.assist = false
	inp.turn = 0.0
	inp.pitch = pitch
	inp.roll = roll
	inp.yaw = yaw
	inp.boost = false
	inp.brake = false
	if ring_kind == "boost":
		inp.boost = dist < 2200.0
	elif ring_kind == "brake":
		inp.brake = dist < 1500.0
	elif not cp.is_empty():
		inp.boost = dist > 1500.0 and off < 0.4
	elif t:
		var td := t.pos.distance_to(p.pos)
		inp.boost = td > 1300.0 and off < 0.6
		inp.brake = off > 1.2 and td < 1200.0
	if ring_kind == "roll" and dist < 420.0 and _rolled_ring != g.mission.ring_idx:
		inp.roll_tap = 1
		_rolled_ring = g.mission.ring_idx
	# Weapons.
	_missile_t -= dt
	inp.guns = false
	if t and cp.is_empty():
		var td := t.pos.distance_to(p.pos)
		if g.locked and not t.ecm and _missile_t <= 0.0:
			inp.missile = true
			_missile_t = 0.9
		if td < 1100.0 and off < 0.07:
			inp.guns = true
	# Missile evasion.
	_evade_t -= dt
	var close := false
	for m in g.weapons.incoming_missiles(p):
		if m.pos.distance_to(p.pos) < 450.0:
			close = true
	if close and _evade_t <= 0.0:
		inp.roll_tap = -1 if randf() < 0.5 else 1
		_evade_t = 1.5
