class_name Trails
extends MeshInstance3D
## Wingtip vapour ribbons. Every trail shares one ImmediateMesh (one draw call), rebuilt per
## frame from ring buffers of points and strengths. Port of effects.ts TrailBatch.

const MAX := 64
const LEN := 36

var _points := PackedVector3Array()
var _strength := PackedFloat32Array()
var _heads := PackedInt32Array()
var _counts := PackedInt32Array()
var _used: Array[bool] = []
var _im: ImmediateMesh


func _init() -> void:
	_points.resize(MAX * LEN)
	_strength.resize(MAX * LEN)
	_heads.resize(MAX)
	_counts.resize(MAX)
	_used.resize(MAX)
	_used.fill(false)
	_im = ImmediateMesh.new()
	mesh = _im
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/trail.gdshader")
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))


func alloc() -> int:
	for i in MAX:
		if not _used[i]:
			_used[i] = true
			_counts[i] = 0
			_heads[i] = 0
			return i
	return -1


func free_trail(id: int) -> void:
	if id >= 0:
		_used[id] = false
		_counts[id] = 0


func push(id: int, p: Vector3, strength: float) -> void:
	if id < 0:
		return
	var h := (_heads[id] + 1) % LEN
	_heads[id] = h
	var k := id * LEN + h
	_points[k] = p
	_strength[k] = strength
	_counts[id] = mini(LEN, _counts[id] + 1)


func _pt(t: int, i: int) -> Vector3:
	return _points[t * LEN + (_heads[t] - i + LEN) % LEN]


var _begun := false


func update_mesh(cam_pos: Vector3) -> void:
	_im.clear_surfaces()
	_begun = false
	for t in MAX:
		var n := _counts[t]
		if n < 2:
			continue
		var any := false
		for i in n:
			if _strength[t * LEN + (_heads[t] - i + LEN) % LEN] > 0.001:
				any = true
				break
		if not any:
			continue
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_a := 0.0
		for i in n:
			var a := _pt(t, i)
			var dir: Vector3
			if i < n - 1:
				dir = _pt(t, i + 1) - a
			else:
				dir = a - _pt(t, i - 1)
			var to_cam := cam_pos - a
			var side := dir.cross(to_cam)
			var sl := side.length()
			if sl > 1e-6:
				side *= (0.25 + i * 0.045) / sl
			var near := clampf((to_cam.length() - 12.0) / 40.0, 0.0, 1.0)
			var al := _strength[t * LEN + (_heads[t] - i + LEN) % LEN] * (1.0 - float(i) / LEN) * 0.32 * near
			var l := a + side
			var r := a - side
			if i > 0 and (al > 0.001 or prev_a > 0.001):
				_quad(prev_l, prev_r, l, r, prev_a, al)
			prev_l = l
			prev_r = r
			prev_a = al
	if _begun:
		_im.surface_end()


func _quad(l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, a0: float, a1: float) -> void:
	if not _begun:
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_begun = true
	var c0 := Color(1, 1, 1, a0)
	var c1 := Color(1, 1, 1, a1)
	_im.surface_set_color(c0)
	_im.surface_add_vertex(l0)
	_im.surface_set_color(c0)
	_im.surface_add_vertex(r0)
	_im.surface_set_color(c1)
	_im.surface_add_vertex(l1)
	_im.surface_set_color(c0)
	_im.surface_add_vertex(r0)
	_im.surface_set_color(c1)
	_im.surface_add_vertex(r1)
	_im.surface_set_color(c1)
	_im.surface_add_vertex(l1)


func clear() -> void:
	_counts.fill(0)
	_used.fill(false)
	_im.clear_surfaces()
