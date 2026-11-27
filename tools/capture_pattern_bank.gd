extends SceneTree
# The pattern bank (SpaceRun.BANK) on one sheet: every pattern at every
# level, one row a pattern, one column a level, each the question box and
# the first step's gates as they come in. For choosing what goes where when
# the placement is drawn up, and for any change to a pattern or a level.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 480x854 \
#       --script res://tools/capture_pattern_bank.gd -- <out dir> [--at 0.8]
#
#   --at F    how far in the step is when shot, as an approach() fraction
#             (default 0.8)
#
# Writes two sheets, <out dir>/pattern_bank_color.png and
# pattern_bank_arrow.png. Each memory pattern is shot after its round's
# first gate as well, as a last row, since that is where its "?" shows.
#
# It drives SpaceRun.tick by hand like capture_space_wave.gd, so the frames
# are the same on any PC, and plays real steps, so the save file is backed
# up and written back.

const SAVE_PATH := "user://savegame.cfg"
const DT := 1.0 / 60.0
const CROP := Rect2i(0, 60, 480, 540)    # the question box down to the gates
const SCALE := 0.5
var m
var sp
var at := 0.8                    # --at


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_go.call_deferred()


func _opt(args: PackedStringArray, name: String, fallback: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _step() -> void:
	sp.tick(DT, true, true)
	m._update_fx(DT)


func _shot() -> Image:
	m.queue_redraw()
	if m.hud_canvas != null:
		m.hud_canvas.queue_redraw()
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image().get_region(CROP)
	img.resize(int(CROP.size.x * SCALE), int(CROP.size.y * SCALE), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)   # blit_rect copies nothing between formats
	return img


func _start(kind: int, level: int) -> Dictionary:
	for w0 in sp.waves:
		for p in w0.planets:
			p.node.queue_free()
	sp.waves.clear()
	for r in sp.rocks:
		r.node.queue_free()
	sp.rocks.clear()
	sp._begin_pattern(kind, level)
	return sp.upcoming_wave()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 and not args[0].begins_with("--") else "user://"
	at = float(_opt(args, "--at", "0.8"))
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
	m.pause_button.visible = true

	var K = sp.Kind
	var sheets := {
		"color": [[K.COLOR, false], [K.MIX, false], [K.SPOT, false], [K.MEMORY, false], [K.MEMORY, true], [K.SHELL, false]],
		"arrow": [[K.ARROW, false], [K.ARROW_MIX, false], [K.ARROW_SUM, false], [K.ARROW_MEMORY, false], [K.ARROW_MEMORY, true]],
	}
	for sheet_name in sheets:
		await _sheet(out, sheet_name, sheets[sheet_name])

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_buffer(bak)
	f.close()
	quit()


## One sheet: a row for each [kind, after its first gate] in `rows`.
func _sheet(out: String, sheet_name: String, rows: Array) -> void:
	var cols := 0
	for kind in sp.BANK.keys():
		cols = maxi(cols, (sp.BANK[kind] as Array).size())

	var cw := int(CROP.size.x * SCALE)
	var ch := int(CROP.size.y * SCALE)
	var sheet := Image.create(cw * cols, ch * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.02, 0.05))
	for ri in rows.size():
		var kind: int = rows[ri][0]
		var after_first: bool = rows[ri][1]
		for li in (sp.BANK[kind] as Array).size():
			var w := _start(kind, li + 1)
			sp.ship_target = Vector2(0.0, -0.4)
			if after_first:
				# Into the right gate, then on until the next step is in.
				for p in w.planets:
					if p.correct:
						sp.ship_target = p.pos
				while not w.resolved:
					_step()
				w = sp.upcoming_wave()
				sp.ship_target = Vector2(0.0, -0.4)
			while not w.is_empty() and not w.resolved and sp.approach(w.planets[0]) < at:
				_step()
			var img: Image = await _shot()
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(li * cw, ri * ch))
	var path := out.path_join("pattern_bank_%s.png" % sheet_name)
	sheet.save_png(path)
	print("capture_pattern_bank: wrote %s (rows: %s)" % [path, str(rows.map(func(r): return sp.Kind.keys()[r[0]] + (" after" if r[1] else "")))])
