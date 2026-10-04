class_name MathX
## Small math helpers shared by the simulation (ports of the web build's math.ts).


static func damp(a: float, b: float, lam: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-lam * dt))


static func rand_sign() -> float:
	return -1.0 if randf() < 0.5 else 1.0


## Rotate unit vector `from` toward unit vector `to` by at most `max_angle` radians.
static func rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var d := clampf(from.dot(to), -1.0, 1.0)
	var ang := acos(d)
	if ang < 1e-5 or ang <= max_angle:
		return to
	var axis := from.cross(to)
	if axis.length_squared() < 1e-10:
		axis = Vector3.UP
	return (Quaternion(axis.normalized(), max_angle) * from).normalized()


## Orientation whose local -Z is `fwd` and local +Y is as close to `up` as possible.
static func quat_from_fwd_up(fwd: Vector3, up: Vector3) -> Quaternion:
	var f := fwd.normalized()
	var u := up.normalized()
	if absf(f.dot(u)) > 0.999:
		u = Vector3(0, 0, 1) if absf(f.y) > 0.9 else Vector3.UP
	return Quaternion(Basis.looking_at(f, u))


static func horizontal(v: Vector3) -> Vector3:
	var h := Vector3(v.x, 0.0, v.z)
	if h.length_squared() < 1e-8:
		return Vector3(0, 0, -1)
	return h.normalized()


static func seg_hits_sphere(p0: Vector3, p1: Vector3, c: Vector3, r: float) -> bool:
	var d := p1 - p0
	var len2 := d.length_squared()
	var t := 0.0
	if len2 > 0.0:
		t = clampf((c - p0).dot(d) / len2, 0.0, 1.0)
	return (p0 + d * t).distance_squared_to(c) <= r * r


## Heading in degrees, 0 = north (-Z), clockwise.
static func heading_deg(fwd: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)


static func fmt_score(n: float) -> String:
	var s := str(int(round(absf(n))))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


static func fmt_clock(sec: float, tenths := false) -> String:
	var s := maxf(0.0, sec)
	var m := int(floor(s / 60.0))
	var r := s - m * 60.0
	var whole := int(floor(r))
	var base := "%02d:%02d" % [m, whole]
	if tenths:
		return base + ".%d" % int(floor((r - whole) * 10.0))
	return base


static func _hash(ix: int, iy: int) -> float:
	var h := (ix * 374761393 + iy * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## Smooth value noise in [-1, 1] (camera shake).
static func noise2(x: float, y: float) -> float:
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(ix, iy)
	var b := _hash(ix + 1, iy)
	var c := _hash(ix, iy + 1)
	var d := _hash(ix + 1, iy + 1)
	return (a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy) * 2.0 - 1.0
