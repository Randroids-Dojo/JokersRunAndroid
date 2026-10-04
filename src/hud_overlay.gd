class_name HudOverlay
extends Control
## 3D-projected HUD drawn every frame: pitch ladder, heading tape, boresight, missile seeker
## circle, gun lead pipper, target brackets with HP/upload bars and lock diamonds, checkpoint
## marker, off-screen arrows and incoming-missile warnings. Port of hud.ts draw().

var hud: Hud
var game: Game


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _proj(cam: Camera3D, p: Vector3) -> Vector3:
	var s := cam.unproject_position(p)
	return Vector3(s.x, s.y, 1.0 if cam.is_position_behind(p) else 0.0)


## Text with a CSS-like "middle" baseline and a soft dark outline (the web's shadowBlur).
func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER, font: Font = null) -> void:
	HudOverlay.text_at(self, pos, text, size, color, align, font)


static func text_at(ci: CanvasItem, pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER, font: Font = null) -> void:
	var f: Font = font if font else UiKit.semibold
	var w := 300.0
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var base := Vector2(x, pos.y + (f.get_ascent(size) - f.get_descent(size)) / 2.0)
	ci.draw_string_outline(f, base, text, align, w, size, 3, Color(0, 0, 0, 0.45 * color.a))
	ci.draw_string(f, base, text, align, w, size, color)


func _draw() -> void:
	var g := game
	if g == null or not hud.visible_hud or g.cinematic or not g.player.alive:
		return
	var cam := g.rig
	var p := g.player
	var W := size.x
	var H := size.y
	var focal := H / 2.0 / tan(deg_to_rad(cam.fov) / 2.0)
	_draw_ladder(g, cam)
	_draw_heading_tape(g)
	var t: Aircraft = g.target if g.target != null and g.target.targetable() else null
	var t_dist := t.pos.distance_to(p.pos) if t else 900.0
	var bore := _proj(cam, p.pos + p.fwd * clampf(t_dist, 300.0, 1500.0))
	var seek := _proj(cam, p.pos + p.fwd * 1500.0)
	if seek.z == 0.0:
		var r := tan(Cfg.MSL_LOCK_CONE) * focal
		var n := maxi(8, int(TAU * r / 12.0))
		var step := TAU / n
		for i in n:
			draw_arc(Vector2(seek.x, seek.y), r, step * i, step * i + 3.0 / r, 3, Cfg.C_HUD_FAINT, 1.5, true)
	if bore.z == 0.0:
		_draw_boresight(bore.x, bore.y)
	# Gun lead pipper.
	if t and t_dist < 1600.0:
		var tf := t_dist / (Cfg.GUN_SPEED + p.speed)
		var lead := _proj(cam, t.pos + t.vel * tf)
		if lead.z == 0.0:
			var on := Vector2(lead.x - bore.x, lead.y - bore.y).length() < 14.0
			var c := Color.WHITE if on else Cfg.C_HUD
			draw_arc(Vector2(lead.x, lead.y), 9.0, 0, TAU, 24, c, 2.5 if on else 1.5, true)
			draw_rect(Rect2(lead.x - 1.5, lead.y - 1.5, 3, 3), c)
			if on:
				_text(Vector2(lead.x + 14, lead.y), "FIRE", 11, c, HORIZONTAL_ALIGNMENT_LEFT, UiKit.bold)
	for a in g.aircraft:
		if a == p or not a.targetable():
			continue
		_draw_marker(g, a, cam, focal, a == t)
	var cp: Dictionary = g.mission.active_checkpoint()
	if not cp.is_empty():
		var s := _proj(cam, cp.pos)
		var d: float = (cp.pos as Vector3).distance_to(p.pos)
		var lbl := "%s %s" % [cp.label, _fmt_dist(d)]
		if s.z == 0.0 and s.x > 0 and s.x < W and s.y > 0 and s.y < H:
			var pts := PackedVector2Array([Vector2(s.x, s.y - 12), Vector2(s.x + 12, s.y), Vector2(s.x, s.y + 12), Vector2(s.x - 12, s.y), Vector2(s.x, s.y - 12)])
			draw_polyline(pts, Cfg.C_GOLD, 1.5, true)
			_text(Vector2(s.x, s.y + 24), lbl, 12, Cfg.C_GOLD)
		else:
			_edge_arrow(s, Cfg.C_GOLD, lbl)
	for a in g.aircraft:
		if a == p or not a.targetable() or a.team != "red":
			continue
		if a != t and not a.mission_target:
			continue
		var s := _proj(cam, a.pos)
		if s.z == 0.0 and s.x > 20 and s.x < W - 20 and s.y > 20 and s.y < H - 20:
			continue
		var col := Cfg.C_ACE if a.kind == "ace" else (Cfg.C_TARGET if a.mission_target else Cfg.C_HOSTILE)
		_edge_arrow(s, col, "%s %s" % [a.label, _fmt_dist(a.pos.distance_to(p.pos))])
	var incoming := g.weapons.incoming_missiles(p)
	if not incoming.is_empty():
		var blink := int(g.real_time * 6.0) % 2 == 0
		var close := false
		for m in incoming:
			if m.pos.distance_to(p.pos) < 700.0:
				close = true
			var s := _proj(cam, m.pos)
			var dx := s.x - W / 2.0
			var dy := s.y - H / 2.0
			if s.z > 0.0:
				dx = -dx
				dy = -dy
			var ang := atan2(dy, dx)
			var c := Vector2(W / 2.0, H / 2.0) + Vector2(cos(ang), sin(ang)) * 120.0
			var tr := Transform2D(ang, c)
			draw_colored_polygon(PackedVector2Array([tr * Vector2(16, 0), tr * Vector2(-6, -10), tr * Vector2(-6, 10)]), Cfg.C_HOSTILE)
		if blink:
			_text(Vector2(W / 2.0, H * 0.42), "MISSILE — BREAK!" if close else "MISSILE", 22, Cfg.C_HOSTILE, HORIZONTAL_ALIGNMENT_CENTER, UiKit.bold)
			if close and not g.controls.using_touch:
				_text(Vector2(W / 2.0, H * 0.42 + 22.0), "BARREL ROLL: DOUBLE-TAP A / D", 12, Cfg.C_HOSTILE)


func _draw_boresight(x: float, y: float) -> void:
	var pts := PackedVector2Array([Vector2(x - 18, y), Vector2(x - 8, y), Vector2(x - 4, y + 5), Vector2(x, y), Vector2(x + 4, y + 5), Vector2(x + 8, y), Vector2(x + 18, y)])
	draw_polyline(pts, Cfg.C_HUD, 1.6, true)
	draw_line(Vector2(x, y - 4), Vector2(x, y - 10), Cfg.C_HUD, 1.6, true)


func _draw_ladder(g: Game, cam: Camera3D) -> void:
	var p := g.player
	var hdg := atan2(p.fwd.x, -p.fwd.z)
	var origin := cam.global_position
	var center := size / 2.0
	var clip_r := minf(size.x, size.y) * 0.3
	for e in range(-60, 61, 10):
		var er := deg_to_rad(e)
		var span := deg_to_rad(16.0 if e == 0 else 5.0)
		var gap := deg_to_rad(3.2 if e == 0 else 2.0)
		var a1 := _ladder_pt(cam, origin, hdg - span, er)
		var a2 := _ladder_pt(cam, origin, hdg - gap, er)
		var b1 := _ladder_pt(cam, origin, hdg + gap, er)
		var b2 := _ladder_pt(cam, origin, hdg + span, er)
		if a1.z > 0.0 or a2.z > 0.0 or b1.z > 0.0 or b2.z > 0.0:
			continue
		var col := Cfg.C_HUD_DIM if e == 0 else Cfg.C_HUD_FAINT
		for sgm in [[a1, a2], [b1, b2]]:
			var c := clip_segment(Vector2(sgm[0].x, sgm[0].y), Vector2(sgm[1].x, sgm[1].y), center, clip_r)
			if c.is_empty():
				continue
			if e < 0:
				draw_dashed_line(c[0], c[1], col, 1.0, 5.0)
			else:
				draw_line(c[0], c[1], col, 1.4 if e == 0 else 1.0, true)
		var lp := Vector2(b2.x + 5, b2.y)
		if e != 0 and lp.distance_to(center) < clip_r - 6.0:
			_text(lp, str(absi(e)), 11, Cfg.C_HUD_FAINT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.medium)


## The part of segment a-b inside the circle (c, r), or an empty array.
static func clip_segment(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array:
	var d := b - a
	var f := a - c
	var A := d.dot(d)
	if A < 1e-6:
		return [a, b] if f.length() <= r else []
	var B := 2.0 * f.dot(d)
	var C := f.dot(f) - r * r
	var disc := B * B - 4.0 * A * C
	if disc <= 0.0:
		return []
	var sq := sqrt(disc)
	var t0 := maxf(0.0, (-B - sq) / (2.0 * A))
	var t1 := minf(1.0, (-B + sq) / (2.0 * A))
	if t0 >= t1:
		return []
	return [a + d * t0, a + d * t1]


func _ladder_pt(cam: Camera3D, origin: Vector3, h: float, e: float) -> Vector3:
	var ce := cos(e)
	return _proj(cam, origin + Vector3(sin(h) * ce, sin(e), -cos(h) * ce) * 8000.0)


func _draw_heading_tape(g: Game) -> void:
	var hdg := MathX.heading_deg(g.player.fwd)
	var cx := size.x / 2.0
	var y := 22.0
	var half_w := 160.0
	var px_per_deg := 3.2
	var start := int(floor((hdg - 60.0) / 5.0)) * 5
	var d := start
	while d <= hdg + 60.0:
		var x := cx + (d - hdg) * px_per_deg
		if x >= cx - half_w and x <= cx + half_w:
			var dd := posmod(d, 360)
			var major := dd % 30 == 0
			draw_line(Vector2(x, y), Vector2(x, y + (8.0 if major else 4.0)), Cfg.C_HUD_DIM, 1.5, true)
			if major:
				var lbl := "N" if dd == 0 else ("E" if dd == 90 else ("S" if dd == 180 else ("W" if dd == 270 else "%02d" % (dd / 10))))
				_text(Vector2(x, y - 8), lbl, 11, Cfg.C_HUD_DIM)
		d += 5
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y + 11), Vector2(cx - 5, y + 18), Vector2(cx + 5, y + 18)]), Cfg.C_HUD)


func _draw_marker(g: Game, a: Aircraft, cam: Camera3D, focal: float, selected: bool) -> void:
	var p := g.player
	var s := _proj(cam, a.pos)
	if s.z > 0.0 or s.x < -50 or s.x > size.x + 50 or s.y < -50 or s.y > size.y + 50:
		return
	var dist := a.pos.distance_to(p.pos)
	if a.team == "blue":
		if dist > 6000.0:
			return
		draw_polyline(PackedVector2Array([Vector2(s.x - 6, s.y - 12), Vector2(s.x, s.y - 6), Vector2(s.x + 6, s.y - 12)]), Cfg.C_FRIEND, 1.5, true)
		_text(Vector2(s.x, s.y - 20), a.callsign, 10, Cfg.C_FRIEND)
		return
	var col := Cfg.C_ACE if a.kind == "ace" else (Cfg.C_TARGET if a.mission_target else (Cfg.C_DRONE if a.kind == "drone" else Cfg.C_HOSTILE))
	var sz := clampf(a.radius * 1.6 * focal / maxf(dist, 1.0), 16.0 if selected else 11.0, 70.0)
	var lw := 2.0 if selected else 1.4
	var k := sz * 0.4
	for c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var x: float = s.x + c[0] * sz
		var y: float = s.y + c[1] * sz
		draw_polyline(PackedVector2Array([Vector2(x, y - c[1] * k), Vector2(x, y), Vector2(x - c[0] * k, y)]), col, lw, true)
	var font: Font = UiKit.bold if selected else UiKit.semibold
	var important := selected or a.mission_target or a.kind == "ace"
	if selected or (important and dist < 5000.0) or dist < 1300.0:
		_text(Vector2(s.x, s.y - sz - 9), ("TGT " + a.label) if a.mission_target else a.label, 11, col, HORIZONTAL_ALIGNMENT_CENTER, font)
	if selected or important:
		_text(Vector2(s.x, s.y + sz + 10), _fmt_dist(dist), 11, col, HORIZONTAL_ALIGNMENT_CENTER, font)
	var bar_y := s.y + sz + 20
	var detail := selected or dist < 3000.0
	if (a.kind == "scout" or a.kind == "ace") and detail:
		_mini_bar(s.x, bar_y, 56, a.hp / a.max_hp, col)
		bar_y += 8
	if a.kind == "scout" and g.uploads_active and detail:
		var paused := a.upload_pause > 0.0
		_mini_bar(s.x, bar_y, 56, a.upload, Color.WHITE if paused else Cfg.C_GOLD)
		_text(Vector2(s.x, bar_y + 10), "JAMMED" if paused else "UPLOAD %d%%" % int(round(a.upload * 100.0)), 9, Color.WHITE if paused else Cfg.C_GOLD)
	if selected:
		if a.ecm:
			_text(Vector2(s.x + sz + 8, s.y), "NO LOCK", 11, Cfg.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT, UiKit.bold)
		elif g.locked:
			var d := (sz + 10.0) * (1.0 + 0.08 * sin(g.real_time * 20.0))
			_diamond(Vector2(s.x, s.y), d, Cfg.C_HOSTILE, 2.5)
			_text(Vector2(s.x + d + 6, s.y), "LOCK", 12, Cfg.C_HOSTILE, HORIZONTAL_ALIGNMENT_LEFT, UiKit.bold)
		elif g.lock_progress > 0.0:
			_diamond(Vector2(s.x, s.y), sz + 10.0 + (1.0 - g.lock_progress) * 70.0, Cfg.C_HUD, 1.5)


func _diamond(c: Vector2, d: float, col: Color, w: float) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)]), col, w, true)


func _mini_bar(cx: float, y: float, w: float, frac: float, col: Color) -> void:
	draw_rect(Rect2(cx - w / 2.0, y, w, 4), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(cx - w / 2.0, y, w * clampf(frac, 0.0, 1.0), 4), col)


func _edge_arrow(s: Vector3, col: Color, label: String) -> void:
	var cx := size.x / 2.0
	var cy := size.y / 2.0
	var dx := s.x - cx
	var dy := s.y - cy
	if s.z > 0.0:
		dx = -dx
		dy = -dy
		if absf(dx) < 1.0 and absf(dy) < 1.0:
			dy = 1.0
	var ang := atan2(dy, dx)
	var e := Vector2(cx + cos(ang) * size.x * 0.42, cy + sin(ang) * size.y * 0.38)
	var tr := Transform2D(ang, e)
	draw_colored_polygon(PackedVector2Array([tr * Vector2(14, 0), tr * Vector2(-6, -9), tr * Vector2(-2, 0), tr * Vector2(-6, 9)]), col)
	_text(e - Vector2(cos(ang) * 30.0, sin(ang) * 22.0), label, 11, col)


static func _fmt_dist(d: float) -> String:
	if d >= 1000.0:
		return "%.1fKM" % (d / 1000.0)
	return "%dM" % int(round(d / 10.0) * 10.0)
