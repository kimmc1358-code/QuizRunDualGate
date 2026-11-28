extends SceneTree
# Shoots the space game at each step of its cycle: a colour pattern with its
# steps in sight, the same pattern a few right gates into a streak, an
# arrow pattern, the boss fight and fever.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 480x854 \
#       --script res://tools/capture_space.gd -- <out dir>
#
# It drives SpaceRun.tick by hand rather than waiting in real time, so the
# frames are the same on any PC. It plays real steps, so the save file is
# backed up and written back like the checkers do.
var m
var sp
var out := ""


func _init():
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_go.call_deferred()


func _shot(name: String) -> void:
	m.queue_redraw()
	if m.hud_canvas != null:
		m.hud_canvas.queue_redraw()
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name)


func _tick(seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(seconds / dt):
		# Rocks are not what these shots are about; a hit would end the run.
		m.hurt_elapsed = 0.5
		sp.tick(dt, m.state == m.State.PLAYING, true)
		m._update_fx(dt)
		m._update_hearts(dt)
		if m.flash_time > 0.0:
			m.flash_time = maxf(0.0, m.flash_time - dt)
		if m.space_banner_elapsed >= 0.0:
			m.space_banner_elapsed += dt
			if m.space_banner_elapsed >= m.SPACE_BANNER_TIME:
				m.space_banner_elapsed = -1.0
		if m.power_banner_t >= 0.0:
			m.power_banner_t += dt
			if m.power_banner_t >= m.POWER_BANNER_TIME:
				m.power_banner_t = -1.0
	m.hurt_elapsed = -1.0


func _restart_pattern(kind: int) -> void:
	for w in sp.waves:
		for p in w.planets:
			p.node.queue_free()
	sp.waves.clear()
	for r in sp.rocks:
		r.node.queue_free()
	sp.rocks.clear()
	sp.phase = sp.Phase.PATTERN
	sp._begin_pattern(kind)


func _correct(w: Dictionary) -> Vector2:
	for p in w.planets:
		if p.correct:
			return p.pos
	return Vector2.ZERO


## Flies the front step through its right gate.
func _pass_right() -> void:
	var w: Dictionary = sp.upcoming_wave()
	sp.ship_target = _correct(w)
	while not w.resolved and m.state == m.State.PLAYING:
		_tick(1.0 / 60.0)


func _go():
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	var bak := FileAccess.get_file_as_bytes("user://savegame.cfg")
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

	sp.cycle = 1                 # three gates a step, and red arrows possible
	_restart_pattern(sp.Kind.COLOR)
	sp.ship_target = Vector2(0.3, -0.6)
	_tick(2.4)
	await _shot("space_1_color.png")
	for i in 3:
		_pass_right()
	_tick(0.15)
	await _shot("space_2_streak.png")

	_restart_pattern(sp.Kind.ARROW)
	_tick(2.4)
	await _shot("space_3_arrow.png")

	sp.weapon = sp.Weapon.SPREAD
	sp.level = 6
	sp.drones = 1
	sp._sync_drones()
	_restart_pattern(sp.Kind.COLOR)
	for w in sp.waves:
		for p in w.planets:
			p.node.queue_free()
	sp.waves.clear()
	sp._enter(sp.Phase.BOSS)
	sp.ship_target = Vector2(-0.6, -1.2)
	_tick(3.2)
	await _shot("space_4_boss.png")

	sp._remove_boss()
	sp._enter(sp.Phase.FEVER)
	sp.ship_target = Vector2(0.4, 0.6)
	_tick(2.0)
	await _shot("space_5_fever.png")

	var f := FileAccess.open("user://savegame.cfg", FileAccess.WRITE)
	f.store_buffer(bak)
	f.close()
	quit()
