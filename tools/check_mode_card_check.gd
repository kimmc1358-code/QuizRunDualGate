extends SceneTree

# 고른 카드 왼쪽 위의 초록 체크가 글자도 캐릭터도 가리지 않는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_mode_card_check.gd
#
# 눈으로는 못 지키는 조건이다. 네 카드의 캐릭터 배율이 다르고
# (CARD_CHARACTER_SCALE 의 유니콘 1.20) 이름판 너비는 네 이름 중 가장 긴
# 것이 정하는데 그 이름이 번역되므로, 언어를 바꾸면 넷 다 판 너비가 바뀐다.
# 게다가 카드를 하나씩 골라 봐야 보이는 상태라, 스크린샷 한 장으로는 넷 중
# 하나만, 그것도 한 언어에서만 확인된다.
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
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))

	var tex: Texture2D = screen.get("_check_texture")
	if tex == null:
		_fail("check icon did not load — is %s missing? (tools/slice_popup_icons_2.ps1)" % screen.get("CARD_CHECK_FILE"))

	var cards: Array = screen.get("_cards")
	var names: Array = screen.get("_card_name_plate")
	var arts: Array = screen.get("_card_art")
	var labels: Array = screen.get("_card_name")

	# 기준 비율 하나로는 모자란다. CARD_HEIGHT_SCALE 이 남는 세로에서 카드를
	# 늘리는데, 늘어난 몫은 전부 캐릭터에게 가므로 캐릭터만 커지고 체크는
	# 그대로다. 16:9 는 늘어날 자리가 없어 아무 일도 안 일어나는 비율이라,
	# 거기서만 재면 정작 캐릭터가 가장 큰 화면을 한 번도 안 보게 된다.
	#
	# 언어도 함께 훑는다. 이름판 너비는 네 이름 중 가장 긴 것이 정하고 그
	# 이름은 번역되므로, 판 너비도 체크가 들어갈 구석도 언어마다 다르다 —
	# 한 언어만 재면 다른 언어에서만 겹치는 것을 못 본다. 실제로 한국어
	# 이름은 넷 다 다섯 자라 영어보다 판이 40px 좁다.
	var heights: Array[float] = []
	var plate_sizes: Array[Vector2] = []
	var plate_widths: Array[Vector2] = []
	var was_locale: String = TranslationServer.get_locale()
	for combo in [["en", base.y], ["en", base.x * 20.0 / 9.0],
			["ko", base.y], ["ko", base.x * 20.0 / 9.0]]:
		TranslationServer.set_locale(str(combo[0]))
		screen.call("rebuild")
		var h: float = float(combo[1])
		var view := Vector2(base.x, h)
		screen.size = view
		screen.call("_layout")
		await process_frame
		var card_h: float = cards[0].size.y
		heights.append(card_h)
		# 카드가 커질 때 안쪽 판까지 같이 부풀면 안 된다. 한 번 그렇게 됐는데,
		# 점수판이 세로 22.8 -> 26.9 로 늘면서 가로는 149.9 -> 147.1 로 줄어
		# 눌린 모양이 됐다. 크기 자체가 아니라 "비율이 달라졌는가"가 문제라,
		# 두 비율에서 같은 값이 나오는지로 본다.
		plate_sizes.append(Vector2(
			screen.get("_card_name_plate")[0].size.y,
			screen.get("_card_best_plate")[0].size.y))
		plate_widths.append(Vector2(
			screen.get("_card_name_plate")[0].size.x,
			screen.get("_card_best_plate")[0].size.x))
		print("")
		print("check_mode_card_check: %s, viewport %.0fx%.0f, %d cards, card %.0fx%.0f" % [
			str(combo[0]), view.x, view.y, cards.size(), cards[0].size.x, card_h])
		print("  %-6s %-22s %-22s %-22s %s" % ["card", "check rect", "name plate", "character ink", "verdict"])

		for i in range(cards.size()):
			# 카드마다 골라 본다 — 체크는 고른 카드에만 붙고, 카드마다 이름
			# 길이와 캐릭터 배율이 달라 여백이 같지 않다.
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
				_fail("%.0fx%.0f card %d (%s): the check %s" % [
					view.x, view.y, i, labels[i].text, ", ".join(problems)])
			print("  %-6d %-22s %-22s %-22s %s" % [
				i,
				"%.0f,%.0f %.0fx%.0f" % [check.position.x, check.position.y, check.size.x, check.size.y],
				"%.0f,%.0f %.0fx%.0f" % [plate.position.x, plate.position.y, plate.size.x, plate.size.y],
				"%.0f,%.0f %.0fx%.0f" % [ink.position.x, ink.position.y, ink.size.x, ink.size.y],
				"ok" if problems.is_empty() else "FAIL"])

	# 긴 화면에서 카드가 실제로 커졌어야 한다. 안 커졌다면 위의 두 바퀴는 같은
	# 화면을 두 번 잰 것이고, 이 확장은 아무것도 안 지킨 셈이다.
	if heights.size() < 2 or heights[1] <= heights[0] + 1.0:
		_fail("the 20:9 card is %.1fpx tall against 16:9's %.1f — CARD_HEIGHT_SCALE is doing nothing, so this sweep measured the same screen twice" % [
			heights[1] if heights.size() > 1 else 0.0, heights[0] if heights.size() > 0 else 0.0])
	else:
		print("")
		print("  card height %.1f (16:9) -> %.1f (20:9), contents held at the 16:9 size" % [
			heights[0], heights[1]])
	TranslationServer.set_locale(was_locale)
	screen.call("rebuild")
	# 비율 둘씩 짝지어 언어별로 본다 — 판이 카드 높이를 타고 있는지가 질문이고,
	# 언어가 바뀌면 판 너비는 바뀌어도 되는 값이다.
	print("")
	for pair in [[0, 1, "en"], [2, 3, "ko"]]:
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		if plate_sizes.size() <= b:
			continue
		var dh: Vector2 = plate_sizes[b] - plate_sizes[a]
		var dw: Vector2 = plate_widths[b] - plate_widths[a]
		if absf(dh.x) > 0.5 or absf(dw.x) > 0.5:
			_fail("%s: the name plate is %.1fx%.1f at 16:9 but %.1fx%.1f at 20:9 — it is riding the card height" % [
				str(pair[2]), plate_widths[a].x, plate_sizes[a].x, plate_widths[b].x, plate_sizes[b].x])
		if absf(dh.y) > 0.5 or absf(dw.y) > 0.5:
			_fail("%s: the BEST plate is %.1fx%.1f at 16:9 but %.1fx%.1f at 20:9 — it is riding the card height" % [
				str(pair[2]), plate_widths[a].y, plate_sizes[a].y, plate_widths[b].y, plate_sizes[b].y])
		print("  %s: name plate %.1fx%.1f, BEST plate %.1fx%.1f — unchanged by the growth" % [
			str(pair[2]), plate_widths[a].x, plate_sizes[a].x, plate_widths[a].y, plate_sizes[a].y])

	# ---- 점수판 한 줄 ----
	#
	# 왕관 + "BEST" + 숫자가 한 줄로 판 안에 들어가야 한다. 판 너비는 카드
	# 너비 비율로만 정해져 숫자가 길어져도 넓어지지 않으므로, 셋 중 무엇을
	# 키워도 넘칠 수 있다 — "BEST" 를 숫자보다 크게 잡은 뒤로는 특히.
	# 넘쳐도 오류는 안 난다: HBox 가 조용히 왕관을 눌러 버리거나 글자가 판
	# 밖으로 걸쳐 나갈 뿐이라, 스크린샷 한 장으로도 알아채기 어렵다.
	#
	# 그리고 네 카드가 서로 같아야 한다. 카드마다 이름 길이도 캐릭터 배율도
	# 다르지만 점수판은 넷이 나란히 읽히는 자리다 — 하나만 글자가 크면 그
	# 모드가 특별한 것처럼 보인다.
	#
	# 가장 긴 표기로 재야 의미가 있다. ScoreFormat.compact 는 다섯 자를 넘지
	# 않지만 어느 다섯 자가 가장 넓은지는 글꼴이 정하므로, 자릿수가 다른
	# 후보를 훑어 가장 넓은 것을 쓴다.
	print("")
	var worst_scores := [0, 88888, 888888, 8888888, 888888888, 2147483647]
	for h in [base.y, base.x * 20.0 / 9.0]:
		screen.size = Vector2(base.x, h)
		screen.call("_layout")
		await process_frame
		var best_fs: Array[int] = []
		var score_fs: Array[int] = []
		var plate_wh: Array[Vector2] = []
		var widest := 0.0
		var widest_text := ""
		var widest_card := 0
		for value in worst_scores:
			var row_values := PackedInt32Array()
			for m in range(4):
				row_values.append(int(value))
			screen.call("set_best_scores", row_values)
			await process_frame
			for i in range(cards.size()):
				var row: Control = screen.get("_card_best_row")[i]
				var need: float = row.get_combined_minimum_size().x
				if need > widest:
					widest = need
					widest_text = screen.get("_card_score")[i].text
					widest_card = i
		for i in range(cards.size()):
			best_fs.append(screen.get("_card_best")[i].get_theme_font_size("font_size"))
			score_fs.append(screen.get("_card_score")[i].get_theme_font_size("font_size"))
			plate_wh.append(screen.get("_card_best_plate")[i].size)
		var plate_w: float = plate_wh[0].x
		print("  %.0fx%.0f: BEST plate %.1fx%.1f, \"BEST\" %dpx, score %dpx, widest row %.1f (\"%s\")" % [
			base.x, h, plate_wh[0].x, plate_wh[0].y, best_fs[0], score_fs[0], widest, widest_text])
		if widest > plate_w:
			_fail("the BEST row needs %.1fpx for \"%s\" on card %d but its plate is %.1f — crown, BEST or the number is too big" % [
				widest, widest_text, widest_card, plate_w])
		for i in range(1, cards.size()):
			if best_fs[i] != best_fs[0]:
				_fail("card %d draws \"BEST\" at %dpx but card 0 draws it at %d" % [i, best_fs[i], best_fs[0]])
			if score_fs[i] != score_fs[0]:
				_fail("card %d draws its score at %dpx but card 0 draws it at %d" % [i, score_fs[i], score_fs[0]])
			if not plate_wh[i].is_equal_approx(plate_wh[0]):
				_fail("card %d's BEST plate is %.1fx%.1f but card 0's is %.1fx%.1f" % [
					i, plate_wh[i].x, plate_wh[i].y, plate_wh[0].x, plate_wh[0].y])
		if best_fs[0] <= score_fs[0]:
			_fail("\"BEST\" is %dpx against the score's %d — CARD_BEST_LABEL_SCALE is doing nothing" % [
				best_fs[0], score_fs[0]])
	# 뒤 검사들이 실제 기록을 보지 않도록 되돌린다.
	screen.call("set_best_scores", PackedInt32Array([0, 0, 0, 0]))
	await process_frame

	var view := Vector2(base.x, base.x * 20.0 / 9.0)
	var modes: Array = screen.get("CARD_MODES")
	var hidden: int = screen.get("MODE_HIDDEN")
	var hidden_card: int = modes.find(hidden)
	var required: int = screen.get("hidden_modes_required")
	var gates: int = screen.get("hidden_gates_needed")
	if hidden_card < 0:
		_fail("no card maps to MODE_HIDDEN")

	# ---- 잠긴 히든 카드의 덮개 ----
	#
	# 덮개는 카드를 통째로 가리므로 "무엇을 가리는가"는 볼 것이 없다. 대신
	# 안에 든 세 조각(자물쇠·LOCKED·안내판)이 카드 밖으로 새지 않는지, 서로
	# 겹치지 않는지, 그리고 읽을 수 있는 크기인지를 본다 — 셋을 한 덩어리로
	# 세로 가운데에 놓는 계산이라, 카드 높이가 비율마다 다른 이 화면에서는
	# 한 비율만 재면 다른 비율에서 넘치는 것을 못 본다.
	#
	# 그리고 잠겼을 때만 떠야 한다. 늘 떠 있으면 해금해도 잠긴 것처럼 보이는데,
	# 스크린샷으로는 "덮개가 있다"로 똑같이 보인다.
	print("")
	var lock_tex: Texture2D = screen.get("_lock_texture")
	if lock_tex == null:
		_fail("lock art did not load — is %s missing?" % screen.get("CARD_LOCK_FILE"))
	if hidden_card >= 0 and lock_tex != null:
		for h2 in [base.y, base.x * 20.0 / 9.0]:
			screen.size = Vector2(base.x, h2)
			screen.call("_layout")
			for pick in [0, hidden_card]:
				screen.call("set_hidden_progress", 0, required, gates)
				screen.call("_select", pick, false)
				await process_frame
				var lock_card: Rect2 = screen.call("_lock_draw_rect")
				if lock_card.size.x <= 0.0:
					_fail("잠긴 상태인데 덮개가 안 나온다")
					continue
				var parts: Dictionary = screen.call("_lock_layout", hidden_card, lock_card)
				var icon: Rect2 = parts["icon"]
				var title: Rect2 = parts["title"]
				var hint: Rect2 = parts["hint"]
				var probs := []
				# 카드 안에 있는 것만으로는 부족하다 — 이름판과 점수판 사이에
				# 들어가야 한다. 카드 한가운데에 놓았을 때 안내판이 BEST 판에
				# 맞닿았고, 덮개 때문에 "가린다"로는 안 잡혔다.
				var np: Rect2 = screen.call("_drawn_rect", names[hidden_card])
				var bp: Rect2 = screen.call("_drawn_rect", screen.get("_card_best_plate")[hidden_card])
				for entry in [["icon", icon], ["LOCKED", title], ["hint box", hint]]:
					if not lock_card.encloses(entry[1]):
						probs.append("%s spills outside the card" % entry[0])
					if entry[1].intersects(np):
						probs.append("%s touches the name plate" % entry[0])
					if entry[1].intersects(bp):
						probs.append("%s touches the BEST plate" % entry[0])
				if icon.intersects(title):
					probs.append("the icon runs into LOCKED")
				if title.intersects(hint):
					probs.append("LOCKED runs into the hint box")
				if title.position.y < icon.end.y:
					probs.append("LOCKED is not below the icon")
				if hint.position.y < title.end.y:
					probs.append("the hint box is not below LOCKED")
				# 읽을 수 있는 크기인가. 0 에 가까우면 위의 검사가 전부 저절로
				# 통과하므로 이 검사가 아무것도 안 지키게 된다.
				if icon.size.y < lock_card.size.y * 0.12:
					probs.append("the icon is under 12%% of the card tall")
				if int(parts["title_size"]) < 8:
					probs.append("LOCKED is under 8px")
				if int(parts["hint_size"]) < 7:
					probs.append("the hint is under 7px")
				# 안내 글자가 자기 판을 넘지 않는가.
				var hf: Font = parts["hint_font"]
				var text_w: float = hf.get_string_size(
					screen.get("CARD_LOCK_HINT"), HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(parts["hint_size"])).x
				if text_w > hint.size.x + 0.5:
					probs.append("\"%s\" is %.0fpx but its plate is %.0f" % [
						screen.get("CARD_LOCK_HINT"), text_w, hint.size.x])
				if pick == hidden_card:
					var check2: Rect2 = screen.call("_check_rect", hidden_card,
						screen.call("_selected_card_rect"))
					if check2.intersects(icon) or check2.intersects(title) or check2.intersects(hint):
						probs.append("the selection check lands on the lock panel")
				if not probs.is_empty():
					_fail("%.0fx%.0f lock panel (%s): %s" % [
						base.x, h2, "selected" if pick == hidden_card else "unselected",
						", ".join(probs)])
				print("  %.0fx%.0f lock %-10s icon %.0fx%.0f  LOCKED %dpx  hint %.0fx%.0f @%dpx  %s" % [
					base.x, h2, "selected" if pick == hidden_card else "unselected",
					icon.size.x, icon.size.y, int(parts["title_size"]),
					hint.size.x, hint.size.y, int(parts["hint_size"]),
					"ok" if probs.is_empty() else "FAIL"])

		# 덮개가 흰 테두리 안쪽에서 딱 멈추는가.
		#
		# 두 방향 모두 틀릴 수 있다. 덜 들어가면 흰 띠가 반쯤 어두워져 어중간한
		# 링이 남고(254 -> 117), 너무 들어가면 카드 속의 밝은 띠가 덮이지 않고
		# 남는다.
		#
		# 예전에는 기준값을 카드 아트에서 직접 쟀다. 이제 판을 그리므로 테두리
		# 두께는 CARD_BORDER_NATIVE 하나에서 나오고 그리는 쪽과 덮개가 같은 값을
		# 쓰므로, 두께 자체는 어긋날 수 없다. 남은 위험은 배율과 반올림이다.
		screen.size = view
		screen.call("_layout")
		await process_frame
		# 고른 카드는 105%% 로 그려지고 흰 띠도 같이 커진다. 배율을 빼먹으면
		# 기준값이 실제보다 작게 나와 검사가 헐거워진다.
		var native_w: float = float(screen.get("SELECT_SHEET_WIDTH_NATIVE"))
		var art_scale: float = cards[hidden_card].size.x * cards[hidden_card].scale.x / native_w
		var want_inset: float = float(screen.get("CARD_BORDER_NATIVE")) * art_scale
		var lock_card2: Rect2 = screen.call("_lock_draw_rect")
		var veil: Rect2 = screen.call("_lock_veil_rect", hidden_card, lock_card2)
		var got_inset: float = veil.position.x - lock_card2.position.x
		# 위아래 좌우가 같은 값이어야 한다 — 한쪽만 어긋나면 링이 한 변에만 남는다.
		for entry in [["top", veil.position.y - lock_card2.position.y],
				["right", lock_card2.end.x - veil.end.x],
				["bottom", lock_card2.end.y - veil.end.y]]:
			if absf(float(entry[1]) - got_inset) > 0.5:
				_fail("덮개가 왼쪽에서 %.1fpx, %s 에서 %.1fpx 들어와 있다" % [
					got_inset, entry[0], float(entry[1])])
		if got_inset < want_inset - 0.5:
			_fail("덮개가 %.1fpx 만 들어와 있는데 흰 띠는 %.1fpx 다 — 띠가 반쯤 어두워져 링이 남는다" % [
				got_inset, want_inset])
		elif got_inset > want_inset + 1.0:
			_fail("덮개가 %.1fpx 들어와 있어 흰 띠(%.1fpx)보다 더 물러섰다 — 카드 속이 덜 덮인다" % [
				got_inset, want_inset])
		else:
			print("  veil stops %.1fpx in, the drawn border is %.1fpx" % [got_inset, want_inset])

		# 해금하면 사라져야 한다. _draw_selection 은 _lock_draw_rect() 가 빈
		# 사각형인지만 보고 그리므로, 그 함수의 답이 곧 화면에 나오는 답이다.
		screen.size = view
		screen.call("_layout")
		for cleared2 in range(required + 1):
			screen.call("set_hidden_progress", cleared2, required, gates)
			screen.call("_select", 0, false)
			await process_frame
			var drawn: Rect2 = screen.call("_lock_draw_rect")
			var shows: bool = drawn.size.x > 0.0
			var want_shown: bool = cleared2 < required
			if shows != want_shown:
				_fail("%d/%d 에서 덮개가 %s — 기대 %s" % [
					cleared2, required,
					"보인다" if shows else "안 보인다",
					"보임" if want_shown else "안 보임"])
			else:
				print("  %d/%d -> 덮개 %s" % [
					cleared2, required, "보임" if shows else "없음 (해금)"])
		screen.call("set_hidden_progress", 0, required, gates)

	# ---- 카드의 "BEST" 가 게임 화면의 BEST 와 같은 얼굴인가 ----
	#
	# 같은 것을 가리키는 두 자리인데 서로 다른 파일에 색이 적혀 있다. 화면 쪽이
	# Main 을 참조할 수 없는 구조라 값이 두 벌 존재하고, 그러면 한쪽만 고치는
	# 날이 온다 — 두 화면을 나란히 놓고 보는 일이 없으니 그날 아무도 모른다.
	#
	# 상수만 비교하면 부족하다. 색을 맞춰 놓고 라벨에 안 걸어 두면 상수는
	# 통과하고 화면은 예전 색으로 남는다. 그래서 실제 라벨이 들고 있는 값을 본다.
	print("")
	var hud_fill: Color = main.get("BEST_LABEL_FILL")
	var hud_outline: Color = main.get("SCORE_TEXT_OUTLINE")
	var card_fill: Color = screen.get("CARD_BEST_COLOR")
	var card_outline: Color = screen.get("CARD_BEST_OUTLINE")
	if not card_fill.is_equal_approx(hud_fill):
		_fail("the card's BEST is %s but the HUD's is %s — CARD_BEST_COLOR and BEST_LABEL_FILL have drifted" % [
			card_fill, hud_fill])
	if not card_outline.is_equal_approx(hud_outline):
		_fail("the card's BEST outline is %s but the HUD's is %s — CARD_BEST_OUTLINE and SCORE_TEXT_OUTLINE have drifted" % [
			card_outline, hud_outline])
	var bests: Array = screen.get("_card_best")
	for i in range(bests.size()):
		var label: Label = bests[i]
		var got_fill: Color = label.get_theme_color("font_color")
		var got_outline: Color = label.get_theme_color("font_outline_color")
		var ring: int = label.get_theme_constant("outline_size")
		if not got_fill.is_equal_approx(hud_fill):
			_fail("card %d's BEST label draws %s, not the HUD's %s" % [i, got_fill, hud_fill])
		if not got_outline.is_equal_approx(hud_outline):
			_fail("card %d's BEST label outlines in %s, not the HUD's %s" % [i, got_outline, hud_outline])
		if ring < 1:
			_fail("card %d's BEST label has outline_size %d — the outline colour is set but nothing draws it" % [i, ring])
	print("  BEST label %s on %s outline, ring %dpx — same as the HUD" % [
		card_fill, card_outline, bests[0].get_theme_constant("outline_size")])

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
	if hidden_card >= 0:
		# 화면은 번역된 문구를 그린다. 원문 상수와 비교하면 한국어 기기에서만
		# 실패한다 — 로케일은 OS 에서 자동으로 잡히므로 개발 기기에 따라 결과가
		# 갈린다.
		var open_text: String = TranslationServer.translate(screen.get("CARD_EXPLAIN_HIDDEN_OPEN"))
		# 진행도를 실제로 넘겨 가며 본다. hidden_mode_open 을 직접 뒤집으면
		# 잠금만 바뀌고 진행도는 그대로라, 화면이 두 값을 함께 쓰는지 —
		# set_hidden_progress 가 둘을 같은 자리에서 정하는지 — 를 못 본다.
		for cleared in range(required + 1):
			screen.call("set_hidden_progress", cleared, required, gates)
			screen.call("_select", hidden_card, false)
			await process_frame
			var shown: String = screen.get("_explain_label").text
			var unlocked: bool = cleared >= required
			var want_text: String = open_text if unlocked \
				else screen.call("_hidden_locked_text", cleared)
			if shown != want_text:
				_fail("%d/%d cleared shows \"%s\", want \"%s\"" % [
					cleared, required, shown, want_text])
			if screen.get("hidden_mode_open") != unlocked:
				_fail("%d/%d cleared left hidden_mode_open = %s" % [
					cleared, required, screen.get("hidden_mode_open")])
			print("  %d/%d -> open=%-5s \"%s\"" % [
				cleared, required, screen.get("hidden_mode_open"), shown])
		# 잠금 문구와 해금 문구가 같으면 두 상태 중 하나는 안내가 없는 것이다.
		if screen.call("_hidden_locked_text", 0) == open_text:
			_fail("the locked and open blurbs are the same string — one of the two states is unlabelled")
		screen.call("set_hidden_progress", 0, required, gates)
		# 그리고 나갈 수 있는 문구가 전부 설명 바 안에 들어가야 한다. 글자
		# 크기는 _fit_explain_size 가 _explain_candidates() 를 훑어 한 번에
		# 정하므로, 거기서 빠진 문구는 크기 계산에 반영되지 않고 출시 때
		# 뒤집는 순간 잘린다.
		#
		# 그 목록을 여기서 다시 부르면 안 된다 — 처음에 그렇게 썼더니,
		# _explain_candidates() 에서 문구를 빼는 순간 피팅과 검사가 같이 눈을
		# 감아 통과했다. 검사할 문구는 상수에서 직접 모은다.
		var must_fit: Array = []
		for text in screen.get("CARD_EXPLAIN"):
			if str(text) != "":
				must_fit.append(TranslationServer.translate(text))
		must_fit.append(open_text)
		for cleared in range(required + 1):
			must_fit.append(screen.call("_hidden_locked_text", cleared))
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
