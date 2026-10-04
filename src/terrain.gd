class_name Terrain
extends Node3D
## East peninsula: sea cliffs, a sea-level canyon cut west->east, a suspension bridge, open
## water beyond. Heights are baked from the web build's terrain.ts, so the land is identical.

var x0 := 5000.0
var z0 := -9500.0
var cell := 30.0
var nx := 301
var nz := 568
var bridge_x := 10700.0
var bridge_deck_y := 135.0
var heights := PackedFloat32Array()
var shore_tex: ImageTexture
var colliders: Array[AABB] = []
var mesh_instance: MeshInstance3D


static func coast_w(z: float) -> float:
	return 6500.0 + 380.0 * sin(z / 2100.0) + 160.0 * sin(z / 650.0 + 1.3) + 60.0 * sin(z / 230.0 + 0.4)


static func coast_e(z: float) -> float:
	return 12600.0 + 300.0 * sin(z / 1800.0 + 2.1) + 120.0 * sin(z / 520.0 + 0.7)


static func canyon_z(x: float) -> float:
	return -1200.0 + 520.0 * sin((x - 6000.0) / 1250.0) + 180.0 * sin((x - 6000.0) / 480.0 + 0.8)


static func canyon_half_width(x: float) -> float:
	return 150.0 + 30.0 * sin(x / 640.0 + 0.3)


func _init() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/terrain.json"))
	x0 = meta.x0
	z0 = meta.z0
	cell = meta.cell
	nx = int(meta.nx)
	nz = int(meta.nz)
	bridge_x = meta.bridgeX
	bridge_deck_y = meta.bridgeDeckY
	var raw := FileAccess.get_file_as_bytes("res://assets/data/heights.bin")
	heights = raw.to_float32_array()
	var raw8 := FileAccess.get_file_as_bytes("res://assets/data/heights8.bin")
	shore_tex = ImageTexture.create_from_image(Image.create_from_data(nx, nz, false, Image.FORMAT_R8, raw8))


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _build_mesh()
	mesh_instance.material_override = mat
	mesh_instance.custom_aabb = AABB(Vector3(x0, -80, z0), Vector3((nx - 1) * cell, 1100, (nz - 1) * cell))
	add_child(mesh_instance)
	_build_bridge()


## The height-field grid as a real mesh (heights in the vertices, slope in UV.x) with the
## same triangle split as height(). Built on the CPU rather than displaced in the vertex
## shader: some mobile GPUs mis-read the height texture there and throw spikes across the sky.
func _build_mesh() -> ArrayMesh:
	var n := nx * nz
	var verts := PackedVector3Array()
	verts.resize(n)
	var uvs := PackedVector2Array()
	uvs.resize(n)
	var inv := 1.0 / (2.0 * cell)
	for j in nz:
		var jm := maxi(j - 1, 0) * nx
		var jp := mini(j + 1, nz - 1) * nx
		var row := j * nx
		var z := z0 + j * cell
		for i in nx:
			var k := row + i
			verts[k] = Vector3(x0 + i * cell, heights[k], z)
			var dx := heights[row + mini(i + 1, nx - 1)] - heights[row + maxi(i - 1, 0)]
			var dz := heights[jp + i] - heights[jm + i]
			uvs[k] = Vector2(sqrt(dx * dx + dz * dz) * inv, 0.0)
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var o := 0
	for j in nz - 1:
		var row := j * nx
		for i in nx - 1:
			var a := row + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# Triangles (a, b, c) and (b, d, c): the a-b-c / b-c-d split used by height(),
			# wound clockwise as seen from above.
			idx[o] = a
			idx[o + 1] = b
			idx[o + 2] = c
			idx[o + 3] = b
			idx[o + 4] = d
			idx[o + 5] = c
			o += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Height of the rendered surface (same triangle split as the mesh). May be below sea level.
func height(x: float, z: float) -> float:
	var gx := (x - x0) / cell
	var gz := (z - z0) / cell
	if gx < 0.0 or gz < 0.0 or gx >= nx - 1 or gz >= nz - 1:
		return -60.0
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * nx + ix
	var ha := heights[i]
	var hb := heights[i + 1]
	var hc := heights[i + nx]
	var hd := heights[i + nx + 1]
	if fx + fz <= 1.0:
		return ha + (hb - ha) * fx + (hc - ha) * fz
	return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)


## Solid surface height: terrain or the sea.
func ground(x: float, z: float) -> float:
	return maxf(0.0, height(x, z))


func hits_structure(p: Vector3, r: float) -> bool:
	for b in colliders:
		if p.x > b.position.x - r and p.x < b.end.x + r and p.y > b.position.y - r and p.y < b.end.y + r and p.z > b.position.z - r and p.z < b.end.z + r:
			return true
	return false


## The lead scout's chase line: approach, canyon, under the bridge, open water.
func chase_route() -> Array:
	var pts: Array = []
	var entry_x := coast_w(canyon_z(6400.0))
	var x := 3000.0
	while x <= Cfg.BOUNDARY_X + 1500.0:
		var z := canyon_z(x)
		var y: float
		var spd: float
		if x < entry_x - 900.0:
			y = lerpf(260.0, 80.0, smoothstep(3000.0, entry_x - 900.0, x))
			spd = 285.0
		elif x < coast_e(z) + 300.0:
			y = 62.0
			spd = 250.0
		else:
			y = lerpf(62.0, 90.0, smoothstep(coast_e(z) + 300.0, coast_e(z) + 2500.0, x))
			spd = 290.0
		pts.append([Vector3(x, y, z), spd])
		x += 90.0
	return pts


func _build_bridge() -> void:
	var cz := canyon_z(bridge_x)
	var hw := canyon_half_width(bridge_x)
	var length := hw * 2.0 + 560.0
	var deck_y := bridge_deck_y
	var red := Geo.col(0xb23a24)
	var g := Geo.new()
	g.append(Geo.box(26, 5, length, red), Geo.xf(bridge_x, deck_y, cz))
	g.append(Geo.box(24, 0.6, length, Geo.col(0x3c3f44)), Geo.xf(bridge_x, deck_y + 2.8, cz))
	g.append(Geo.box(30, 7, length, Geo.col(0x8d3122)), Geo.xf(bridge_x, deck_y - 5.5, cz))
	var tower_top := deck_y + 140.0
	var towers := [cz - hw * 0.62, cz + hw * 0.62]
	for tz in towers:
		for sx in [-12.0, 12.0]:
			g.append(Geo.box(6, tower_top + 20.0, 7, red), Geo.xf(bridge_x + sx, (tower_top - 20.0) / 2.0, tz))
		for y in [deck_y - 18.0, deck_y + 55.0, tower_top - 6.0]:
			g.append(Geo.box(30, 6, 6, red), Geo.xf(bridge_x, y, tz))
		g.append(Geo.box(34, 8, 16, Geo.col(0x6f7276)), Geo.xf(bridge_x, -2, tz))
		colliders.append(AABB(Vector3(bridge_x - 16.0, -30.0, tz - 5.0), Vector3(32.0, tower_top + 32.0, 10.0)))
	colliders.append(AABB(Vector3(bridge_x - 15.0, deck_y - 10.0, cz - length / 2.0), Vector3(30.0, 14.0, length)))
	var cable_span := func(za: float, ya: float, zb: float, yb: float, sag: float, sx: float) -> void:
		var seg := 18
		for i in seg:
			var t0 := float(i) / seg
			var t1 := float(i + 1) / seg
			var z_a := lerpf(za, zb, t0)
			var z_b := lerpf(za, zb, t1)
			var y_a := lerpf(ya, yb, t0) - sag * 4.0 * t0 * (1.0 - t0)
			var y_b := lerpf(ya, yb, t1) - sag * 4.0 * t1 * (1.0 - t1)
			var l := Vector2(z_b - z_a, y_b - y_a).length()
			g.append(Geo.box(1.4, 1.4, l, Geo.col(0xd04a30)), Geo.xf(bridge_x + sx, (y_a + y_b) / 2.0, (z_a + z_b) / 2.0, -atan2(y_b - y_a, z_b - z_a), 0, 0))
			if i % 2 == 0:
				g.append(Geo.box(0.5, y_a - deck_y, 0.5, Geo.col(0x9a3a2a)), Geo.xf(bridge_x + sx, (y_a + deck_y) / 2.0, z_a))
	for sx in [-12.0, 12.0]:
		cable_span.call(towers[0], tower_top, towers[1], tower_top, 110.0, sx)
		cable_span.call(cz - length / 2.0, deck_y + 4.0, towers[0], tower_top, 18.0, sx)
		cable_span.call(towers[1], tower_top, cz + length / 2.0, deck_y + 4.0, 18.0, sx)
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh(Geo.material(0.7, 0.2))
	add_child(mi)
