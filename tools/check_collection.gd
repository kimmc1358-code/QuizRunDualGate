extends SceneTree

# 도감이 모으는 대로 모이고, 저장되고, 화면에 그대로 나오는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_collection.gd
#
# 실제 Main.tscn 을 띄우고 그 함수를 부른다 — 게이트 판정이 부르는
# _collection_note, 문제를 뽑는 _pick_flag_target / _make_color_problem, 팝업의
# tap_at 까지 게임이 쓰는 것 그대로다.
#
#   1. 국기: 틀리면 "봤다"만, 맞히면 모이고 NEW 가 붙는다. 두 번 맞혀도 한 번.
#   2. 연산: 맞힌 것만 세고, 문턱을 넘는 순간에만 별이 는다.
#   3. 색깔: 이름 키("RED/BLUE")로 모인다.
#   4. 실제로 생긴 게이트가 도감에 필요한 것(math_kind, 색 인덱스)을 들고 있다.
#   5. 저장했다가 다시 불러오면 그대로다.
#   6. 못 모은 것이 더 자주 나온다 — 하나 남은 칸이 고르게 뽑을 때의 두 배 넘게.
#      이게 없으면 마지막 칸들이 안 나와 도감이 "안 채워지는 것"이 된다.
#   7. 게임오버 팝업의 NEW! 줄은 새 것이 있을 때만 나오고, 버튼과 겹치지 않는다.
#   8. 도감 팝업이 세 탭을 그리고, 칸을 누르면 그 칸의 것을 말한다.
#   9. 모드 선택의 도감 버튼이 리더보드 옆에 나란히 서고, 닫으면 점이 꺼진다.
#
# 저장 파일(user://savegame.cfg)을 건드리므로 처음에 떠 두고 끝에 되돌린다.

const SAVE_PATH := "user://savegame.cfg"
const SAMPLES := 6000

var _fail := 0
var _saved_bytes := PackedByteArray()
var _had_save := false


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok    " + msg)
	else:
		_fail += 1
		print("  FAIL  " + msg)


func _backup() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SAVE_PATH)


func _restore() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _clear(m: Node) -> void:
	m.collected_flags.clear()
	m.seen_flags.clear()
	m.collected_colors.clear()
	m.collection_unviewed.clear()
	m.math_solved.fill(0)
	m.run_new_flags = 0
	m.run_new_colors = 0
	m.run_new_stars = 0


func _run() -> void:
	_backup()
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	var QK = m.QuizKind
	print("check_collection")
	_clear(m)

	# ---- 1. 국기 ----
	var code: String = str(m.flag_records[0].code)
	var fg := {"quiz_kind": QK.FLAG, "target_code": code}
	m._collection_note(fg, false)
	_check(m.seen_flags.has(code) and not m.collected_flags.has(code),
		"a missed flag is remembered as seen, not collected")
	m._collection_note(fg, true)
	m._collection_note(fg, true)
	_check(m.collected_flags.has(code) and m.collection_unviewed.has("f:" + code)
		and m.run_new_flags == 1, "a passed flag is collected once, marked NEW, counted once")

	# ---- 2. 연산 ----
	var times: int = m.MathKind.TIMES_TABLE
	var mg := {"quiz_kind": QK.MATH, "math_kind": times}
	m._collection_note(mg, false)
	_check(m.math_solved[times] == 0, "a missed math gate counts nothing")
	var first: int = int(m.MATH_STAR_THRESHOLDS[0])
	for i in range(first - 1):
		m._collection_note(mg, true)
	_check(m.run_new_stars == 0 and not m.collection_unviewed.has("m:%d" % times),
		"no star one short of %d" % first)
	m._collection_note(mg, true)
	_check(m.math_solved[times] == first and m.run_new_stars == 1
		and m.collection_unviewed.has("m:%d" % times), "the %dth answer earns the first star" % first)

	# ---- 3. 색깔 ----
	var cg := {"quiz_kind": QK.STROOP, "ocean_word_index": 0, "ocean_answer_index": 1}
	m._collection_note(cg, true)
	var key: String = "%s/%s" % [m.OCEAN_COLOR_NAMES[0], m.OCEAN_COLOR_NAMES[1]]
	_check(m.collected_colors.has(key) and m.run_new_colors == 1, "a colour pair is collected as " + key)

	# ---- 4. 실제 게이트 ----
	var view := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var was_mode: int = m.current_mode
	m.current_mode = m.Mode.JUNGLE
	m.gates.clear()
	m._spawn_gate(view)
	var jg: Dictionary = m.gates[m.gates.size() - 1]
	_check(int(jg.get("math_kind", -1)) >= 0 and int(jg.math_kind) < m.MathKind.size(),
		"a spawned math gate carries its math_kind (%s)" % str(jg.get("math_kind")))
	m.current_mode = m.Mode.OCEAN
	m.gates.clear()
	m._spawn_gate(view)
	var og: Dictionary = m.gates[m.gates.size() - 1]
	_check(og.has("ocean_word_index") and og.has("ocean_answer_index"),
		"a spawned colour gate carries its word and ink")
	m.gates.clear()
	m.current_mode = was_mode

	# ---- 5. 저장 ----
	m.collection_dirty = true
	m._save_collection()
	var snapshot := [m.collected_flags.duplicate(), m.seen_flags.duplicate(),
		m.collected_colors.duplicate(), m.collection_unviewed.duplicate(), m.math_solved.duplicate()]
	_clear(m)
	m._load_collection()
	_check(m.collected_flags == snapshot[0] and m.seen_flags == snapshot[1]
		and m.collected_colors == snapshot[2] and m.collection_unviewed == snapshot[3]
		and m.math_solved == snapshot[4], "everything survives a save and reload")

	# ---- 6. 못 모은 것 쪽으로 ----
	# 국기: 1등급을 하나만 남기고 다 모은 뒤, 1등급에서 나온 것 중 그 하나의 몫.
	var tier1: Array = m.flag_records_by_tier.get(1, [])
	if tier1.size() >= 2:
		_clear(m)
		var left: String = str(tier1[0].code)
		for r in tier1:
			if str(r.code) != left:
				m.collected_flags[str(r.code)] = true
		var in_tier := 0
		var hits := 0
		for i in range(SAMPLES):
			var r: Dictionary = m._pick_flag_target(0)
			if int(r.get("recognition_tier", 0)) == 1:
				in_tier += 1
				if str(r.code) == left:
					hits += 1
		var share: float = float(hits) / float(maxi(1, in_tier))
		var uniform: float = 1.0 / float(tier1.size())
		_check(share > uniform * 2.0, "the last tier-1 flag comes up %.1f%% of tier-1 picks (uniform %.1f%%)" % [
			share * 100.0, uniform * 100.0])
	# 색깔: 첫 페이즈에서 실제로 나오는 조합 중 하나만 남긴다.
	_clear(m)
	var seen_pairs := {}
	for i in range(SAMPLES):
		var p: Dictionary = m._make_color_problem(0)
		seen_pairs[m._color_key(p.word, p.answer)] = true
	var pairs: Array = seen_pairs.keys()
	var left_pair: String = pairs[0]
	for k in pairs:
		if k != left_pair:
			m.collected_colors[k] = true
	var pair_hits := 0
	for i in range(SAMPLES):
		var p2: Dictionary = m._make_color_problem(0)
		if m._color_key(p2.word, p2.answer) == left_pair:
			pair_hits += 1
	var pair_share: float = float(pair_hits) / SAMPLES
	_check(pair_share > 2.0 / pairs.size(), "the last phase-1 colour pair comes up %.1f%% (uniform %.1f%%)" % [
		pair_share * 100.0, 100.0 / pairs.size()])

	# ---- 7. 게임오버 팝업 ----
	var go: Control = m.gameover_popup
	go.size = view
	go.set_collection_news(2, 1, 0)
	go.set_result(null, 100.0, 1200, 7, 5000, false, false, 1200)
	var box: Control = go.get("_collection_box")
	var play: Control = go.get("_play_button")
	_check(box.visible, "the NEW! line shows when something was collected")
	_check(box.position.y + box.size.y <= play.position.y + 0.5,
		"the NEW! line ends above PLAY AGAIN (%.0f vs %.0f)" % [box.position.y + box.size.y, play.position.y])
	var home: Control = go.get("_home_button")
	var panel: Rect2 = go.get("_panel_rect")
	_check(home.position.y + home.size.y <= panel.end.y + 0.5, "HOME still ends inside the panel")
	go.set_collection_news(0, 0, 0)
	go.set_result(null, 100.0, 1200, 7, 5000, false, false, 1200)
	_check(not box.visible, "no NEW! line when nothing was collected")
	go.visible = false

	# ---- 8. 도감 팝업 ----
	_clear(m)
	m._collection_note({"quiz_kind": QK.FLAG, "target_code": code}, true)
	var seen_code: String = str(m.flag_records[1].code)
	m._collection_note({"quiz_kind": QK.FLAG, "target_code": seen_code}, false)
	m._collection_note(cg, true)
	var cp: Control = m.collection_popup
	# 크기를 여기서 넣어 주지 않는다 — 코드로 만든 팝업이 화면을 덮는지가 바로
	# 볼 것이다. 넣어 주면 크기 0 으로 시작하는 결함을 가려 버린다(실제로 가렸다).
	var screen: Vector2 = root.get_visible_rect().size
	_check(cp.size.distance_to(screen) < 1.0, "the collection popup covers the screen (%s vs %s)" % [cp.size, screen])
	m._open_collection()
	await process_frame
	var sheet: Control = cp.get("_sheet")
	for tab in [0, 1, 2]:
		cp._select_tab(tab)
		await process_frame
		_check(sheet.custom_minimum_size.y > 50.0, "tab %d has content (%.0fpx)" % [tab, sheet.custom_minimum_size.y])
	_check(cp.tab_progress(0) == Vector2i(1, m.flag_records.size()), "flag tab counts 1 / %d" % m.flag_records.size())
	_check(cp.tab_progress(2) == Vector2i(1, 110), "colour tab counts 1 / 110")
	cp._select_tab(0)
	await process_frame
	var flag_cells: Array = cp._flag_layout(sheet.size.x).cells
	for cell in flag_cells:
		var c: String = str(cell.record.code)
		if c == code:
			cp.tap_at(cell.rect.get_center())
			_check(cp.info_text() == TranslationServer.translate(str(cell.record.name)),
				"tapping a collected flag names it (%s)" % cp.info_text())
		elif c == seen_code:
			cp.tap_at(cell.rect.get_center())
			_check(cp.info_text() == TranslationServer.translate(cp.INFO_SEEN), "tapping a seen flag says so")
	_check(flag_cells.size() == m.flag_records.size(), "every flag has a cell (%d)" % flag_cells.size())
	cp._select_tab(2)
	await process_frame
	var color_cells: Array = cp._color_layout(sheet.size.x).cells
	_check(color_cells.size() == 110, "every colour pair has a cell (%d)" % color_cells.size())
	for cell in color_cells:
		if cell.word == 0 and cell.ink == 1:
			cp.tap_at(cell.rect.get_center())
			_check(cp.info_text().contains(TranslationServer.translate(m.OCEAN_COLOR_NAMES[0])),
				"tapping a collected colour pair describes it (%s)" % cp.info_text())
	# 칸이 스크롤 폭 안에 들어가는가.
	var widest := 0.0
	for cell in flag_cells + color_cells:
		widest = maxf(widest, cell.rect.end.x)
	_check(widest <= sheet.size.x + 0.5, "cells fit the sheet width (%.0f / %.0f)" % [widest, sheet.size.x])

	# ---- 9. 모드 선택의 버튼 ----
	var ms: Control = m.mode_select_panel
	ms.size = view
	ms.call("_layout")
	var lb: Control = ms.get("_leaderboard")
	var col: Control = ms.get("_collection")
	_check(col != null and absf(col.position.y - lb.position.y) < 0.5 and absf(col.size.y - lb.size.y) < 0.5,
		"the collection plate shares the leaderboard's row")
	_check(col != null and lb.position.x + lb.size.x <= col.position.x + 0.5,
		"the two plates do not overlap sideways")
	_check(col != null and col.position.x + col.size.x <= view.x + 0.5, "the collection plate stays on screen")
	m._push_collection_badge()
	_check(ms.get("_collection_dot").visible, "the badge dot is on while something is unviewed")
	m._on_collection_closed()
	_check(not ms.get("_collection_dot").visible and m.collection_unviewed.is_empty(),
		"closing the collection clears NEW and the dot")

	_restore()
	print("check_collection: %s" % ("OK" if _fail == 0 else "%d failure(s)" % _fail))
	quit(0 if _fail == 0 else 1)
