class_name CloudLayer
extends MultiMeshInstance3D
## Billboard cloud puffs (one draw call), sorted back-to-front every few frames.
## Layouts use the web build's seeded generator so the sky matches exactly.

var puffs: Array = []  # each [x, y, z, size, shade, rot, alpha]
var clusters: Array = []  # each [center: Vector3, rx, ry]
var _order: PackedInt32Array
var _buf := PackedFloat32Array()
var _sort_t := 0
var _mat: ShaderMaterial


func _init(layout: Dictionary, is_storm: bool) -> void:
	puffs = layout.puffs
	clusters = layout.clusters
	var n := puffs.size()
	_order.resize(n)
	for i in n:
		_order[i] = i
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/cloud.gdshader")
	_mat.set_shader_parameter("tex", load("res://assets/tex/cloud.png"))
	if is_storm:
		_mat.set_shader_parameter("light_col", World.lin(0x56606d))
		_mat.set_shader_parameter("shadow_col", World.lin(0x161a21))
		_mat.set_shader_parameter("fog_tint", World.lin(0x8796a6))
		_mat.set_shader_parameter("fog_mul", 0.12)
		_mat.set_shader_parameter("near_fade", 0.0)
	else:
		_mat.set_shader_parameter("light_col", Vector3(1, 1, 1))
		_mat.set_shader_parameter("shadow_col", World.lin(0xa3b2c4))
		_mat.set_shader_parameter("fog_tint", World.lin(World.FOG))
		_mat.set_shader_parameter("fog_mul", 1.0)
		_mat.set_shader_parameter("near_fade", 1.0)
	q.material = _mat
	mm.mesh = q
	mm.instance_count = n
	multimesh = mm
	custom_aabb = AABB(Vector3(-60000, -1000, -60000), Vector3(120000, 12000, 120000))
	# The web draws the storm (renderOrder -4) after the rain curtains and before every
	# other transparent; distance sorting put close-up rain on top of it.
	if is_storm:
		_mat.render_priority = -4
	_buf.resize(n * 16)
	_write()


static func field_layout() -> Dictionary:
	var rng := Mulberry32.new(7)
	var puffs: Array = []
	var clusters: Array = []
	for c in 70:
		var cx := -16000.0 + rng.next() * 36000.0
		var cz := -18000.0 + rng.next() * 30000.0
		var cy := 1100.0 + rng.next() * 900.0
		var rx := 350.0 + rng.next() * 550.0
		var ry := 110.0 + rng.next() * 120.0
		clusters.append([Vector3(cx, cy, cz), rx, ry])
		var count := 7 + int(floor(rng.next() * 9.0))
		for i in count:
			var a := rng.next() * TAU
			var r := sqrt(rng.next()) * rx * 0.8
			var dy := (rng.next() - 0.35) * ry
			var sx := cx + cos(a) * r
			var sz := cz + sin(a) * r
			var size := 260.0 + rng.next() * 360.0
			var shade := 0.45 + (dy / ry) * 0.6 + rng.next() * 0.15
			var rot := rng.next() * TAU
			var alpha := 0.7 + rng.next() * 0.25
			puffs.append([sx, cy + dy, sz, size, shade, rot, alpha])
	return {"puffs": puffs, "clusters": clusters}


static func storm_layout() -> Dictionary:
	var rng := Mulberry32.new(99)
	var puffs: Array = []
	for i in 260:
		var t := rng.next()
		var h := rng.next()
		var x := -34000.0 + t * 44000.0
		var z := 22000.0 + (rng.next() - 0.5) * 5000.0 + sin(t * 7.0) * 1800.0
		var y := 1300.0 + h * h * 4800.0
		var anvil := smoothstep(0.55, 1.0, h)
		var px := x + (rng.next() - 0.5) * 2000.0 * anvil
		var pz := z - anvil * 1500.0
		var size := (2200.0 + rng.next() * 2400.0) * (1.0 + anvil * 0.8)
		var shade := h * 0.9 + rng.next() * 0.15
		var rot := rng.next() * TAU
		puffs.append([px, y, pz, size, shade, rot, 0.92])
	return {"puffs": puffs, "clusters": []}


func set_flash(v: float) -> void:
	_mat.set_shader_parameter("flash", v)


func density_at(p: Vector3) -> float:
	var d := 0.0
	for c in clusters:
		var center: Vector3 = c[0]
		var rx: float = c[1]
		var ry: float = c[2]
		var dx := (p.x - center.x) / rx
		var dy := (p.y - center.y) / (ry * 1.4)
		var dz := (p.z - center.z) / rx
		var r2 := dx * dx + dy * dy + dz * dz
		if r2 < 1.0:
			d = maxf(d, 1.0 - r2)
	return d


func update_sort(cam: Vector3) -> void:
	_sort_t -= 1
	if _sort_t > 0:
		return
	_sort_t = 8
	var dist := PackedFloat32Array()
	dist.resize(puffs.size())
	for i in puffs.size():
		var pf: Array = puffs[i]
		dist[i] = (pf[0] - cam.x) * (pf[0] - cam.x) + (pf[1] - cam.y) * (pf[1] - cam.y) + (pf[2] - cam.z) * (pf[2] - cam.z)
	var idx: Array = []
	idx.resize(puffs.size())
	for i in puffs.size():
		idx[i] = i
	idx.sort_custom(func(a: int, b: int) -> bool: return dist[a] > dist[b])
	for i in idx.size():
		_order[i] = idx[i]
	_write()


func _write() -> void:
	for k in _order.size():
		var pf: Array = puffs[_order[k]]
		var o := k * 16
		_buf[o] = 1.0
		_buf[o + 1] = 0.0
		_buf[o + 2] = 0.0
		_buf[o + 3] = pf[0]
		_buf[o + 4] = 0.0
		_buf[o + 5] = 1.0
		_buf[o + 6] = 0.0
		_buf[o + 7] = pf[1]
		_buf[o + 8] = 0.0
		_buf[o + 9] = 0.0
		_buf[o + 10] = 1.0
		_buf[o + 11] = pf[2]
		_buf[o + 12] = pf[3]
		_buf[o + 13] = pf[4]
		_buf[o + 14] = pf[5]
		_buf[o + 15] = pf[6]
	multimesh.buffer = _buf
