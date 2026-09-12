extends SceneTree

# 게임오버의 SHARE 가 만드는 점수 카드와 문구를 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_share.gd
#
# 헤드리스는 카드를 그리지 못한다(더미 렌더러는 빈 그림을 준다). 그래서 그림
# 대신 ShareCard.card_layout 이 내는 자리를 잰다 — 그리는 쪽이 쓰는 바로 그
# 숫자다. 두 언어 x 네 모드 x 점수 0 ~ int 끝 x 신기록 여부마다:
#   - 로고, 모드 이름판, 캐릭터, SCORE/NEW BEST!, 점수, 맺음말이 흰 테두리
#     안쪽에 있는가
#   - 위에서부터 쌓인 순서대로 서로 겹치지 않는가
#   - 글자가 CONTENT_WIDTH 를 넘지 않는가. 점수는 넘치면 줄어드는데, 줄다가
#     SCORE_MIN_SIZE 에서 멈추므로 "줄였으니 들어갔겠지"는 성립하지 않는다
#   - 로고와 캐릭터가 실제로 실렸는가(크기 0 이면 위 검사는 저절로 통과한다)
# 그리고 공유 문구에 콤마 찍힌 점수, 번역된 모드 이름, 스토어 주소가 들어가는지,
# {score}/{mode} 가 채워지지 않고 남지 않았는지. 마지막으로 PC 에서 SHARE 를
# 누르면 공유 창 없이 조용히 끝나고, 다음 누름을 막는 깃발이 풀리는지.

const SCORES := [0, 7, 1250, 123456, 99999999, 2147483647]
const EPS := 0.5

var _fail := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail_msg(msg: String) -> void:
	_fail += 1
	print("  FAIL  %s" % msg)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var card = main.get("share_card")
	if card == null or not card.is_inside_tree():
		_fail_msg("Main has no ShareCard in the tree — SHARE has nothing to draw with")
		quit(1)
		return

	var logo: Texture2D = card.logo_texture()
	if logo == null:
		_fail_msg("the title logo did not load")
	var faces := []
	var dirs: Array = main.get("MODE_CHARACTER_DIR")
	var happy: Array = main.get("MODE_CHARACTER_HAPPY_FILE")
	for m in range(dirs.size()):
		faces.append(load(str(dirs[m]) + str(happy[m])))

	var content_w: float = float(card.get("CONTENT_WIDTH"))
	var min_size: int = int(card.get("SCORE_MIN_SIZE"))
	var names: Array = load("res://scripts/ModeSelectScreen.gd").get("CARD_NAMES")
	var store_url: String = ExternalLinks.STORE_URL
	var was_locale: String = TranslationServer.get_locale()
	var english_text := ""

	for loc in ["en", "ko"]:
		TranslationServer.set_locale(loc)
		var smallest_score := 9999
		var tightest := 9999.0
		for mode in range(faces.size()):
			for s in SCORES:
				for rec in [false, true]:
					var lay: Dictionary = card.card_layout(mode, s, rec, logo, faces[mode])
					var where := "%s mode %d score %d%s" % [loc, mode, s, " NEW" if rec else ""]
					var inner: Rect2 = lay.frame_inner
					var stack := [["logo", lay.logo], ["mode plate", lay.pill],
						["character", lay.character], ["label", lay.label],
						["score", lay.score], ["footer", lay.footer]]
					for part in stack:
						if not inner.grow(EPS).encloses(part[1]):
							_fail_msg("%s: %s %s leaves the frame %s" % [where, part[0], part[1], inner])
					for i in range(stack.size() - 1):
						var gap: float = stack[i + 1][1].position.y - stack[i][1].end.y
						tightest = minf(tightest, gap)
						if gap < -EPS:
							_fail_msg("%s: %s runs %.0fpx into %s" % [where, stack[i][0], -gap, stack[i + 1][0]])
					for part in [["logo", lay.logo], ["character", lay.character]]:
						if part[1].size.x < 1.0 or part[1].size.y < 1.0:
							_fail_msg("%s: the %s has no size — art missing?" % [where, part[0]])
					for part in [["score", lay.score_width], ["label", lay.label_width],
							["footer", lay.footer_width], ["mode plate", lay.pill.size.x]]:
						if float(part[1]) > content_w + EPS:
							_fail_msg("%s: the %s is %.0fpx, wider than %.0f" % [where, part[0], part[1], content_w])
					if int(lay.score_size) < min_size:
						_fail_msg("%s: score at %dpx, under %d" % [where, int(lay.score_size), min_size])
					if str(lay.digits) != ScoreFormat.grouped(s):
						_fail_msg("%s: card says %s" % [where, lay.digits])
					var want_label := TranslationServer.translate("NEW BEST!" if rec else "SCORE")
					if str(lay.label_text) != want_label:
						_fail_msg("%s: label reads \"%s\", want \"%s\"" % [where, lay.label_text, want_label])
					smallest_score = mini(smallest_score, int(lay.score_size))

				var text: String = card.share_text(mode, s)
				var mode_name := TranslationServer.translate(str(names[mode]))
				var tw := "%s mode %d score %d text" % [loc, mode, s]
				if not text.contains(ScoreFormat.grouped(s)):
					_fail_msg("%s lacks the score: %s" % [tw, text])
				if not text.contains(mode_name):
					_fail_msg("%s lacks \"%s\": %s" % [tw, mode_name, text])
				if not text.contains(store_url):
					_fail_msg("%s lacks the store link" % tw)
				if text.contains("{") or text.contains("}"):
					_fail_msg("%s left a placeholder: %s" % [tw, text])
				if loc == "en" and mode == 0 and s == 1250:
					english_text = text
				if loc == "ko" and mode == 0 and s == 1250 and text == english_text:
					_fail_msg("the Korean share text is the English one — no translation reached it")
		print("  %s  score font >= %dpx, tightest gap %.0fpx" % [loc, smallest_score, tightest])
	TranslationServer.set_locale(was_locale)
	print("  %s" % card.share_text(0, 1250).replace("\n", "  |  "))

	# PC: 공유 창은 없고, 누름이 멈춘 채 남지 않아야 한다.
	if ShareSheet.available():
		_fail_msg("ShareSheet says a share sheet exists on this PC")
	if ShareSheet.share_image("C:/nowhere.png", "x", "y"):
		_fail_msg("ShareSheet.share_image claimed success without Android")
	main.set("score", 1250)
	await main.call("_on_gameover_share_pressed")
	if main.get("share_busy"):
		_fail_msg("share_busy is still set after a press — the next SHARE would be ignored")
	else:
		print("  PC press: no share sheet, button free again")

	if _fail == 0:
		print("check_share: ok")
		quit(0)
	else:
		print("check_share: %d failure(s)" % _fail)
		quit(1)
