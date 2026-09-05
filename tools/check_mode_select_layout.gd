extends SceneTree

# 모드 선택 화면의 세로 흐름이 어떤 화면 비율에서도 겹치지 않는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_mode_select_layout.gd
#
# 이 화면은 남는 세로를 블록 사이로 나눠 갖는 구조라, 화면이 짧아지면 간격이
# 0 으로 눌리고 그 다음부터는 블록끼리 파고든다. 그 지점이 어디인지는 아트
# 비율(제목, 카드, 설명 바, START)의 곱으로 정해지므로 손으로 계산할 수 없고,
# 개발 화면에서는 비율 하나만 보이니 눈으로도 안 잡힌다 — 실제로 4:3 에서
# START 가 하단 카드의 점수를 덮고 있는 것을 스크린샷을 찍고서야 알았다.
#
# 겹침 검사와 함께 두 가지를 더 본다:
#
#   1. 설명 바는 카드에 붙어 있어야 한다. 카드끼리의 세로 간격과 같아야지,
#      따로 떠 있으면 넷과 한 덩어리로 읽히지 않는다. 예전에 후광용으로 두던
#      여백이 후광이 사라진 뒤로도 남아 20:9 에서 4 배로 벌어져 있었다.
#   2. 아무것도 화면 밖으로 나가지 않아야 한다.

const RATIOS := [
	["4:3 tablet", 4.0 / 3.0], ["16:10", 1.6], ["16:9", 16.0 / 9.0],
	["18:9", 2.0], ["19.5:9", 19.5 / 9.0], ["20:9", 20.0 / 9.0], ["21:9", 21.0 / 9.0],
]
# 붙었다고 볼 오차. 간격은 화면 폭 비율에서 나오므로 반올림 몇 px 은 늘 생긴다.
const BOARD_GAP_EPS := 1.5

var fails := 0


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


func _rect(c: Control) -> Rect2:
	return Rect2(c.position, c.size)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame
	var s = main.get("mode_select_panel")
	if s == null:
		print("  FAIL: no mode_select_panel")
		quit(1)
		return

	# 기준 해상도. 스트레치가 expand 라 이 크기는 양축 모두 최소값이다 — 화면이
	# 기준보다 길면 세로가 늘고, 기준보다 넓으면 가로가 는다. 어느 쪽도 줄지는
	# 않는다.
	#
	# 그래서 4:3 기기의 뷰포트는 480x640 이 아니라 640x854 다. 처음에 폭을
	# 480 으로 고정하고 세로만 바꿔 훑었더니 존재할 수 없는 화면을 검사하며
	# 4:3 과 16:10 에서 겹친다고 실패했다.
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var base_ratio: float = base.y / base.x
	print("check_mode_select_layout: base %.0fx%.0f, %d ratios" % [base.x, base.y, RATIOS.size()])
	print("")
	print("  %-12s %11s %9s %10s %8s" % ["ratio", "viewport", "card gap", "card->bar", "verdict"])

	for row in RATIOS:
		var ratio: float = float(row[1])
		var view: Vector2 = Vector2(base.x, base.x * ratio) if ratio >= base_ratio \
			else Vector2(base.y / ratio, base.y)
		var w: float = view.x
		var h: float = view.y
		s.size = view
		s.call("_layout")
		await process_frame

		var cards: Array = s.get("_cards")
		# 세로로 이어지는 블록들. 이름은 실패 메시지에 그대로 나간다.
		var blocks := [
			["title", s.get("_title")],
			["cards top row", cards[0]],
			["cards bottom row", cards[2]],
			["explain bar", s.get("_explain")],
			["leaderboard", s.get("_leaderboard")],
			["START", s.get("_start")],
			["remove ads", s.get("_remove_ads")],
		]
		var problems: Array = []

		# 위에서 아래로 순서대로 겹치지 않는가. 위 블록의 아래끝이 다음 블록의
		# 위끝을 넘으면 겹친 것이다.
		for i in range(blocks.size() - 1):
			var a: Control = blocks[i][1]
			var b: Control = blocks[i + 1][1]
			if a == null or b == null:
				continue
			var overlap: float = (a.position.y + a.size.y) - b.position.y
			if overlap > 0.5:
				problems.append("%s overruns %s by %.0fpx" % [blocks[i][0], blocks[i + 1][0], overlap])

		# 화면 밖으로 나가지 않는가.
		for entry in blocks:
			var c: Control = entry[1]
			if c == null:
				continue
			var r: Rect2 = _rect(c)
			if r.position.y < -0.5 or r.end.y > h + 0.5:
				problems.append("%s runs %.0f..%.0f outside 0..%.0f" % [entry[0], r.position.y, r.end.y, h])

		# 설명 바가 카드에 붙어 있는가 — 카드끼리의 세로 간격과 같아야 한다.
		var card_gap: float = cards[2].position.y - (cards[0].position.y + cards[0].size.y)
		var bar_gap: float = s.get("_explain").position.y - (cards[2].position.y + cards[2].size.y)
		if absf(bar_gap - card_gap) > BOARD_GAP_EPS:
			problems.append("explain bar sits %.0fpx under the cards but the cards are %.0fpx apart" % [
				bar_gap, card_gap])

		if not problems.is_empty():
			for p in problems:
				_fail("%s: %s" % [row[0], p])
		print("  %-12s %11s %9.1f %10.1f %8s" % [
			row[0], "%.0fx%.0f" % [w, h], card_gap, bar_gap, "ok" if problems.is_empty() else "FAIL"])

	# 그리고 화면이 길수록 위쪽 덩어리가 따라 내려와야 한다. 남는 세로가 전부
	# 리더보드 둘레로만 가면 제목과 카드는 위에 붙은 채 가운데만 휑해진다 —
	# 겹침 검사로는 전혀 안 잡히는 종류의 어긋남이다.
	print("")
	var tops: Array[float] = []
	for row in [["16:9", 16.0 / 9.0], ["21:9", 21.0 / 9.0]]:
		s.size = Vector2(base.x, base.x * float(row[1]))
		s.call("_layout")
		await process_frame
		tops.append(s.get("_title").position.y)
	if tops[1] <= tops[0] + 1.0:
		_fail("the title sits at %.0f on 16:9 and %.0f on 21:9 — the top block is not taking a share of the extra height" % [
			tops[0], tops[1]])
	else:
		print("  title drops %.0f -> %.0f px from 16:9 to 21:9" % [tops[0], tops[1]])

	# 기본 상태로 되돌려 둔다.
	s.size = Vector2(base.x, base.x * 20.0 / 9.0)
	s.call("_layout")

	print("")
	if fails == 0:
		print("check_mode_select_layout: OK")
	else:
		print("check_mode_select_layout: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
