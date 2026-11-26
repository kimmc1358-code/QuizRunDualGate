extends SceneTree

# One quiz wave, from appearing to flying past, as a single strip image —
# for any change to how a wave looks (the gates, the arrival markers, the
# plates, the pass flash) where the question is "does it look right".
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 480x854 \
#       --script res://tools/capture_space_wave.gd -- <out dir> [options]
#
#   --kind math|arrow|rps     the question (default math)
#   --cycle N                 0: 2 gates, 1: 3, 2 and up: 4 (default 2)
#   --at 0.1,0.5,0.86,0.97    frames before judgement, as approach() fractions
#   --fly right|wrong|stay    where the ship goes (default right)
#   --after 0.07,0.2,0.4      frames after judgement, in seconds
#
# Writes <out dir>/wave_<kind>_<fly>.png, the frames left to right.
#
# It goes straight into a run and drives SpaceRun.tick by hand, as
# capture_space.gd does: no logo, splash or mode select to wait through,
# no random question kind to wait for, and the same frames on any PC. Only
# the menus' state is skipped — what is drawn is the real game's draw code.
# It plays a real wave, so the save file is backed up and written back.

const SAVE_PATH := "user://savegame.cfg"
const DT := 1.0 / 60.0

var m
var sp
var frames: Array[Image] = []


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_go.call_deferred()


func _opt(args: PackedStringArray, name: String, fallback: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _floats(text: String) -> Array[float]:
	var out: Array[float] = []
	for s in text.split(",", false):
		out.append(float(s))
	return out


func _tick(seconds: float) -> void:
	for i in maxi(1, int(round(seconds / DT))):
		_step()


func _step() -> void:
	sp.tick(DT, m.state == m.State.PLAYING, true)
	m._update_fx(DT)
	m._update_hearts(DT)
	if m.flash_time > 0.0:
		m.flash_time = maxf(0.0, m.flash_time - DT)
	if m.space_banner_elapsed >= 0.0:
		m.space_banner_elapsed += DT
		if m.space_banner_elapsed >= m.SPACE_BANNER_TIME:
			m.space_banner_elapsed = -1.0


func _grab() -> void:
	m.queue_redraw()
	if m.hud_canvas != null:
		m.hud_canvas.queue_redraw()
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	frames.append(root.get_texture().get_image())


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 and not args[0].begins_with("--") else "user://"
	var kind_name := _opt(args, "--kind", "math")
	var fly := _opt(args, "--fly", "right")
	var at := _floats(_opt(args, "--at", "0.1,0.5,0.86,0.97"))
	var after := _floats(_opt(args, "--after", "0.07,0.2,0.4"))

	var bak := FileAccess.get_file_as_bytes(SAVE_PATH)
	await process_frame
	await process_frame
	m = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	sp = m.space
	m.call("_reset_game")
	m.call("_set_state", m.State.PLAYING)
	m.tutorial_active = false
	m.set_process(false)
	# Main._process is what shows the pause button during a run; with it
	# stopped, show it here so the shot has the whole HUD.
	m.pause_button.visible = true

	sp.cycle = int(_opt(args, "--cycle", "2"))
	var kind: int = {"math": sp.Kind.MATH, "arrow": sp.Kind.ARROW, "rps": sp.Kind.RPS}.get(kind_name, sp.Kind.MATH)
	for w0 in sp.waves:
		for p in w0.planets:
			p.node.queue_free()
	sp.waves.clear()
	sp.spawn_wave(kind)
	var w: Dictionary = sp.upcoming_wave()

	var goal := Vector2.ZERO
	for p in w.planets:
		if (fly == "right" and p.correct) or (fly == "wrong" and not p.correct):
			goal = p.pos
			if fly == "wrong":
				break
	sp.ship_target = goal

	for t in at:
		while not w.resolved and sp.approach(w.planets[0]) < t:
			_step()
		await _grab()
	while not w.resolved:
		_step()
	var since := 0.0
	for s in after:
		_tick(s - since)
		since = s
		await _grab()

	var size := frames[0].get_size()
	var strip := Image.create(size.x * frames.size(), size.y, false, frames[0].get_format())
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, size), Vector2i(size.x * i, 0))
	var path := out.path_join("wave_%s_%s.png" % [kind_name, fly])
	strip.save_png(path)
	print("capture_space_wave: wrote %s (%d frames, score %d)" % [path, frames.size(), m.score])

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_buffer(bak)
	f.close()
	quit()
