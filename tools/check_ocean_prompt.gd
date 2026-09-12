extends SceneTree

# OCEAN(스트룹) 문제 상자의 질문 글자가 읽히는 크기인지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ocean_prompt.gd
#
# 상자는 [질문][색 단어] 한 줄이고, 질문은 단어 크기의 OCEAN_PROMPT_SIZE_RATIO
# 배로 정해진다. 그 비율이 0.46 이던 때 한국어 "이 글자는 무슨 색?" 은 13px 로
# 나와 읽기 어렵다는 말을 들었는데, 폭이 모자라서가 아니었다 — 줄은 상자의
# 71%(영어) / 42%(한국어)만 쓰고 있었다. 비율 하나가 만든 크기다.
#
# 모든 색 단어 x 두 언어 x 두 화면 비율에서 본다:
#   - 줄이 상자의 쓸 수 있는 폭 안에 들어가는가
#   - 질문이 OCEAN_PROMPT_READABLE_PX 이상인가
#   - 단어가 제 크기 그대로인가 — 질문은 빈 자리를 차지해야지 단어 자리를
#     빼앗으면 안 된다. 비율을 너무 올리면 줄은 넘치지 않는다: 배치가 둘을
#     같이 줄여 맞추기 때문이다. 그래서 "넘치는가"만 보면 0.90 같은 값이 거저
#     통과하고, 망가지는 것은 매 게이트 다시 읽어야 하는 단어 쪽이다.
#   - 단어가 질문보다 큰가
#
# 숫자는 화면이 그리는 바로 그 함수(_ocean_quiz_layout)에서 받는다.

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

	var names: Array = main.get("OCEAN_COLOR_NAMES")
	var readable: int = int(main.get("OCEAN_PROMPT_READABLE_PX"))
	var max_frac: float = float(main.get("QUIZ_TEXT_MAX_FONT_FRAC"))
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var was_locale: String = TranslationServer.get_locale()

	for h in [base_h, width * 20.0 / 9.0]:
		var rect: Rect2 = main.call("_quiz_box_rect", Vector2(width, h))
		# The size the word starts at before the row has to shrink anything.
		var full_word: int = int(round(rect.size.x * max_frac))
		for loc in ["en", "ko"]:
			TranslationServer.set_locale(loc)
			var min_prompt := 9999
			var min_word := 9999
			var worst_fill := 0.0
			var worst_word := ""
			for n in names:
				var word: String = TranslationServer.translate(str(n))
				var lay: Dictionary = main.call("_ocean_quiz_layout", rect, word)
				var area: float = float(lay.area_right) - float(lay.area_left)
				var row: float = float(lay.prompt_width) + float(lay.gap) + float(lay.word_width)
				if row > area + 0.5:
					_fail_msg("%s %.0f: \"%s\" row is %.1fpx in a %.1fpx writing area" % [loc, h, word, row, area])
				if int(lay.prompt_size) < readable:
					_fail_msg("%s %.0f: with \"%s\" the question is %dpx, under the readable %dpx" % [
						loc, h, word, int(lay.prompt_size), readable])
				if int(lay.word_size) < full_word:
					_fail_msg("%s %.0f: \"%s\" shrank to %dpx from %dpx to make room for the question" % [
						loc, h, word, int(lay.word_size), full_word])
				if int(lay.word_size) <= int(lay.prompt_size):
					_fail_msg("%s %.0f: \"%s\" is %dpx, no bigger than the question's %dpx" % [
						loc, h, word, int(lay.word_size), int(lay.prompt_size)])
				min_prompt = mini(min_prompt, int(lay.prompt_size))
				min_word = mini(min_word, int(lay.word_size))
				if row / area > worst_fill:
					worst_fill = row / area
					worst_word = word
			print("  %s  480x%.0f  question >= %dpx, word >= %dpx (full %dpx), fullest row %.0f%% (\"%s\")" % [
				loc, h, min_prompt, min_word, full_word, worst_fill * 100.0, worst_word])
	TranslationServer.set_locale(was_locale)

	if _fail == 0:
		print("check_ocean_prompt: ok")
		quit(0)
	else:
		print("check_ocean_prompt: %d failure(s)" % _fail)
		quit(1)
