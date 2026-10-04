class_name Geo
extends RefCounted
## Procedural low-poly parts with per-vertex colour, merged into one mesh per model.
## Port of the web build's geo.ts (same primitives, same winding rules).

var verts := PackedVector3Array()
var cols := PackedColorArray()

static var flat_material: ShaderMaterial


static func col(hex: int) -> Color:
	return Color.hex((hex << 8) | 0xff).srgb_to_linear()


static func material(rough := 0.55, metal := 0.35) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/flat.gdshader")
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	return m


static func xf(x := 0.0, y := 0.0, z := 0.0, rx := 0.0, ry := 0.0, rz := 0.0, sx := 1.0, sy := 1.0, sz := 1.0) -> Transform3D:
	var b := Basis(Vector3(1, 0, 0), rx) * Basis(Vector3(0, 1, 0), ry) * Basis(Vector3(0, 0, 1), rz)
	b = b * Basis.from_scale(Vector3(sx, sy, sz))
	return Transform3D(b, Vector3(x, y, z))


func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	cols.append(color)
	cols.append(color)
	cols.append(color)


func append(other: Geo, t := Transform3D.IDENTITY, mirror := false) -> void:
	var n := other.verts.size()
	var flip := t.basis.determinant() < 0.0
	if mirror:
		flip = not flip
	var i := 0
	while i < n:
		var a := t * other.verts[i]
		var b := t * other.verts[i + 1]
		var c := t * other.verts[i + 2]
		if mirror:
			a.x = -a.x
			b.x = -b.x
			c.x = -c.x
		if flip:
			tri(a, c, b, other.cols[i])
		else:
			tri(a, b, c, other.cols[i])
		i += 3


## Append `other` and its mirror image across x = 0.
func append_pair(other: Geo, t := Transform3D.IDENTITY) -> void:
	append(other, t)
	append(other, t, true)


static func box(w: float, h: float, d: float, color: Color) -> Geo:
	var g := Geo.new()
	var x := w / 2.0
	var y := h / 2.0
	var z := d / 2.0
	var p := [Vector3(-x, -y, -z), Vector3(x, -y, -z), Vector3(x, y, -z), Vector3(-x, y, -z), Vector3(-x, -y, z), Vector3(x, -y, z), Vector3(x, y, z), Vector3(-x, y, z)]
	var faces := [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3], [0, 1, 5, 4]]
	for f in faces:
		g.tri(p[f[0]], p[f[1]], p[f[2]], color)
		g.tri(p[f[0]], p[f[2]], p[f[3]], color)
	return g


## Cylinder along Y.
static func cyl(r_top: float, r_bot: float, h: float, seg: int, color: Color, caps := true) -> Geo:
	var g := Geo.new()
	var y0 := -h / 2.0
	var y1 := h / 2.0
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var b0 := Vector3(sin(a0) * r_bot, y0, cos(a0) * r_bot)
		var b1 := Vector3(sin(a1) * r_bot, y0, cos(a1) * r_bot)
		var t0 := Vector3(sin(a0) * r_top, y1, cos(a0) * r_top)
		var t1 := Vector3(sin(a1) * r_top, y1, cos(a1) * r_top)
		g.tri(b0, b1, t1, color)
		g.tri(b0, t1, t0, color)
		if caps:
			if r_top > 0.0:
				g.tri(Vector3(0, y1, 0), t0, t1, color)
			if r_bot > 0.0:
				g.tri(Vector3(0, y0, 0), b1, b0, color)
	return g


## Cylinder along Z. Matches the web tubeZ(): the second radius sits at -Z, the first at +Z.
static func tube_z(r_pos: float, r_neg: float, length: float, seg: int, color: Color) -> Geo:
	var g := Geo.new()
	g.append(cyl(r_neg, r_pos, length, seg, color), Transform3D(Basis(Vector3(1, 0, 0), -PI / 2.0), Vector3.ZERO))
	return g


## UV sphere segment (theta from the +Y pole).
static func sphere(r: float, ws: int, hs: int, color: Color, theta_len := PI) -> Geo:
	var g := Geo.new()
	for j in hs:
		var t0 := theta_len * j / hs
		var t1 := theta_len * (j + 1) / hs
		for i in ws:
			var p0 := TAU * i / ws
			var p1 := TAU * (i + 1) / ws
			var a := Vector3(-cos(p0) * sin(t0), cos(t0), sin(p0) * sin(t0)) * r
			var b := Vector3(-cos(p1) * sin(t0), cos(t0), sin(p1) * sin(t0)) * r
			var c := Vector3(-cos(p1) * sin(t1), cos(t1), sin(p1) * sin(t1)) * r
			var d := Vector3(-cos(p0) * sin(t1), cos(t1), sin(p0) * sin(t1)) * r
			if j > 0:
				g.tri(a, c, b, color)
			g.tri(a, d, c, color)
	return g


## Fuselage loft through elliptical sections [z, w, h, y] from nose (-Z) to tail.
static func loft(sections: Array, seg: int, color: Color) -> Geo:
	var g := Geo.new()
	var ring := func(s: Array, i: int) -> Vector3:
		var a := TAU * i / seg
		var y: float = s[3] if s.size() > 3 else 0.0
		return Vector3(cos(a) * s[1], y + sin(a) * s[2], s[0])
	for k in sections.size() - 1:
		var s0: Array = sections[k]
		var s1: Array = sections[k + 1]
		for i in seg:
			var a0: Vector3 = ring.call(s0, i)
			var a1: Vector3 = ring.call(s0, i + 1)
			var b0: Vector3 = ring.call(s1, i)
			var b1: Vector3 = ring.call(s1, i + 1)
			g.tri(a0, a1, b0, color)
			g.tri(a1, b1, b0, color)
	var first: Array = sections[0]
	var last: Array = sections[sections.size() - 1]
	var cf := Vector3(0, first[3] if first.size() > 3 else 0.0, first[0])
	var cl := Vector3(0, last[3] if last.size() > 3 else 0.0, last[0])
	for i in seg:
		g.tri(cf, ring.call(first, i + 1), ring.call(first, i), color)
		g.tri(cl, ring.call(last, i), ring.call(last, i + 1), color)
	return g


## Flat convex polygon slab. plane "xz": points are [x, z], thickness along y (wings).
## plane "zy": points are [z, y], thickness along x (fins).
static func slab(pts: Array, thickness: float, color: Color, plane := "xz") -> Geo:
	var g := Geo.new()
	var h := thickness / 2.0
	var to3 := func(a: float, b: float, t: float) -> Vector3:
		return Vector3(a, t, b) if plane == "xz" else Vector3(t, b, a)
	var n := pts.size()
	var cx := 0.0
	var cy := 0.0
	for p in pts:
		cx += p[0]
		cy += p[1]
	var center: Vector3 = to3.call(cx / n, cy / n, 0.0)
	var tris: Array = []
	for i in range(1, n - 1):
		tris.append([to3.call(pts[0][0], pts[0][1], h), to3.call(pts[i][0], pts[i][1], h), to3.call(pts[i + 1][0], pts[i + 1][1], h)])
		tris.append([to3.call(pts[0][0], pts[0][1], -h), to3.call(pts[i + 1][0], pts[i + 1][1], -h), to3.call(pts[i][0], pts[i][1], -h)])
	for i in n:
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % n]
		var a0: Vector3 = to3.call(a[0], a[1], h)
		var b0: Vector3 = to3.call(b[0], b[1], h)
		var a1: Vector3 = to3.call(a[0], a[1], -h)
		var b1: Vector3 = to3.call(b[0], b[1], -h)
		tris.append([a0, b0, a1])
		tris.append([b0, b1, a1])
	for t in tris:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var nn := (p1 - p0).cross(p2 - p0)
		var m := (p0 + p1 + p2) / 3.0 - center
		if nn.dot(m) < 0.0:
			g.tri(p0, p2, p1, color)
		else:
			g.tri(p0, p1, p2, color)
	return g


func to_mesh(mat: Material) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var i := 0
	while i < verts.size():
		var nn := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).normalized()
		normals[i] = nn
		normals[i + 1] = nn
		normals[i + 2] = nn
		i += 3
	# Godot treats clockwise triangles as front faces; flip from the CCW (three.js) convention.
	var gv := PackedVector3Array()
	var gc := PackedColorArray()
	var gn := PackedVector3Array()
	gv.resize(verts.size())
	gc.resize(verts.size())
	gn.resize(verts.size())
	i = 0
	while i < verts.size():
		gv[i] = verts[i]
		gv[i + 1] = verts[i + 2]
		gv[i + 2] = verts[i + 1]
		gc[i] = cols[i]
		gc[i + 1] = cols[i + 2]
		gc[i + 2] = cols[i + 1]
		gn[i] = normals[i]
		gn[i + 1] = normals[i]
		gn[i + 2] = normals[i]
		i += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = gv
	arrays[Mesh.ARRAY_NORMAL] = gn
	arrays[Mesh.ARRAY_COLOR] = gc
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh
