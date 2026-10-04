class_name HudRadar
extends Control
## Heading-up radar: coastlines, combat-area boundary, fleet, checkpoint, contacts (mission
## targets pinned to the rim), missiles, the incoming ping ring and a rotating sweep.

var hud: Hud
var game: Game
var _coast: Array[PackedVector2Array] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var west := PackedVector2Array()
	var east := PackedVector2Array()
	var z := -8300.0
	while z <= 6400.0:
		west.append(Vector2(Terrain.coast_w(z), z))
		east.append(Vector2(Terrain.coast_e(z), z))
		z += 150.0
	_coast = [west, east]


func _draw() -> void:
	var g := game
	if g == null or not hud.visible_hud or g.cinematic:
		return
	var S := size.x
	var R := S / 2.0 - 4.0
	var c := Vector2(S / 2.0, S / 2.0)
	var p := g.player
	var range_m := hud.radar_range
	var hdg := atan2(p.fwd.x, -p.fwd.z)
	var cos_h := cos(hdg)
	var sin_h := sin(hdg)
	var to_radar := func(x: float, z: float) -> Vector2:
		var dx := x - p.pos.x
		var dz := z - p.pos.z
		return c + Vector2(dx * cos_h + dz * sin_h, -dx * sin_h + dz * cos_h) / range_m * R

	draw_circle(c, R, Color(0.012, 0.055, 0.04, 0.62), true, -1.0, true)
	for f in [1.0 / 3.0, 2.0 / 3.0]:
		draw_arc(c, R * f, 0, TAU, 48, Cfg.C_HUD_FAINT, 1.0, true)
	draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Cfg.C_HUD_FAINT, 1.0)
	draw_line(c - Vector2(0, R), c + Vector2(0, R), Cfg.C_HUD_FAINT, 1.0)

	# Sweep: a conic fade starting a quarter turn behind the beam angle.
	var a0 := fmod(g.real_time * 1.6, TAU) - PI / 2.0
	var n := 14
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([Color(0.651, 1, 0.816, 0.12)])
	for i in n + 1:
		var a := a0 + TAU * 0.12 * float(i) / n
		pts.append(c + Vector2(cos(a), sin(a)) * R)
		cols.append(Color(0.651, 1, 0.816, 0.22 * (1.0 - float(i) / n)))
	draw_polygon(pts, cols)

	# Coastlines.
	var coast_col := Color(0.651, 1, 0.816, 0.4)
	for line in _coast:
		var prev: Vector2 = to_radar.call(line[0].x, line[0].y)
		for i in range(1, line.size()):
			var cur: Vector2 = to_radar.call(line[i].x, line[i].y)
			var seg := HudOverlay.clip_segment(prev, cur, c, R)
			if not seg.is_empty():
				draw_line(seg[0], seg[1], coast_col, 1.2, true)
			prev = cur
	if g.show_boundary:
		var seg := HudOverlay.clip_segment(to_radar.call(Cfg.BOUNDARY_X, p.pos.z - 30000.0), to_radar.call(Cfg.BOUNDARY_X, p.pos.z + 30000.0), c, R)
		if not seg.is_empty():
			draw_dashed_line(seg[0], seg[1], Color(1, 0.3, 0.24, 0.7), 1.2, 6.0)

	# Ships.
	for s in g.fleet.ships:
		var r: Vector2 = to_radar.call(s.global_position.x, s.global_position.z)
		if r.distance_to(c) > R - 3.0:
			continue
		draw_set_transform(r, -hdg)
		draw_rect(Rect2(-2, -5, 4, 10), Cfg.C_FRIEND)
		draw_set_transform(Vector2.ZERO)

	var cp: Dictionary = g.mission.active_checkpoint()
	if not cp.is_empty():
		var k := _clamp_to(to_radar.call(cp.pos.x, cp.pos.z), c, R - 6.0)
		draw_arc(k, 5.0, 0, TAU, 16, Cfg.C_GOLD, 2.0, true)

	for a in g.aircraft:
		if a == p or not a.targetable():
			continue
		var pos: Vector2 = to_radar.call(a.pos.x, a.pos.z)
		if pos.distance_to(c) > R:
			if not a.mission_target and a.kind != "ace":
				continue
			pos = _clamp_to(pos, c, R - 6.0)
		var col := Cfg.C_FRIEND if a.team == "blue" else (Cfg.C_ACE if a.kind == "ace" else (Cfg.C_TARGET if a.mission_target else (Cfg.C_DRONE if a.kind == "drone" else Cfg.C_HOSTILE)))
		if a.mission_target:
			var pulse := 4.5 + sin(g.real_time * 6.0) * 1.2
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -pulse), pos + Vector2(pulse, 0), pos + Vector2(0, pulse), pos + Vector2(-pulse, 0)]), col)
		else:
			var ah := atan2(a.fwd.x, -a.fwd.z) - hdg
			var sz := 7.0 if a.kind == "ace" else (4.0 if a.team == "blue" else 5.0)
			var tr := Transform2D(ah, pos)
			draw_colored_polygon(PackedVector2Array([tr * Vector2(0, -sz), tr * Vector2(sz * 0.7, sz * 0.8), tr * Vector2(-sz * 0.7, sz * 0.8)]), col)
		if a == g.target:
			draw_rect(Rect2(pos.x - 7, pos.y - 7, 14, 14), Color.WHITE, false, 1.0)

	for m in g.weapons.missiles:
		if not m.active:
			continue
		var r: Vector2 = to_radar.call(m.pos.x, m.pos.z)
		if r.distance_to(c) > R:
			continue
		draw_rect(Rect2(r.x - 1.5, r.y - 1.5, 3, 3), Cfg.C_HOSTILE if m.team == "red" else Color.WHITE)

	if hud.ping_t < 1.6:
		draw_arc(c, maxf(1.0, hud.ping_t / 1.6 * R), 0, TAU, 40, Color(1, 0.3, 0.24, 1.0 - hud.ping_t / 1.6), 2.0, true)

	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 6), c + Vector2(0, 3), c + Vector2(-5, 6)]), Cfg.C_HUD)
	draw_arc(c, R, 0, TAU, 64, Cfg.C_HUD_DIM, 1.5, true)
	HudOverlay.text_at(self, Vector2(S - 6, S - 8), "%d KM" % int(round(range_m / 1000.0)), 10, Cfg.C_HUD_DIM, HORIZONTAL_ALIGNMENT_RIGHT, UiKit.semibold)


static func _clamp_to(r: Vector2, c: Vector2, R: float) -> Vector2:
	var d := r - c
	if d.length() <= R:
		return r
	return c + d.normalized() * R
