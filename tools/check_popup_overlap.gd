@tool
extends SceneTree

# Instantiates the real Main scene and measures, with the real font at the
# real sizes, whether the BOOST popup (top-left, left-anchored) can ever
# touch the combo readout (top-right, right-anchored).
#
# Worth a script rather than an eyeball: the two only collide at high combo
# with a large bonus, which is exactly the state that is hardest to reach by
# hand in a playtest.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_popup_overlap.gd

var main: Node
var frames := 0


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false   # let _ready finish loading fonts
	_check()
	return true


func _check() -> void:
	# NOT the headless viewport — that comes back square and far wider than
	# the game actually runs at, which would make this check pass by default.
	# The shipped resolution is what matters.
	var view_size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var problems_pre := 0
	var zone_top: float = main._gate_zone_top(view_size)
	var zone_bottom: float = main._gate_zone_bottom(view_size)
	print("viewport %.0f x %.0f   gate zone %.0f..%.0f\n" % [view_size.x, view_size.y, zone_top, zone_bottom])

	# The gradient fill draws the popup from a texture assembled out of the
	# font's glyph atlas (see _text_as_texture), and that assembly has one
	# failure mode that looks fine from every angle except the screen: the
	# atlas can be L8 or LA8 and the coverage lives in a different channel in
	# each. Read the wrong one on an LA8 atlas and every pixel comes back
	# 1.0, so the "text" is a filled rectangle — the gradient still ramps
	# correctly down it, which is exactly why it would survive a glance at
	# the numbers.
	#
	# A real word is mostly empty space. Measured both ways rather than
	# guessed at: assembled correctly these two strings come out 66% clear,
	# and with the channel misread they come out 39% — not 0%, because only
	# each glyph's own box fills in and the gaps between boxes stay empty. So
	# the threshold has to sit between those, not merely above zero; 0.25 was
	# the first guess and it passed the broken build.
	var font: Font = main.get("combo_font")
	for spec in [["TURBO!", main.get("BOOST_POP_FONT_SIZE_BEST")], ["BOOST!", main.get("BOOST_POP_FONT_SIZE_MID")]]:
		var text: String = spec[0]
		var size: int = spec[1]
		var tex: Texture2D = main.call("_text_as_texture", font, size, text)
		if tex == null:
			print("  %-7s FAIL: no texture assembled" % text)
			problems_pre += 1
			continue
		var img: Image = tex.get_image()
		var clear := 0
		var total: int = img.get_width() * img.get_height()
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a < 0.02:
					clear += 1
		var clear_frac: float = float(clear) / float(total)
		# And the assembled width must track what draw_string would measure,
		# or the outline passes and the fill drift apart.
		var expect_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var drift: float = absf(img.get_width() - expect_w)
		var ok: bool = clear_frac > 0.50 and drift <= 6.0
		if not ok:
			problems_pre += 1
		print("  %-7s @%d  tex %dx%d  clear %.0f%%  width drift %.0fpx vs Font.get_string_size  %s" % [
			text, size, img.get_width(), img.get_height(), clear_frac * 100.0, drift,
			"ok" if ok else "FAIL (correct is ~66% clear; a mis-read channel gives ~39%)"])
	print("")
	print("%-6s %-14s %-7s %-20s %-20s %-6s %s" % [
		"combo", "boost text", "char y", "boost rect x/y", "combo rect x/y", "fit", "verdict"])

	var problems := problems_pre
	# The popup is anchored to the character, so its position depends on where
	# in the lane the pass happened — sweep the whole zone, not one spot.
	for combo in [1, 8, 25, 60]:
		main.combo = combo
		var combo_rect: Rect2 = main._combo_display_rect(view_size)
		# Only positions the character can actually occupy: _update_playing
		# clamps it so its hitbox stays inside the lane.
		var half_h: float = float(main.PLAYER_SIZE.y) * 0.5
		for char_frac in [0.0, 0.25, 0.5, 1.0]:
			var char_y: float = lerpf(zone_top + half_h, zone_bottom - half_h, char_frac)
			for is_best in [true, false]:
				# The largest bonus this combo can produce — i.e. the widest
				# the string ever gets.
				var mult: float = main.boost_bonus_best_multiplier if is_best else main.boost_bonus_mid_multiplier
				var base: int = main.SCORE_PER_COMBO * combo
				var points: int = int(round(base * (1.0 + mult))) - base
				if points <= 0:
					continue
				# 게임 자기 함수를 부른다 — 여기에 포맷을 복사해 두면 이름이 바뀌어도
				# 조용히 옛 문자열을 재게 된다(실제로 BOOST!! -> TURBO! 때 그럴 뻔했다).
				var text: String = main.call("_boost_pop_text", points, is_best)
				# Peak of the pop: widest font AND highest rise, the one frame
				# most likely to collide.
				var offset: Vector2 = main.BOOST_POP_CHARACTER_OFFSET
				var anchor: Vector2 = Vector2(float(main.PLAYER_X), char_y) + offset \
					- Vector2(0.0, float(main.BOOST_POP_RISE))
				var layout: Dictionary = main._boost_pop_layout(
					view_size, text, is_best, anchor, main.POP_PEAK_SCALE)
				var rect: Rect2 = layout["rect"]
				var overlaps: bool = combo_rect.size.x > 0.0 and rect.intersects(combo_rect)
				# Inside the GATE ZONE, not merely inside the screen — above
				# the zone sits the quiz box and the boost bar.
				var on_screen: bool = rect.position.x >= 0.0 and rect.end.x <= view_size.x \
					and rect.position.y >= zone_top and rect.end.y <= zone_bottom
				if overlaps or not on_screen:
					problems += 1
				var nominal: int = main.BOOST_POP_FONT_SIZE_BEST if is_best else main.BOOST_POP_FONT_SIZE_MID
				print("%-6d %-14s %-7s %-20s %-20s %-6s %s" % [
					combo, text, "%.0f" % char_y,
					"%.0f-%.0f / %.0f-%.0f" % [rect.position.x, rect.end.x, rect.position.y, rect.end.y],
					"%.0f-%.0f / %.0f-%.0f" % [combo_rect.position.x, combo_rect.end.x, combo_rect.position.y, combo_rect.end.y],
					"%d/%d" % [layout["font_size"], int(round(nominal * main.POP_PEAK_SCALE))],
					"ok" if (not overlaps and on_screen) else ("OVERLAP" if overlaps else "OFF-SCREEN")])

	print("\n", "PASS — BOOST never touches the combo block, never leaves the screen" if problems == 0 else "FAIL (%d problems)" % problems)
	quit(0 if problems == 0 else 1)
