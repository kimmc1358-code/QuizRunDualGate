extends SceneTree

# 하트 HUD 를 찍는다 — 가득 찬 상태, 하나 잃은 순간(빈 칸 위로 부풀며 사라지는
# 하트와 깜빡이는 캐릭터), 하나 남은 상태. 헤드리스가 아니라 창을 띄워 돌려야
# 한다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_hearts.gd -- --out <dir> [--mode <n>]
#
# check_hearts 는 칸의 위치와 규칙을 숫자로 보지만, 하트가 배경 위에서 읽히는지,
# 콤보 표시와 나란히 놓였을 때 어색하지 않은지는 그림으로만 답이 나온다.
# 진짜 판을 굴리므로 저장 파일을 떠 두었다 되돌린다.

const SAVE_PATH := "user://savegame.cfg"
var out_dir := "user://hearts_shots"
var mode := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			out_dir = args[i + 1]
		elif args[i] == "--mode":
			mode = int(args[i + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in range(2):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path: String = out_dir.path_join(name + ".png")
	img.save_png(path)
	print("  %s" % path)


func _gate(m: Node2D, correct: bool) -> void:
	var view: Vector2 = m.get_viewport_rect().size
	m.call("_spawn_gate", view)
	var g: Dictionary = m.gates[m.gates.size() - 1]
	var top: bool = g.top_correct if correct else not g.top_correct
	m.player_y = ((g.top_zone_top + g.top_zone_bottom) if top else (g.bottom_zone_top + g.bottom_zone_bottom)) * 0.5
	m.call("_resolve_gate", g, view)


func _run() -> void:
	var had := FileAccess.file_exists(SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(SAVE_PATH) if had else PackedByteArray()
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	m.call("_reset_game")
	m.call("_apply_mode", mode)
	m.call("_set_state", m.State.PLAYING)
	m.tutorial_active = false
	for i in range(6):
		_gate(m, true)
	m.gates.clear()
	var view: Vector2 = m.get_viewport_rect().size
	m.call("_spawn_gate", view)
	# 세상을 멈춰 둔다 — 찍는 사이 다음 게이트가 와서 판정되면 하트가 또 깎인다.
	m.set_process(false)
	m.queue_redraw()
	m.hud_canvas.queue_redraw()
	await _shot("hearts_full")
	m.call("_take_hit")
	# 부풀며 사라지는 하트의 한가운데, 그리고 캐릭터가 흐린 쪽 박자.
	m.heart_lost_elapsed = m.HEART_LOSS_POP_DURATION * 0.35
	m.hurt_elapsed = m.HURT_BLINK_PERIOD * 1.5
	m.queue_redraw()
	m.hud_canvas.queue_redraw()
	await _shot("hearts_hit")
	m.call("_take_hit")
	m.heart_lost_elapsed = -1.0
	m.hurt_elapsed = -1.0
	m.queue_redraw()
	m.hud_canvas.queue_redraw()
	await _shot("hearts_one_left")
	if had:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	quit(0)
