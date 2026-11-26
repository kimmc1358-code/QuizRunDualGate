extends SceneTree
# The 2.0 mode select (ModeSelectScreen.gd, 2026-11-27) across seven screen
# ratios, each viewport derived from the project's stretch setting.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_mode_select_layout.gd
#
# Checks:
#   1. The stretch aspect is keep_width, so a tablet held upright keeps the
#      480x854 viewport with bars beside it instead of a wider game.
#   2. No two blocks overlap and none leaves the screen, at every ratio.
#
# The banner reserve this used to check went with the banner ad (2026-11-27).
#
# A headless viewport is square, so each ratio's size is set on the screen
# by hand rather than read from the window.

const RATIOS := [
	["4:3 tablet", 4.0 / 3.0], ["16:10", 1.6], ["16:9", 16.0 / 9.0],
	["18:9", 2.0], ["19.5:9", 19.5 / 9.0], ["20:9", 20.0 / 9.0], ["21:9", 21.0 / 9.0],
]
const EPS := 0.5

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


func _viewport_for(ratio: float, base: Vector2) -> Vector2:
	if ratio >= base.y / base.x:
		return Vector2(base.x, base.x * ratio)
	if str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep_width":
		return base
	return Vector2(base.y / ratio, base.y)


## The blocks that must not overlap: everything the layout placed, the
## emblem as the box it is drawn in, the tool row with its labels.
func _blocks(s: Control) -> Array:
	var r: Dictionary = s.layout_rects()
	var k: float = s.size.x / 480.0
	var out := []
	for key in ["login", "setting", "stardust", "card0", "card1", "card2", "explain", "play", "remove_ads"]:
		out.append([key, r[key]])
	var em: Vector2 = r.emblem_mid
	var eh: float = s.EMBLEM_H * k
	out.append(["emblem", Rect2(Vector2(s.MARGIN * k, em.y - eh * 0.5), Vector2(s.size.x - s.MARGIN * 2.0 * k, eh))])
	for i in 3:
		var t: Rect2 = r["tool%d" % i]
		out.append(["tool%d" % i, Rect2(t.position, t.size + Vector2(0, s.TOOL_LABEL_H * k))])
	return out


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame
	var s: Control = main.get("mode_select_panel")
	s.ensure_built()
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	print("check_mode_select_layout: base %dx%d, %d ratios" % [base.x, base.y, RATIOS.size()])

	if str(ProjectSettings.get_setting("display/window/stretch/aspect")) != "keep_width":
		_fail("stretch aspect is %s, not keep_width" % ProjectSettings.get_setting("display/window/stretch/aspect"))

	for rc in RATIOS:
		var view := _viewport_for(rc[1], base)
		s.size = view
		var where := "%s %.0fx%.0f" % [rc[0], view.x, view.y]
		var blocks := _blocks(s)
		for b in blocks:
			var rect: Rect2 = b[1]
			if rect.position.x < -EPS or rect.position.y < -EPS or rect.end.x > view.x + EPS or rect.end.y > view.y + EPS:
				_fail("%s: %s %s leaves the screen" % [where, b[0], rect])
		for i in blocks.size():
			for j in range(i + 1, blocks.size()):
				var a: Rect2 = blocks[i][1]
				var c: Rect2 = blocks[j][1]
				if a.grow(-EPS).intersects(c.grow(-EPS)):
					_fail("%s: %s overlaps %s" % [where, blocks[i][0], blocks[j][0]])
		print("  %-12s %4.0fx%-5.0f  %s" % [rc[0], view.x, view.y, "ok" if fails == 0 else "FAIL"])

	if fails == 0:
		print("check_mode_select_layout: OK")
		quit(0)
	else:
		print("check_mode_select_layout: %d failure(s)" % fails)
		quit(1)
