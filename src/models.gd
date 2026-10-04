class_name Models
extends RefCounted
## Procedural aircraft, missiles, ships and checkpoint rings. Part-for-part port of models.ts.

const SCHEMES := {
	"joker": [0x8a96a3, 0xc0282d, 0x3a4048, 0x1c2a38],
	"enemy": [0x5b6157, 0xd46a1f, 0x2c2f2b, 0x3a2c18],
	"ace": [0x1b1d22, 0xe6b422, 0x0d0e10, 0x5a1010],
}

static var _meshes := {}
static var _body_mat: ShaderMaterial
static var _ship_mat: ShaderMaterial
static var burner_mat: ShaderMaterial
static var burner_core_mat: ShaderMaterial
static var _burner_mesh: ArrayMesh
static var _radome_mesh: ArrayMesh


static func _init_shared() -> void:
	if _body_mat:
		return
	_body_mat = Geo.material(0.55, 0.35)
	_ship_mat = Geo.material(0.8, 0.15)
	burner_mat = _additive(Color("ff9a3c"), 0.9)
	burner_core_mat = _additive(Color("bfe0ff"), 0.95)
	# Open cone: base ring at z = 0, apex at z = +1 (pointing aft).
	var g := Geo.new()
	var seg := 10
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		g.tri(Vector3(cos(a0) * 0.5, sin(a0) * 0.5, 0), Vector3(cos(a1) * 0.5, sin(a1) * 0.5, 0), Vector3(0, 0, 1), Color.WHITE)
	_burner_mesh = g.to_mesh(burner_mat)


static func _additive(c: Color, alpha: float) -> ShaderMaterial:
	return basic(Color(c.r, c.g, c.b, alpha), true, false)


## three.js MeshBasicMaterial equivalent. `c` is an sRGB colour (like a web hex value) with
## opacity in alpha; tone_mapped mirrors the web material's toneMapped flag.
static func basic(c: Color, additive: bool, tone_mapped: bool, tex: Texture2D = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/basic_add.gdshader" if additive else "res://shaders/basic_mix.gdshader")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("tone_mapped", tone_mapped)
	if tex:
		m.set_shader_parameter("tex", tex)
	return m


static func set_opacity(m: ShaderMaterial, a: float) -> void:
	var c: Color = m.get_shader_parameter("color")
	c.a = a
	m.set_shader_parameter("color", c)


## A colour for nodes that draw through Godot's own materials (Label3D): pre-encode so the
## display-referred pipeline shows exactly `c`.
static func display_color(c: Color) -> Color:
	var e := Color(c.r, c.g, c.b).linear_to_srgb()
	return Color(e.r, e.g, e.b, c.a)


static func _c(hex: int) -> Color:
	return Geo.col(hex)


static func fighter_geo(kind: String) -> Geo:
	var s: Array = SCHEMES[kind]
	var body := _c(s[0])
	var accent := _c(s[1])
	var dark := _c(s[2])
	var glass := _c(s[3])
	var g := Geo.new()
	g.append(Geo.loft([[-9.2, 0.04, 0.04, -0.1], [-8.0, 0.42, 0.38, -0.05], [-6.0, 0.8, 0.72], [-3.5, 1.0, 0.95, 0.1], [-1.0, 1.55, 0.95], [2.5, 1.75, 0.9], [6.0, 1.45, 0.85], [8.2, 1.15, 0.75]], 10, body))
	if kind == "ace":
		g.append(Geo.loft([[-9.3, 0.05, 0.05, -0.1], [-8.1, 0.44, 0.4, -0.05]], 10, _c(0xb5121b)))
	g.append(Geo.sphere(0.8, 10, 6, glass, PI / 2.0), Geo.xf(0, 0.72, -3.7, 0, 0, 0, 0.85, 0.75, 2.8))
	var wing: Array
	if kind == "ace":
		wing = [[1.0, 1.0], [7.4, -0.8], [7.4, 0.5], [1.0, 5.4]]
		g.append_pair(Geo.slab([[0.9, -4.6], [2.8, -3.9], [2.8, -3.3], [0.9, -3.0]], 0.15, accent), Geo.xf(0, 0.1, 0))
	else:
		wing = [[0.9, -1.8], [7.0, 3.4], [7.0, 4.5], [0.9, 5.4]]
	g.append_pair(Geo.slab(wing, 0.28, body), Geo.xf(0, -0.1, 0))
	var tip: Array = wing[1]
	var tip_pts := [[tip[0] - 0.9, tip[1] - 0.5], [tip[0] + 0.05, tip[1]], [tip[0] + 0.05, wing[2][1]], [tip[0] - 0.9, wing[2][1] + 0.3]]
	g.append_pair(Geo.slab(tip_pts, 0.32, accent), Geo.xf(0, -0.1, 0))
	g.append_pair(Geo.slab([[1.0, 5.6], [3.9, 7.7], [3.9, 8.5], [1.0, 8.4]], 0.2, body))
	g.append_pair(Geo.slab([[4.4, 0.6], [7.4, 3.9], [8.3, 3.9], [8.4, 0.6]], 0.22, accent, "zy"), Geo.xf(1.0, 0, 0, 0, 0, -0.26))
	g.append_pair(Geo.box(0.8, 0.9, 3.4, dark), Geo.xf(1.45, -0.25, -0.6))
	g.append_pair(Geo.tube_z(0.5, 0.58, 1.3, 8, dark), Geo.xf(0.6, 0, 8.6))
	if kind == "joker":
		g.append(Geo.box(0.35, 0.12, 6, _c(0xe8e8e8)), Geo.xf(0, 0.95, 2.2))
	if kind == "ace":
		g.append_pair(Geo.box(0.18, 0.12, 4.5, accent), Geo.xf(0.5, 0.93, 1.5))
	return g


static func scout_geo() -> Geo:
	var body := _c(0xa9aeb3)
	var accent := _c(0xb3261e)
	var g := Geo.new()
	g.append(Geo.loft([[-13.0, 0.1, 0.1], [-11.5, 1.0, 1.0], [-9.0, 1.6, 1.7], [-4.0, 1.9, 2.0], [5.0, 1.9, 1.9], [10.0, 1.3, 1.5, 0.4], [13.0, 0.5, 0.8, 0.9]], 12, body))
	g.append(Geo.sphere(1.0, 10, 6, _c(0x22303c), PI / 2.0), Geo.xf(0, 1.2, -9.4, 0, 0, 0, 1.2, 0.8, 1.8))
	g.append_pair(Geo.slab([[1.5, -2.5], [15.0, -1.2], [15.0, 0.8], [1.5, 1.8]], 0.4, body), Geo.xf(0, 1.2, 0))
	g.append_pair(Geo.slab([[13.5, -1.35], [15.05, -1.2], [15.05, 0.8], [13.5, 0.95]], 0.45, accent), Geo.xf(0, 1.2, 0))
	g.append_pair(Geo.tube_z(0.9, 0.8, 5.0, 10, _c(0x6d7278)), Geo.xf(6, 0.3, -1.2))
	g.append(Geo.slab([[8.0, 1.5], [11.5, 6.5], [13.2, 6.5], [13.3, 1.5]], 0.35, accent, "zy"))
	g.append_pair(Geo.slab([[0.2, 10.6], [5.5, 12.0], [5.5, 13.0], [0.2, 13.2]], 0.25, body), Geo.xf(0, 6.4, 0))
	g.append(Geo.box(0.4, 2.4, 0.9, body), Geo.xf(0, 3.1, 0.5))
	g.append(Geo.box(0.4, 2.4, 0.9, body), Geo.xf(0, 3.1, 3.6))
	return g


static func drone_geo() -> Geo:
	var g := Geo.new()
	var orange := _c(0xff6d1a)
	var white := _c(0xf2f2f2)
	g.append(Geo.loft([[-4.2, 0.05, 0.05], [-3.3, 0.36, 0.36], [-1.5, 0.55, 0.55], [2.5, 0.5, 0.5], [4.1, 0.3, 0.3]], 8, orange))
	g.append(Geo.box(1.12, 1.12, 0.5, _c(0x161616)), Geo.xf(0, 0, -0.8))
	g.append_pair(Geo.slab([[0.4, -0.6], [3.4, -0.2], [3.4, 0.7], [0.4, 1.0]], 0.12, orange))
	g.append_pair(Geo.slab([[2.7, -0.25], [3.42, -0.2], [3.42, 0.7], [2.7, 0.75]], 0.14, white))
	g.append_pair(Geo.slab([[2.4, 0.2], [3.7, 1.6], [4.2, 1.6], [4.1, 0.2]], 0.1, white, "zy"), Geo.xf(0.15, 0, 0, 0, 0, -0.7))
	return g


## Returns {root: Node3D, burners: Array[Node3D], radome: Node3D or null}.
static func aircraft(kind: String) -> Dictionary:
	_init_shared()
	if not _meshes.has(kind):
		var geo: Geo
		match kind:
			"scout":
				geo = scout_geo()
			"drone":
				geo = drone_geo()
			_:
				geo = fighter_geo(kind)
		_meshes[kind] = geo.to_mesh(_body_mat)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[kind]
	root.add_child(mi)
	var burners: Array[Node3D] = []
	var add_burner := func(x: float, y: float, z: float, r: float) -> void:
		var b := Node3D.new()
		var outer := MeshInstance3D.new()
		outer.mesh = _burner_mesh
		outer.scale = Vector3(r * 2.0, r * 2.0, 1.0)
		var inner := MeshInstance3D.new()
		inner.mesh = _burner_mesh
		inner.material_override = burner_core_mat
		inner.scale = Vector3(r * 1.1, r * 1.1, 0.55)
		b.add_child(outer)
		b.add_child(inner)
		b.position = Vector3(x, y, z)
		root.add_child(b)
		burners.append(b)
	var radome: Node3D = null
	if kind == "scout":
		add_burner.call(6.0, 0.3, 1.4, 0.7)
		add_burner.call(-6.0, 0.3, 1.4, 0.7)
		if _radome_mesh == null:
			var rg := Geo.new()
			rg.append(Geo.cyl(4.3, 4.3, 0.9, 20, _c(0xe4e4e4)))
			rg.append(Geo.cyl(4.35, 4.35, 0.3, 20, _c(0x30343a)))
			_radome_mesh = rg.to_mesh(_body_mat)
		var rm := MeshInstance3D.new()
		rm.mesh = _radome_mesh
		rm.position = Vector3(0, 4.6, 2)
		root.add_child(rm)
		radome = rm
	elif kind == "drone":
		add_burner.call(0.0, 0.0, 4.1, 0.25)
	else:
		add_burner.call(0.6, 0.0, 9.2, 0.45)
		add_burner.call(-0.6, 0.0, 9.2, 0.45)
	return {"root": root, "burners": burners, "radome": radome}


static func missile() -> Dictionary:
	_init_shared()
	if not _meshes.has("missile"):
		var g := Geo.new()
		g.append(Geo.tube_z(0.17, 0.17, 3.0, 8, _c(0xe9e9e9)))
		g.append(Geo.cyl(0.0, 0.17, 0.6, 8, _c(0x9a9a9a)), Geo.xf(0, 0, -1.8, -PI / 2.0))
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			g.append(Geo.box(0.04, 0.55, 0.5, _c(0x777777)), Geo.xf(cos(a) * 0.3, sin(a) * 0.3, 1.25, 0, 0, a - PI / 2.0))
		_meshes["missile"] = g.to_mesh(_body_mat)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["missile"]
	root.add_child(mi)
	var flame := Node3D.new()
	var fm := MeshInstance3D.new()
	fm.mesh = _burner_mesh
	fm.scale = Vector3(0.4, 0.4, 1.0)
	flame.add_child(fm)
	flame.position = Vector3(0, 0, 1.5)
	root.add_child(flame)
	return {"root": root, "flame": flame}


static func carrier() -> Node3D:
	_init_shared()
	var g := Geo.new()
	g.append(Geo.slab([[0, -165], [18, -120], [20, -40], [19, 120], [13, 150], [-13, 150], [-19, 120], [-20, -40], [-18, -120]], 24, _c(0x59636d)), Geo.xf(0, 8, 0))
	g.append(Geo.box(40.5, 2.2, 290, _c(0x7a2a22)), Geo.xf(0, -2.5, 0))
	g.append(Geo.slab([[2, -172], [22, -135], [32, -40], [34, 100], [28, 152], [-26, 152], [-38, 70], [-38, -20], [-24, -120]], 2.5, _c(0x34383c)), Geo.xf(0, 21.3, 0))
	var line := func(x0: float, z0: float, x1: float, z1: float, color: int, w := 0.6) -> void:
		var length := Vector2(x1 - x0, z1 - z0).length()
		g.append(Geo.box(w, 0.12, length, _c(color)), Geo.xf((x0 + x1) / 2.0, 22.62, (z0 + z1) / 2.0, 0, atan2(x1 - x0, z1 - z0), 0))
	line.call(-22, 140, 4, -50, 0xd8b23a, 0.8)
	line.call(-10, 140, 16, -50, 0xd8d8d8)
	line.call(-34, 140, -8, -50, 0xd8d8d8)
	line.call(8, -168, 8, -60, 0x8c8c8c, 1.2)
	line.call(-8, -150, -8, -60, 0x8c8c8c, 1.2)
	line.call(0, 150, 0, 120, 0xd8d8d8)
	g.append(Geo.box(12, 18, 34, _c(0x6b747d)), Geo.xf(27, 31.5, 25))
	g.append(Geo.box(12.3, 2, 30, _c(0x1e2328)), Geo.xf(27, 37, 25))
	g.append(Geo.box(9, 8, 18, _c(0x6b747d)), Geo.xf(27, 44, 22))
	g.append(Geo.box(9.2, 1.6, 16, _c(0x1e2328)), Geo.xf(27, 46, 22))
	g.append(Geo.box(7, 8, 8, _c(0x50575e)), Geo.xf(28, 46, 36))
	g.append(Geo.cyl(0.6, 0.8, 24, 6, _c(0x50575e)), Geo.xf(27, 60, 20))
	g.append(Geo.box(6, 3.2, 0.6, _c(0x9aa3ab)), Geo.xf(27, 58, 18))
	g.append(Geo.box(0.6, 2.4, 5, _c(0x9aa3ab)), Geo.xf(27, 66, 20))
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh(_ship_mat)
	root.add_child(mi)
	var radar := MeshInstance3D.new()
	radar.mesh = Geo.box(7, 0.6, 1.4, _c(0xcfd5da)).to_mesh(_ship_mat)
	radar.position = Vector3(27, 69, 20)
	radar.name = "radar"
	root.add_child(radar)
	return root


static func destroyer() -> Node3D:
	_init_shared()
	var g := Geo.new()
	g.append(Geo.slab([[0, -78], [7, -50], [8, 40], [6, 72], [-6, 72], [-8, 40], [-7, -50]], 11, _c(0x66707a)), Geo.xf(0, 3.5, 0))
	g.append(Geo.box(16.2, 1.6, 120, _c(0x7a2a22)), Geo.xf(0, -1.2, 5))
	g.append(Geo.box(10, 8, 30, _c(0x7b858e)), Geo.xf(0, 13, 0))
	g.append(Geo.box(7, 6, 14, _c(0x7b858e)), Geo.xf(0, 20, -4))
	g.append(Geo.box(7.2, 1.2, 12, _c(0x1e2328)), Geo.xf(0, 21.5, -4))
	g.append(Geo.box(5, 7, 8, _c(0x50575e)), Geo.xf(0, 19, 14))
	g.append(Geo.cyl(0.4, 0.5, 16, 6, _c(0x50575e)), Geo.xf(0, 30, -2))
	g.append(Geo.box(4, 2.2, 5, _c(0x7b858e)), Geo.xf(0, 10.2, -45))
	g.append(Geo.tube_z(0.3, 0.3, 6, 6, _c(0x50575e)), Geo.xf(0, 10.6, -50))
	g.append(Geo.box(5, 3, 8, _c(0x7b858e)), Geo.xf(0, 10.6, 50))
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh(_ship_mat)
	root.add_child(mi)
	return root


## Foam wake behind a ship: widening strip, white gradient fading aft.
static func wake(width: float, length: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 8
	for r in rows:
		for k in 2:
			pass
	var pts: Array = []
	for r in rows + 1:
		var t := float(r) / rows
		var z := t * length
		var w := width * 0.5 * (1.0 + t * 2.5)
		pts.append([Vector3(-w, 0.6, z), Vector3(w, 0.6, z), t])
	for r in rows:
		var a: Array = pts[r]
		var b: Array = pts[r + 1]
		var v0: float = a[2]
		var v1: float = b[2]
		st.set_uv(Vector2(0, v0)); st.add_vertex(a[0])
		st.set_uv(Vector2(1, v1)); st.add_vertex(b[1])
		st.set_uv(Vector2(1, v0)); st.add_vertex(a[1])
		st.set_uv(Vector2(0, v0)); st.add_vertex(a[0])
		st.set_uv(Vector2(0, v1)); st.add_vertex(b[0])
		st.set_uv(Vector2(1, v1)); st.add_vertex(b[1])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = basic(Color(1, 1, 1, 0.75), false, true, load("res://assets/tex/wake.png"))
	mi.sorting_offset = 1.0
	return mi


## Checkpoint ring: gold torus, soft disc and a floating label.
static func ring(radius: float, text: String, font: Font) -> Dictionary:
	var root := Node3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = radius - 3.2
	tor.outer_radius = radius + 3.2
	tor.rings = 72
	tor.ring_segments = 10
	var ring_mat := basic(Color("ffc94a", 0.95), false, false)
	tor.material = ring_mat
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = tor
	# Godot's torus lies in XZ; turn it to face +Z like three.js.
	ring_mi.rotation = Vector3(PI / 2.0, 0, 0)
	root.add_child(ring_mi)
	var disc := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	var dm := basic(Color(1, 1, 1, 1), true, false, load("res://assets/tex/disc.png"))
	q.material = dm
	disc.mesh = q
	root.add_child(disc)
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = 150
	label.pixel_size = radius * 0.8 / 190.0
	label.modulate = display_color(Color("ffd25a"))
	label.outline_size = 14
	label.outline_modulate = display_color(Color(0.04, 0.05, 0.06, 0.75))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.fixed_size = false
	label.position = Vector3(0, radius + 34.0, 0)
	root.add_child(label)
	return {"root": root, "ring": ring_mi, "ring_mat": ring_mat, "disc": disc, "disc_mat": dm, "label": label}
