extends SceneTree

# Takes the stardust's star out of Aztech Games' "Gems and Crystals" pack
# (Unity Asset Store; 2026-11-28, owner): its faceted five-point star,
# Meshes/Crystal_3.fbx. It writes two files into assets/aztech_gems/:
#
#   star_mesh.res   the geometry alone, for the 3D stars that fly from a
#                   smashed planet to the counter (SpaceRun._dust_star)
#   stardust.png    the star rendered front on and mapped onto pink, for the
#                   counters on the menu, the HUD and the game over
#                   (ArtSlot.stardust_icon_path)
#
# The FBX is read straight from the pack (FBXDocument), so nothing of the
# pack enters the project but these two. Not headless — the headless
# renderer hands back blank images:
#
#   Godot_v4.7.2-stable_win64_console.exe --path . \
#       --script res://tools/build_gem_kit.gd -- <GemsAndCrystals dir>
#
# then `--import`. <dir> is the pack's folder in a Unity project, the one
# holding Meshes/ (the owner's is under "C:\Unity Project\My project (2)\
# Assets\Aztech Games\GemsAndCrystals").
#
# **Nothing this writes may go into git**: the pack is paid and this
# repository is public. assets/aztech_gems/ is gitignored. Without it the
# stardust is the UI kit's currency icon, flat, and the motes flat too.
#
# The pack's own material (Unity Standard, white, metallic) does not come
# along; the game gives the star its pink-violet (SpaceRun.DUST_STAR_*).

const SOURCE := "Meshes/Crystal_3.fbx"
const OUT := "res://assets/aztech_gems/"
const RENDER_PX := 512
const OUT_PX := 128
# Shadowed faces a deep magenta, lit ones a pale pink, so the facets hold on
# the dark sky. Pink-violet (2026-11-28, owner) over blue and a white crystal,
# compared in the game: blue is one of the four gate colours and sank among
# the cyan bullets, engines and gate glow; pink is the one colour on screen
# that means stardust.
const TINT_DARK := Color(0.85, 0.08, 0.6)
const TINT_LIGHT := Color(1.0, 0.72, 0.94)
# Brightness squared before the mapping: the star's faces are lit evenly from
# the front, and a straight mapping left it nearly white.
const FACET_CONTRAST := 2.6


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: --script res://tools/build_gem_kit.gd -- <GemsAndCrystals dir>")
		quit(1)
		return
	_run.call_deferred(args[0].path_join(SOURCE))


func _run(src: String) -> void:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	var err := doc.append_from_file(src, state)
	if err != OK:
		push_error("could not read %s (%d)" % [src, err])
		quit(1)
		return
	var scene: Node = doc.generate_scene(state)
	var mesh := _baked_mesh(scene)
	scene.free()
	if mesh == null:
		push_error("no mesh in %s" % src)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	err = ResourceSaver.save(mesh, OUT + "star_mesh.res")
	if err != OK:
		push_error("could not save star_mesh.res (%d)" % err)
		quit(1)
		return
	print("  %sstar_mesh.res <- %s" % [OUT, src])
	var img := await _render(mesh)
	_to_tint(img)
	img.resize(OUT_PX, OUT_PX, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(OUT + "stardust.png"))
	print("  %sstardust.png" % OUT)
	quit(0)


## The first mesh in the scene with its node's place baked into the vertices,
## so the star faces +Z as the pack lays it out, and no material.
func _baked_mesh(scene: Node) -> ArrayMesh:
	var found: Array = [scene] if (scene is MeshInstance3D or scene is ImporterMeshInstance3D) \
		else scene.find_children("*", "", true, false).filter(
			func(n): return n is MeshInstance3D or n is ImporterMeshInstance3D)
	if found.is_empty():
		return null
	var node: Node3D = found[0]
	var src: ArrayMesh = node.mesh.get_mesh() if node is ImporterMeshInstance3D else node.mesh
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var mdt := MeshDataTool.new()
		mdt.create_from_surface(src, s)
		for v in mdt.get_vertex_count():
			mdt.set_vertex(v, xf * mdt.get_vertex(v))
			mdt.set_vertex_normal(v, (xf.basis * mdt.get_vertex_normal(v)).normalized())
		mdt.commit_to_surface(out)
	return out


func _render(mesh: ArrayMesh) -> Image:
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
	var l1 := DirectionalLight3D.new()
	l1.transform = Transform3D(Basis(Vector3(0.47552738, 0.23802982, -0.8468858), Vector3(-0.632839, 0.7612675, -0.14137435), Vector3(0.6110553, 0.60316974, 0.5126381)), Vector3.ZERO)
	l1.light_energy = 1.2
	vp.add_child(l1)
	var l2 := DirectionalLight3D.new()
	l2.transform = Transform3D(Basis(Vector3(-0.23636812, 0.5910061, 0.77125996), Vector3(0.50589114, 0.7525371, -0.4216185), Vector3(-0.8295808, 0.29051644, -0.47686052)), Vector3.ZERO)
	l2.light_energy = 0.9
	vp.add_child(l2)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	vp.add_child(mi)
	var box := mesh.get_aabb()
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


## Grey stretched so the brightest lit face is white, then taken along
## TINT_DARK..TINT_LIGHT; alpha kept.
func _to_tint(img: Image) -> void:
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
			# Squared: the star's faces are all lit fairly evenly from the front,
			# and a straight mapping left it nearly white.
			var l: float = pow(clampf(p.get_luminance() / maxf(top, 0.01), 0.0, 1.0), FACET_CONTRAST)
			var c := TINT_DARK.lerp(TINT_LIGHT, l)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, p.a))
