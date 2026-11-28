extends SceneTree

# Renders the question box's gem and arrow out of Synty's POLYGON Icons pack
# (2026-11-28, owner): the colour balls became the pack's faceted gem and the
# thin drawn arrows its chunky arrow. SpaceRun._draw_swatch / _draw_arrow
# draw them; without them they draw the old ball and arrow.
#
# The pack comes as a Godot project, so this runs INSIDE it, not in ours, and
# it is not headless — the headless renderer hands back blank images:
#
#   Godot_v4.7.2-stable_win64_console.exe --path <unzipped pack project> \
#       --script <this repo>/tools/build_icon_kit.gd -- <this repo>
#
# then `--import` in this repo. <unzipped pack project> is the folder holding
# the pack's project.godot (POLYGON_Icons_Godot_4_6_2_v1_0_0.zip unzips to
# polygon-icons/).
#
# **Nothing this writes may go into git**, for the same reason as the other
# kits: the pack is paid and this repository is public. The output goes to
# assets/polygon_icons/, which .gitignore excludes.
#
# Each icon is rendered front on, orthographic, under two warm and cool key
# lights, then turned to grey and stretched so its brightest lit face is
# white. The game tints it (`modulate`) with the gate colour or the arrow
# blue, so one gem serves every colour and the shading survives the tint.

const PREFABS := "res://Assets/Synty/PolygonIcons/Prefabs/"
const ICONS := {
	"gem.png": "SM_Icon_Gem_01",
	"arrow.png": "SM_Icon_Arrow_03",   # points right, as _draw_arrow expects
}
const RENDER_PX := 512   # rendered large, then cut down with Lanczos
const OUT_PX := 128      # drawn at ~20-50 px, and the HUD imports no mipmaps


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: --path <pack project> --script build_icon_kit.gd -- <repo>")
		quit(1)
		return
	_run.call_deferred(args[0].path_join("assets/polygon_icons"))


func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var here: Transform3D = xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D:
		acc.append(here * (n as MeshInstance3D).get_aabb())
	for c in n.get_children():
		_aabb(c, here, acc)


func _run(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var failed := false
	for file in ICONS:
		var path: String = PREFABS + ICONS[file] + ".tscn"
		if not ResourceLoader.exists(path):
			push_error("not in the pack: %s" % path)
			failed = true
			continue
		var img := await _render(load(path).instantiate())
		_to_grey(img)
		img.resize(OUT_PX, OUT_PX, Image.INTERPOLATE_LANCZOS)
		img.save_png(out_dir.path_join(file))
		print("  %s <- %s" % [out_dir.path_join(file), ICONS[file]])
	quit(1 if failed else 0)


func _render(inst: Node3D) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(RENDER_PX, RENDER_PX)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.9, 1.0)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	# The two key lights of the pack's own demo scene.
	var l1 := DirectionalLight3D.new()
	l1.transform = Transform3D(Basis(Vector3(0.47552738, 0.23802982, -0.8468858), Vector3(-0.632839, 0.7612675, -0.14137435), Vector3(0.6110553, 0.60316974, 0.5126381)), Vector3.ZERO)
	l1.light_color = Color(1, 0.957, 0.839)
	l1.light_energy = 1.2
	vp.add_child(l1)
	var l2 := DirectionalLight3D.new()
	l2.transform = Transform3D(Basis(Vector3(-0.23636812, 0.5910061, 0.77125996), Vector3(0.50589114, 0.7525371, -0.4216185), Vector3(-0.8295808, 0.29051644, -0.47686052)), Vector3.ZERO)
	l2.light_color = Color(0.839, 0.993, 1.0)
	l2.light_energy = 0.9
	vp.add_child(l2)
	vp.add_child(inst)
	var acc := []
	_aabb(inst, Transform3D.IDENTITY, acc)
	var box: AABB = acc[0]
	for b in acc:
		box = box.merge(b)
	# Square and centred on the icon, so the game can draw it in a square
	# around a point and turn it about its middle.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.y) * 1.08
	cam.position = box.get_center() + Vector3(0, 0, 20)
	cam.near = 0.1
	cam.far = 100.0
	vp.add_child(cam)
	cam.current = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _to_grey(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var top := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.5:
				top = maxf(top, p.get_luminance())
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var l: float = clampf(p.get_luminance() / maxf(top, 0.01), 0.0, 1.0)
			img.set_pixel(x, y, Color(l, l, l, p.a))
