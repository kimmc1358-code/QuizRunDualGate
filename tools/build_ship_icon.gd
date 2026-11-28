extends SceneTree

# Renders the player's ship seen from straight above, nose up, for the lives
# readout at the bottom left of the play screen (2026-11-28, owner: "like the
# old shooting games"). Main._draw_lives draws one per heart left.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . \
#       --script res://tools/build_ship_icon.gd
#
# then `--import`. Not headless: the headless renderer hands back blank
# images. It reads the space kit (tools/build_space_kit.py must have run) and
# writes assets/synty_space/ship_top.png beside it, gitignored like the rest
# of the kit, since it is Synty's model. Without it the lives are drawn as a
# plain arrowhead.

const KIT_PATH := "res://assets/synty_space/space_kit.glb"
const SHIP_NODE := "Ship_Fighter_05"   # SpaceRun.SHIP_NODE
const OUT := "res://assets/synty_space/ship_top.png"
const RENDER_PX := 512
const OUT_PX := 96      # drawn at ~26 px; a phone's 2.25x is ~60


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(KIT_PATH):
		push_error("no space kit at %s; run tools/build_space_kit.py first" % KIT_PATH)
		quit(1)
		return
	var kit: Node = (load(KIT_PATH) as PackedScene).instantiate()
	var src := kit.find_child(SHIP_NODE, true, false) as MeshInstance3D
	if src == null:
		push_error("no %s in the kit" % SHIP_NODE)
		quit(1)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	kit.free()
	var img := await _render(mi)
	img.resize(OUT_PX, OUT_PX, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit(0)


func _render(mi: MeshInstance3D) -> Image:
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
	e.ambient_light_color = Color(0.75, 0.78, 0.9)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	# A key from above and to the front, as SpaceRun's first sun lights it.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.95, 0.88)
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(0.5, 1.0, 0.4), Vector3.ZERO, Vector3.UP)
	vp.add_child(mi)
	var box: AABB = mi.mesh.get_aabb()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.z) * 1.06
	cam.near = 0.1
	cam.far = 100.0
	vp.add_child(cam)
	# Straight down; the game turns the model half round (SpaceRun._centred_model)
	# so its nose leads into the screen, so here +Z, its nose, is the image's up.
	cam.look_at_from_position(box.get_center() + Vector3(0, 20, 0), box.get_center(), Vector3(0, 0, 1))
	cam.current = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img
