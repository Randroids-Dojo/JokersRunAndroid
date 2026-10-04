class_name World
extends Node3D
## Sky, ocean, clouds, storm front, rain shafts and global lighting (port of environment.ts).

const ZENITH := 0x2f62a8
const HORIZON := 0xb9cbd8
const FOG := 0xaec2d2
const SUN := 0xfff1d6
const DEEP := 0x0c2c46
const SHALLOW := 0x1f6f78

var sun_dir := Cfg.SUN_DIR.normalized()
var env: Environment
var sky_mat: ShaderMaterial
var sky_dome: MeshInstance3D
var ocean: MeshInstance3D
var ocean_mat: ShaderMaterial
var clouds: CloudLayer
var storm: CloudLayer
var rain: Array[MeshInstance3D] = []
var storm_flash := 0.0
var _lightning_t := 4.0


static func lin(hex: int) -> Vector3:
	var c := Geo.col(hex)
	return Vector3(c.r, c.g, c.b)


func setup(terrain: Terrain) -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("sun_dir", sun_dir)
	rs.global_shader_parameter_set("sun_color", lin(SUN) * 2.6)
	rs.global_shader_parameter_set("hemi_sky", lin(0xcfe2ff) * 1.15)
	rs.global_shader_parameter_set("hemi_ground", lin(0x4f5a52) * 1.15)
	rs.global_shader_parameter_set("fog_color", lin(FOG))
	rs.global_shader_parameter_set("fog_density", Cfg.FOG_DENSITY)

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_dome.gdshader")
	sky_mat.set_shader_parameter("zenith", lin(ZENITH))
	sky_mat.set_shader_parameter("horizon", lin(HORIZON))
	sky_mat.set_shader_parameter("fog_col", lin(FOG))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_col", lin(SUN))
	sky_mat.set_shader_parameter("storm_dir", Vector3(-0.45, 0, 0.9).normalized())
	var dome := SphereMesh.new()
	dome.radius = 40000.0
	dome.height = 80000.0
	dome.radial_segments = 48
	dome.rings = 24
	dome.material = sky_mat
	sky_dome = MeshInstance3D.new()
	sky_dome.mesh = dome
	sky_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_dome.extra_cull_margin = 16384.0
	add_child(sky_dome)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.68, 0.76, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Materials output display-referred colour (see tone.gdshaderinc); make the final pass an
	# identity: linear tonemapper, then a LUT that undoes the engine's sRGB encode.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	# Forward Mobile re-encodes to sRGB before the LUT; the Compatibility (GLES3) post pass
	# already hands the LUT display values, so it needs no correction.
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		env.adjustment_color_correction = _identity_lut()
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://shaders/ocean.gdshader")
	ocean_mat.set_shader_parameter("sun_dir", sun_dir)
	ocean_mat.set_shader_parameter("sun_col", lin(SUN))
	ocean_mat.set_shader_parameter("zenith", lin(ZENITH))
	ocean_mat.set_shader_parameter("horizon", lin(HORIZON))
	ocean_mat.set_shader_parameter("deep", lin(DEEP))
	ocean_mat.set_shader_parameter("shallow_col", lin(SHALLOW))
	ocean_mat.set_shader_parameter("land", terrain.shore_tex)
	ocean_mat.set_shader_parameter("land_rect", Vector4(terrain.x0, terrain.z0, (terrain.nx - 1) * terrain.cell, (terrain.nz - 1) * terrain.cell))
	var plane := PlaneMesh.new()
	plane.size = Vector2(90000, 90000)
	plane.material = ocean_mat
	ocean = MeshInstance3D.new()
	ocean.mesh = plane
	ocean.custom_aabb = AABB(Vector3(-45000, -10, -45000), Vector3(90000, 20, 90000))
	ocean.sorting_offset = -100.0
	add_child(ocean)

	clouds = CloudLayer.new(CloudLayer.field_layout(), false)
	add_child(clouds)
	storm = CloudLayer.new(CloudLayer.storm_layout(), true)
	add_child(storm)
	_build_rain()


static func _identity_lut() -> ImageTexture:
	var n := 1024
	var img := Image.create(n, 1, false, Image.FORMAT_RGB8)
	for i in n:
		var v := Color(float(i) / (n - 1), 0, 0).srgb_to_linear().r
		img.set_pixel(i, 0, Color(v, v, v))
	return ImageTexture.create_from_image(img)


func _build_rain() -> void:
	var tex: Texture2D = load("res://assets/tex/rain.png")
	var rng := Mulberry32.new(5)
	for i in 9:
		var q := QuadMesh.new()
		q.size = Vector2(4600, 2300)
		q.material = Models.basic(Color("595959"), false, true, tex)
		q.material.render_priority = -5  # behind the storm clouds (see CloudLayer)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var x := -30000.0 + i * 4800.0 + rng.next() * 1500.0
		var z := 20500.0 + (rng.next() - 0.5) * 2500.0
		mi.position = Vector3(x, 1150, z)
		add_child(mi)
		mi.look_at(Vector3(0, 1150, -4000), Vector3.UP)
		mi.rotate_object_local(Vector3.UP, PI)
		mi.extra_cull_margin = 4000.0
		rain.append(mi)


func update(dt: float, time: float, cam: Camera3D) -> void:
	ocean_mat.set_shader_parameter("time", time)
	var cp := cam.global_position
	ocean.global_position = Vector3(round(cp.x / 100.0) * 100.0, 0, round(cp.z / 100.0) * 100.0)
	sky_dome.global_position = cp
	_lightning_t -= dt
	if _lightning_t <= 0.0:
		storm_flash = 1.0
		_lightning_t = 1.5 + randf() * 5.0
	storm_flash = maxf(0.0, storm_flash - dt * 5.0)
	var flicker := storm_flash * (0.6 + 0.4 * sin(time * 70.0)) if storm_flash > 0.0 else 0.0
	sky_mat.set_shader_parameter("flash", flicker * 0.35)
	storm.set_flash(flicker)
	for r in rain:
		var m: ShaderMaterial = (r.mesh as QuadMesh).material
		var v := 0.35 + flicker * 0.5
		# The web sets this colour in linear units (Color.setScalar).
		m.set_shader_parameter("color", Color(v, v, v).linear_to_srgb())
	clouds.update_sort(cp)
	storm.update_sort(cp)


## 0..1 how deep a point is inside a cloud bank.
func cloud_density_at(p: Vector3) -> float:
	return clouds.density_at(p)
