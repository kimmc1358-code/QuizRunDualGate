extends SceneTree

# 고른 카드 왼쪽 위의 초록 체크가 글자도 캐릭터도 가리지 않는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_mode_card_check.gd
#
# 눈으로는 못 지키는 조건이다. 네 카드의 이름 길이가 다르고("FLAG MODE" 대
# "STROOP MODE") 캐릭터 배율도 다르므로(CARD_CHARACTER_SCALE 의 유니콘 1.20),
# 한 카드에서 넉넉해 보이는 여백이 다른 카드에서는 없다. 게다가 카드를 하나씩
# 골라 봐야 보이는 상태라, 스크린샷 한 장으로는 넷 중 하나만 확인된다.
#
# 그림이 아니라 사각형으로 잰다:
#   - 이름판(_card_name_plate)은 가운데 정렬이라 그 왼쪽에 구석이 남는다.
#   - 캐릭터(_card_art)는 정사각 칸이지만 그림은 그 안에서 투명 여백을
#     두르고 있으므로, 칸이 아니라 텍스처의 불투명 경계로 잰다. 칸으로 재면
#     유니콘처럼 1.20 배로 넘치는 카드가 늘 실패한다.
#   - 그리고 체크는 카드 밖으로 나가서도 안 된다.
#
# 자리는 화면의 _check_rect() 를 그대로 부른다. 여기에 계산을 복사해 두면
# 배치를 옮겨도 체커는 옛 자리를 검사하며 통과한다.

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


# 노드가 실제로 그리는 그림의 불투명 사각형. 칸 안에서 그림이 차지하는 비율을
# 텍스처에서 재어 화면 좌표로 옮긴다.
func _opaque_screen_rect(node: Control) -> Rect2:
	var tex: Texture2D = null
	if node is TextureRect:
		tex = (node as TextureRect).texture
	if tex == null:
		return node.get_global_transform() * Rect2(Vector2.ZERO, node.size)
	var img: Image = tex.get_image()
	if img == null:
		return node.get_global_transform() * Rect2(Vector2.ZERO, node.size)
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return node.get_global_transform() * Rect2(Vector2.ZERO, node.size)
	var w: float = float(img.get_width())
	var h: float = float(img.get_height())
	# STRETCH_KEEP_ASPECT_CENTERED 로 그리므로, 칸 안에서 그림은 가장 긴 변에
	# 맞춰 균일 축소되고 나머지 축은 가운데 정렬된다.
	# 칸 자체도 부모 scale 로 그려지므로 전역 변환으로 옮긴 사각형에서 잰다.
	var cell: Rect2 = node.get_global_transform() * Rect2(Vector2.ZERO, node.size)
	var s: float = minf(cell.size.x / w, cell.size.y / h)
	var drawn := Vector2(w * s, h * s)
	var origin: Vector2 = cell.position + (cell.size - drawn) * 0.5
	return Rect2(
		origin + Vector2(float(used.position.x), float(used.position.y)) * s,
		Vector2(float(used.size.x), float(used.size.y)) * s)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame
	var screen = main.get("mode_select_panel")
	if screen == null:
		print("  FAIL: no mode_select_panel")
		quit(1)
		return
	# 실제 해상도로 배치시킨다. 헤드리스 뷰포트는 정사각형을 보고하므로 그대로
	# 두면 카드가 화면보다 넓은 자리에 놓여 여백 검사가 거저 통과한다.
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	screen.size = view
	screen.call("_layout")
	await process_frame

	var tex: Texture2D = screen.get("_check_texture")
	if tex == null:
		_fail("check icon did not load — is %s missing? (tools/slice_popup_icons_2.ps1)" % screen.get("CARD_CHECK_FILE"))

	var cards: Array = screen.get("_cards")
	var names: Array = screen.get("_card_name_plate")
	var arts: Array = screen.get("_card_art")
	var labels: Array = screen.get("_card_name")
	print("check_mode_card_check: viewport %.0fx%.0f, %d cards" % [view.x, view.y, cards.size()])
	print("")
	print("  %-6s %-22s %-22s %-22s %s" % ["card", "check rect", "name plate", "character ink", "verdict"])

	for i in range(cards.size()):
		# 카드마다 골라 본다 — 체크는 고른 카드에만 붙고, 카드마다 이름 길이와
		# 캐릭터 배율이 달라 여백이 같지 않다.
		screen.call("_select", i, false)
		await process_frame
		var card_rect: Rect2 = screen.call("_selected_card_rect")
		var check: Rect2 = screen.call("_check_rect", i, card_rect)
		var plate: Rect2 = screen.call("_drawn_rect", names[i])
		var ink: Rect2 = _opaque_screen_rect(arts[i])

		var problems := []
		if check.intersects(plate):
			problems.append("covers the name plate")
		if check.intersects(ink):
			problems.append("covers the character")
		# 카드 밖으로 나가면 옆 카드 위에 뜬다.
		if not card_rect.encloses(check):
			problems.append("hangs outside the card")
		# 그리고 실제로 보이는 크기여야 한다. 0 에 가까우면 위의 검사가 전부
		# 저절로 통과하므로, 이 체커가 아무것도 안 지키게 된다.
		if check.size.x < card_rect.size.x * 0.10:
			problems.append("is under 10%% of the card wide — too small to read, and too small for these checks to mean anything")

		if not problems.is_empty():
			_fail("card %d (%s): the check %s" % [i, labels[i].text, ", ".join(problems)])
		print("  %-6d %-22s %-22s %-22s %s" % [
			i,
			"%.0f,%.0f %.0fx%.0f" % [check.position.x, check.position.y, check.size.x, check.size.y],
			"%.0f,%.0f %.0fx%.0f" % [plate.position.x, plate.position.y, plate.size.x, plate.size.y],
			"%.0f,%.0f %.0fx%.0f" % [ink.position.x, ink.position.y, ink.size.x, ink.size.y],
			"ok" if problems.is_empty() else "FAIL"])

	# 고른 카드가 실제로 커지는가. 요청한 105% 가 그대로 걸려 있어야 한다.
	print("")
	screen.call("_select", 1, false)
	await process_frame
	var want: float = screen.get("CARD_SELECTED_SCALE")
	for i in range(cards.size()):
		var s: float = cards[i].scale.x
		var expect: float = want if i == 1 else 1.0
		if absf(s - expect) > 0.001:
			_fail("card %d is at %.3f scale, want %.3f" % [i, s, expect])
	print("  selected card scale %.2f, others 1.00" % cards[1].scale.x)
	if want <= 1.0:
		_fail("CARD_SELECTED_SCALE is %.2f — the selected card would not grow at all" % want)

	# ---- 히든 모드의 잠금과 안내가 짝이 맞는가 ----
	#
	# 출시 때 hidden_mode_open 을 false 로 되돌리는데, 그때 설명문을 같이
	# 되돌리는 것을 잊으면 잠긴 카드가 "세 퀴즈가 번갈아 나온다"고 광고한다.
	# 반대로 지금 열어 두고 설명문만 잠금용으로 두면, 이미 열린 모드를 못 연
	# 것처럼 안내한다. 어느 쪽도 화면만 봐서는 틀렸다고 알 수 없다 — 두 문장
	# 다 그럴듯하게 읽히기 때문이다.
	#
	# 잠금 자체는 여기서 못 잰다. OS.is_debug_build() 가 이 스크립트에서는
	# 언제나 true 라, hidden_mode_open 이 false 여도 게이트가 통과된다.
	# 실제 잠김은 릴리스로 내보내 눌러 봐야 한다.
	print("")
	var modes: Array = screen.get("CARD_MODES")
	var hidden: int = screen.get("MODE_HIDDEN")
	var hidden_card: int = modes.find(hidden)
	if hidden_card < 0:
		_fail("no card maps to MODE_HIDDEN")
	else:
		var was: bool = screen.get("hidden_mode_open")
		var locked_text: String = screen.get("CARD_EXPLAIN")[hidden_card]
		var open_text: String = screen.get("CARD_EXPLAIN_HIDDEN_OPEN")
		if locked_text == open_text:
			_fail("the locked and open blurbs are the same string — one of the two states is unlabelled")
		for open in [true, false]:
			screen.set("hidden_mode_open", open)
			screen.call("_select", hidden_card, false)
			await process_frame
			var shown: String = screen.get("_explain_label").text
			var want_text: String = open_text if open else locked_text
			if shown != want_text:
				_fail("hidden_mode_open = %s shows \"%s\", want \"%s\"" % [open, shown, want_text])
			print("  hidden_mode_open %-5s -> \"%s\"" % [open, shown])
		screen.set("hidden_mode_open", was)
		# 그리고 나갈 수 있는 문구가 전부 설명 바 안에 들어가야 한다. 글자
		# 크기는 _fit_explain_size 가 _explain_candidates() 를 훑어 한 번에
		# 정하므로, 거기서 빠진 문구는 크기 계산에 반영되지 않고 출시 때
		# 뒤집는 순간 잘린다.
		#
		# 그 목록을 여기서 다시 부르면 안 된다 — 처음에 그렇게 썼더니,
		# _explain_candidates() 에서 문구를 빼는 순간 피팅과 검사가 같이 눈을
		# 감아 통과했다. 검사할 문구는 상수에서 직접 모은다.
		var must_fit: Array = screen.get("CARD_EXPLAIN").duplicate()
		must_fit.append(open_text)
		var label: Label = screen.get("_explain_label")
		var font: Font = label.get_theme_font("font")
		var fs: int = label.get_theme_font_size("font_size")
		var room: float = label.size.x
		for text in must_fit:
			var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			if w > room + 0.5:
				_fail("\"%s\" is %.0fpx at size %d but the bar holds %.0f — is it missing from _explain_candidates()?" % [
					text, w, fs, room])
		print("  all %d blurbs fit the bar at size %d (room %.0fpx)" % [must_fit.size(), fs, room])
		screen.call("_select", 0, false)

	print("")
	if fails == 0:
		print("check_mode_card_check: OK")
	else:
		print("check_mode_card_check: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
