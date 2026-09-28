extends PopupBase

## 도감. 모드 선택 화면의 COLLECTION 버튼에서 연다.
##
## 탭 셋 — 국기 / 연산 / 색깔. 무엇을 모았는지는 Main 이 들고 있고
## (SAVE_SECTION_COLLECTION 블록), 여기서는 set_data 로 받은 것을 그리기만 한다.
##
## 각 탭은 칸이 많아(국기 193, 색 110) 노드를 칸마다 만들지 않는다. 스크롤 안에
## Control 하나(_sheet)를 두고 그 draw 에서 전부 그린다 — 게임 화면과 같은
## 방식이다. 탭 칸은 같은 치수 함수(_flag_cells, _color_cells)로 그리고 누른
## 자리를 찾으므로 둘이 어긋날 수 없다.

signal close_pressed

enum Tab { FLAGS, MATH, COLORS }
const TAB_LABELS := ["FLAGS", "MATH", "COLORS"]

const TITLE := "COLLECTION"
const TITLE_FRAC := 0.075             # 판 너비 대비
# 제목과 탭 사이. 붙여 두면 제목이 탭 줄의 머리글처럼 눌려 보였다.
const TITLE_GAP_FRAC := 0.045         # 판 너비 대비
const TAB_HEIGHT_FRAC := 0.075        # 판 높이 대비
const TAB_GAP := 6.0
const TAB_TEXT_FRAC := 0.42           # 탭 높이 대비
const TAB_ON := Color(1.0, 0.78, 0.22, 1.0)       # 판 골드와 같은 계열
const TAB_OFF := Color(0.93, 0.90, 0.82, 1.0)     # 크림
const TAB_ON_TEXT := Color(1.0, 1.0, 1.0, 1.0)
const TAB_TEXT_OUTLINE_FRAC := 0.18

# 탭 아래 "모은 수 / 전체" 와 막대.
const SUMMARY_FRAC := 0.050           # 판 너비 대비 글자
const SUMMARY_BAR_H := 10.0
const BAR_TRACK := Color(0.84, 0.80, 0.70, 1.0)   # 슬라이더의 빈 구간과 같다
const BAR_FILL := Color(1.0, 0.78, 0.22, 1.0)

# 맨 아래 한 줄 — 칸을 누르면 그것이 무엇인지 여기에 나온다.
const INFO_FRAC := 0.046
const INFO_COLOR := Color(0.40, 0.42, 0.48, 1.0)
const HINT_FLAGS := "Tap a flag to see its name"
const HINT_COLORS := "Tap a card to see it"
const HINT_MATH := "Stars at 10, 50 and 200 correct"
const INFO_UNSEEN := "Not discovered yet"
const INFO_SEEN := "Seen it, missed it. Catch it next time!"
const INFO_COLOR_FORMAT := "'%s' written in %s"

# ---- 국기 ----
# 등급별로 나눠 놓는다. 쉬운 나라만 채워진 도감과 어려운 나라까지 채운 도감이
# 한눈에 달라 보여야 한다 — 뒤쪽 칸은 오래 버텨야만 나온다.
const TIER_LABELS := ["EASY", "NORMAL", "HARD", "EXPERT"]
const FLAG_COLUMNS := 5
const FLAG_ASPECT := 171.0 / 256.0    # assets/flags/256x171
const CELL_GAP := 6.0
const CELL_RADIUS := 5
const SECTION_FRAC := 0.050           # 판 너비 대비, 등급/색 이름 머리글
const SECTION_H_FRAC := 1.9           # 머리글 글자 크기 대비 줄 높이
const SECTION_GAP := 10.0             # 섹션 사이
const UNKNOWN_FILL := Color(0.82, 0.80, 0.75, 1.0)
const UNKNOWN_MARK := Color(0.055, 0.180, 0.435, 0.45)
# 봤지만 못 맞힌 국기. 그림을 흐리게 깔아 "저건 봤다"가 읽히게 한다.
const SEEN_TINT := Color(1.0, 1.0, 1.0, 0.30)
const SEEN_BACK := Color(0.70, 0.70, 0.72, 1.0)
const FLAG_EDGE := Color(0.055, 0.180, 0.435, 0.35)
const NEW_DOT := Color(0.93, 0.20, 0.20, 1.0)
const NEW_DOT_RING := Color(1.0, 1.0, 1.0, 1.0)
const NEW_DOT_R := 5.0

# ---- 연산 ----
# MathKind 순서 그대로. Main 의 enum 을 바꾸면 여기도 같이 바꾼다 — 줄 수가
# 다르면 _layout_content 가 알린다.
# 기호 대신 말로 — "−"(U+2212)가 두 폰트에 다 있는지 확인하지 않았다. "×" 는
# 게임 문제가 이미 쓰고 있어 확인된 글리프다(_make_times_table).
const MATH_LABELS := [
	"1-digit add & subtract",
	"2-digit add & subtract",
	"Times tables",
	"2-digit with carrying",
	"2-digit × 1-digit",
	"Missing number",
]
const MATH_ROW_FRAC := 0.155          # 판 너비 대비 한 줄 높이
const MATH_LABEL_FRAC := 0.050
const MATH_COUNT_FRAC := 0.040
const MATH_BAR_H := 12.0
const STAR_ON := Color(1.0, 0.76, 0.10, 1.0)
const STAR_OFF := Color(0.80, 0.76, 0.66, 1.0)
const STAR_EDGE := Color(0.55, 0.38, 0.05, 1.0)
const MAX_TEXT := "MAX"

# ---- 색깔 ----
const COLOR_COLUMNS := 5
const COLOR_CELL_ASPECT := 0.62       # 높이 / 폭
# 판의 크림과 같으면 모은 칸이 판에 녹아 빈자리처럼 보인다 — 더 흰 바탕에 테두리.
const COLOR_CELL_FILL := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_CELL_EDGE := Color(0.80, 0.75, 0.63, 1.0)  # 점선 구분선의 진한 크림
const COLOR_WORD_FRAC := 0.50         # 칸 높이 대비
const COLOR_OUTLINE := Color(0.09, 0.12, 0.18, 0.95)   # 게임의 OCEAN_INK_OUTLINE_COLOR
const COLOR_OUTLINE_FRAC := 0.16

const TAP_SLOP := 12.0                # 이보다 많이 움직이면 누름이 아니라 스크롤

var _tab: int = Tab.FLAGS
var _cancel: Button
var _title: Control
var _tabs: Array[Control] = []
var _summary: Control
var _scroll: ScrollContainer
var _sheet: Control
var _info: Control
var _info_text := ""
var _press_pos := Vector2.ZERO
var _pressing := false

# set_data 로 받는 것. 비어 있으면 빈 도감으로 그린다.
var _data: Dictionary = {}
# 등급별로 나누고 이름순으로 줄 세운 국기 기록 — [[tier1 records], ...].
var _flags_by_tier: Array = []


func panel_size_frac() -> Vector2:
	return Vector2(0.92, 0.88)


func panel_texture_width() -> int:
	return 450


func panel_center_y_frac() -> float:
	return 0.51


## Main 이 열기 직전에 넘긴다. 참조를 그대로 들고 있으므로 열려 있는 동안
## Main 쪽이 바뀌면 다음 그리기에 반영된다(바뀔 일은 없지만).
func set_data(data: Dictionary) -> void:
	_data = data
	_flags_by_tier = []
	for t in range(TIER_LABELS.size()):
		_flags_by_tier.append([])
	for record in data.get("flag_records", []):
		var tier: int = clampi(int(record.get("recognition_tier", 1)), 1, TIER_LABELS.size())
		_flags_by_tier[tier - 1].append(record)
	# 이름순 — 찾는 사람에게는 코드순보다 낫다. 언어가 바뀌면 다시 연다.
	for list in _flags_by_tier:
		list.sort_custom(func(a, b): return tr(str(a.name)).naturalnocasecmp_to(tr(str(b.name))) < 0)
	_select_tab(_tab)


func _build_content() -> void:
	_tabs.clear()
	_title = Control.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.draw.connect(_draw_title)
	add_child(_title)

	for i in range(TAB_LABELS.size()):
		var t := Control.new()
		t.mouse_filter = Control.MOUSE_FILTER_STOP
		t.draw.connect(_draw_tab.bind(t, i))
		t.gui_input.connect(_on_tab_input.bind(i))
		t.set_meta("sound", CREAM_SOUND_NAME)
		add_child(t)
		_tabs.append(t)

	_summary = Control.new()
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.draw.connect(_draw_summary)
	add_child(_summary)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 막대를 안 띄운다. 띄우면 칸 위에 얹혀 오른쪽 끝의 "5 / 10" 을 가렸다. 끌기와
	# 휠로는 그대로 스크롤되고, 아래 끝에서 잘린 칸 줄이 "더 있다"를 말해 준다.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = false
	add_child(_scroll)
	_sheet = Control.new()
	# PASS: 끌기는 스크롤로 올라가고, 짧은 누름만 여기서 칸 고르기로 쓴다.
	_sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	_sheet.draw.connect(_draw_sheet)
	_sheet.gui_input.connect(_on_sheet_input)
	_scroll.add_child(_sheet)

	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.draw.connect(_draw_info)
	add_child(_info)

	_cancel = _make_close_button(func(): close_pressed.emit())


func _layout_content(inner: Rect2) -> void:
	var pw: float = _panel_rect.size.x
	var ph: float = _panel_rect.size.y
	var x: float = inner.position.x
	var w: float = inner.size.x
	var y: float = inner.position.y

	var title_h: float = pw * TITLE_FRAC * 1.4
	_title.position = Vector2(x, y)
	_title.size = Vector2(w, title_h)
	y += title_h + pw * TITLE_GAP_FRAC

	var tab_h: float = ph * TAB_HEIGHT_FRAC
	var tab_w: float = (w - TAB_GAP * (_tabs.size() - 1)) / float(_tabs.size())
	for i in range(_tabs.size()):
		_tabs[i].position = Vector2(x + i * (tab_w + TAB_GAP), y)
		_tabs[i].size = Vector2(tab_w, tab_h)
		_tabs[i].pivot_offset = _tabs[i].size * 0.5
		_tabs[i].queue_redraw()
	y += tab_h + 8.0

	var summary_h: float = pw * SUMMARY_FRAC * 1.5 + SUMMARY_BAR_H + 6.0
	_summary.position = Vector2(x, y)
	_summary.size = Vector2(w, summary_h)
	y += summary_h + 8.0

	var info_h: float = pw * INFO_FRAC * 1.8
	_info.position = Vector2(x, inner.end.y - info_h)
	_info.size = Vector2(w, info_h)

	_scroll.position = Vector2(x, y)
	_scroll.size = Vector2(w, maxf(10.0, inner.end.y - info_h - 4.0 - y))
	_place_close_button(_cancel)
	_resize_sheet()


# 시트 높이는 탭 내용이 정한다. 폭은 스크롤 폭 그대로 — 세로 막대가 뜨면 그만큼
# 좁아지지만, 칸 치수는 그리는 순간의 _sheet.size.x 로 다시 재므로 어긋나지 않는다.
func _resize_sheet() -> void:
	if _sheet == null or _scroll == null:
		return
	var w: float = _scroll.size.x
	_sheet.custom_minimum_size = Vector2(w, _sheet_height(w))
	_sheet.queue_redraw()
	_summary.queue_redraw()
	_info.queue_redraw()
	for t in _tabs:
		t.queue_redraw()


func _select_tab(tab: int) -> void:
	_tab = tab
	match tab:
		Tab.FLAGS:
			_info_text = tr(HINT_FLAGS)
		Tab.MATH:
			_info_text = tr(HINT_MATH)
		_:
			_info_text = tr(HINT_COLORS)
	if _scroll != null:
		_scroll.scroll_vertical = 0
	_resize_sheet()


func _on_tab_input(event: InputEvent, index: int) -> void:
	if _is_press(event):
		_play_button_sound(_tabs[index])
		_select_tab(index)


func _is_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT


# ---- 치수 ----

func _section_font() -> int:
	return int(round(_panel_rect.size.x * SECTION_FRAC))


func _section_h() -> float:
	return _section_font() * SECTION_H_FRAC


# 국기 탭의 모든 칸: [{rect, record}] 과 머리글 [{y, tier}] 을 한 번에 잰다.
# 그리기와 누르기가 같은 것을 쓴다.
func _flag_layout(w: float) -> Dictionary:
	var cells: Array = []
	var headers: Array = []
	var cw: float = (w - CELL_GAP * (FLAG_COLUMNS - 1)) / float(FLAG_COLUMNS)
	var ch: float = cw * FLAG_ASPECT
	var y := 0.0
	for t in range(_flags_by_tier.size()):
		var list: Array = _flags_by_tier[t]
		if list.is_empty():
			continue
		headers.append({"y": y, "tier": t})
		y += _section_h()
		for i in range(list.size()):
			var col: int = i % FLAG_COLUMNS
			var row: int = i / FLAG_COLUMNS
			cells.append({
				"rect": Rect2(col * (cw + CELL_GAP), y + row * (ch + CELL_GAP), cw, ch),
				"record": list[i]})
		var rows: int = int(ceil(list.size() / float(FLAG_COLUMNS)))
		y += rows * ch + (rows - 1) * CELL_GAP + SECTION_GAP
	return {"cells": cells, "headers": headers, "height": y}


func _color_layout(w: float) -> Dictionary:
	var cells: Array = []
	var headers: Array = []
	var names: Array = _data.get("color_names", [])
	var cw: float = (w - CELL_GAP * (COLOR_COLUMNS - 1)) / float(COLOR_COLUMNS)
	var ch: float = cw * COLOR_CELL_ASPECT
	var y := 0.0
	for word in range(names.size()):
		headers.append({"y": y, "word": word})
		y += _section_h()
		var i := 0
		for ink in range(names.size()):
			if ink == word:
				continue   # 게임은 같은 색 조합을 내지 않는다 — 칸도 없다
			var col: int = i % COLOR_COLUMNS
			var row: int = i / COLOR_COLUMNS
			cells.append({
				"rect": Rect2(col * (cw + CELL_GAP), y + row * (ch + CELL_GAP), cw, ch),
				"word": word, "ink": ink})
			i += 1
		var rows: int = int(ceil(i / float(COLOR_COLUMNS)))
		y += rows * ch + (rows - 1) * CELL_GAP + SECTION_GAP
	return {"cells": cells, "headers": headers, "height": y}


func _math_row_h() -> float:
	return _panel_rect.size.x * MATH_ROW_FRAC


func _sheet_height(w: float) -> float:
	match _tab:
		Tab.FLAGS:
			return _flag_layout(w).height
		Tab.MATH:
			return _math_row_h() * MATH_LABELS.size()
		_:
			return _color_layout(w).height


# ---- 모은 수 ----

func _color_key(word: int, ink: int) -> String:
	var f: Callable = _data.get("color_key", Callable())
	return f.call(word, ink) if f.is_valid() else "%d/%d" % [word, ink]


## (모은 수, 전체) — 탭마다. 연산은 칸이 아니라 별이라 별 수로 센다.
func tab_progress(tab: int) -> Vector2i:
	match tab:
		Tab.FLAGS:
			var total: int = _data.get("flag_records", []).size()
			var got := 0
			var collected: Dictionary = _data.get("collected_flags", {})
			for record in _data.get("flag_records", []):
				if collected.has(str(record.code)):
					got += 1
			return Vector2i(got, total)
		Tab.MATH:
			var thresholds: Array = _data.get("math_thresholds", [])
			var solved: PackedInt32Array = _data.get("math_solved", PackedInt32Array())
			var stars := 0
			for n in solved:
				stars += _stars_for(n, thresholds)
			return Vector2i(stars, MATH_LABELS.size() * thresholds.size())
		_:
			var n: int = _data.get("color_names", []).size()
			return Vector2i(_data.get("collected_colors", {}).size(), n * (n - 1))


func _stars_for(solved: int, thresholds: Array) -> int:
	var s := 0
	for t in thresholds:
		if solved >= int(t):
			s += 1
	return s


# ---- 그리기 ----

func _draw_title() -> void:
	var fs: int = int(round(_panel_rect.size.x * TITLE_FRAC))
	var text: String = tr(TITLE)
	var tw: float = _font_heavy.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_title.draw_string(_font_heavy, Vector2((_title.size.x - tw) * 0.5, _title.size.y * 0.5 + fs * 0.36),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


func _draw_tab(t: Control, index: int) -> void:
	var on: bool = index == _tab
	t.draw_style_box(_pill(TAB_ON if on else TAB_OFF, t.size.y * 0.5), Rect2(Vector2.ZERO, t.size))
	var text: String = tr(TAB_LABELS[index])
	var fs: int = int(round(t.size.y * TAB_TEXT_FRAC))
	while fs > BUTTON_LABEL_MIN and _font_heavy.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > t.size.x * 0.86:
		fs -= 1
	var tw: float = _font_heavy.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2((t.size.x - tw) * 0.5, t.size.y * 0.5 + fs * 0.36)
	if on:
		t.draw_string_outline(_font_heavy, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			maxi(1, int(round(fs * TAB_TEXT_OUTLINE_FRAC))), INK)
	t.draw_string(_font_heavy, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		TAB_ON_TEXT if on else INK)


func _draw_summary() -> void:
	var p: Vector2i = tab_progress(_tab)
	var fs: int = int(round(_panel_rect.size.x * SUMMARY_FRAC))
	var text := "%d / %d" % [p.x, p.y]
	var tw: float = _font_heavy.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_summary.draw_string(_font_heavy, Vector2((_summary.size.x - tw) * 0.5, fs * 1.05),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	var bar := Rect2(0.0, _summary.size.y - SUMMARY_BAR_H, _summary.size.x, SUMMARY_BAR_H)
	_draw_bar(_summary, bar, float(p.x) / float(maxi(1, p.y)))


func _draw_bar(ci: Control, bar: Rect2, frac: float) -> void:
	ci.draw_style_box(_pill(BAR_TRACK, bar.size.y * 0.5), bar)
	var f: float = clampf(frac, 0.0, 1.0)
	if f > 0.0:
		# 둥근 끝이 뭉개지지 않게, 아무리 적어도 막대 높이만큼은 그린다.
		var fw: float = maxf(bar.size.y, bar.size.x * f)
		ci.draw_style_box(_pill(BAR_FILL, bar.size.y * 0.5), Rect2(bar.position, Vector2(fw, bar.size.y)))


func _draw_info() -> void:
	var fs: int = int(round(_panel_rect.size.x * INFO_FRAC))
	while fs > BUTTON_LABEL_MIN and _font_bold.get_string_size(
			_info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > _info.size.x:
		fs -= 1
	var tw: float = _font_bold.get_string_size(_info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_info.draw_string(_font_bold, Vector2((_info.size.x - tw) * 0.5, _info.size.y * 0.5 + fs * 0.36),
		_info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INFO_COLOR)


func _draw_sheet() -> void:
	match _tab:
		Tab.FLAGS:
			_draw_flags()
		Tab.MATH:
			_draw_math()
		_:
			_draw_colors()


func _draw_header(y: float, text: String, got: int, total: int) -> void:
	var fs: int = _section_font()
	var baseline: float = y + _section_h() * 0.5 + fs * 0.36
	_sheet.draw_string(_font_heavy, Vector2(0.0, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	var count := "%d / %d" % [got, total]
	var cw: float = _font_bold.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_sheet.draw_string(_font_bold, Vector2(_sheet.size.x - cw, baseline), count,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INFO_COLOR)


func _draw_unknown(r: Rect2) -> void:
	_sheet.draw_style_box(_pill(UNKNOWN_FILL, CELL_RADIUS), r)
	_draw_question(r, UNKNOWN_MARK)


func _draw_question(r: Rect2, color: Color) -> void:
	var fs: int = int(round(r.size.y * 0.55))
	var tw: float = _font_heavy.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_sheet.draw_string(_font_heavy, r.position + Vector2((r.size.x - tw) * 0.5, r.size.y * 0.5 + fs * 0.36),
		"?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_new_dot(r: Rect2) -> void:
	var c := Vector2(r.end.x - NEW_DOT_R * 0.6, r.position.y + NEW_DOT_R * 0.6)
	_sheet.draw_circle(c, NEW_DOT_R, NEW_DOT_RING)
	_sheet.draw_circle(c, NEW_DOT_R * 0.7, NEW_DOT)


func _visible_band() -> Vector2:
	# 스크롤 밖의 칸은 건너뛴다 — 193 장을 매번 다 그릴 까닭이 없다.
	var top: float = float(_scroll.scroll_vertical) if _scroll != null else 0.0
	var h: float = _scroll.size.y if _scroll != null else _sheet.size.y
	return Vector2(top - 40.0, top + h + 40.0)


func _draw_flags() -> void:
	var lay: Dictionary = _flag_layout(_sheet.size.x)
	var collected: Dictionary = _data.get("collected_flags", {})
	var seen: Dictionary = _data.get("seen_flags", {})
	var unviewed: Dictionary = _data.get("unviewed", {})
	var textures: Dictionary = _data.get("flag_textures", {})
	for h in lay.headers:
		var list: Array = _flags_by_tier[h.tier]
		var got := 0
		for r in list:
			if collected.has(str(r.code)):
				got += 1
		_draw_header(h.y, tr(TIER_LABELS[h.tier]), got, list.size())
	var band: Vector2 = _visible_band()
	for cell in lay.cells:
		var r: Rect2 = cell.rect
		if r.end.y < band.x or r.position.y > band.y:
			continue
		var code: String = str(cell.record.code)
		var tex: Texture2D = textures.get(code, null)
		if collected.has(code) and tex != null:
			_sheet.draw_texture_rect(tex, r, false)
			_sheet.draw_rect(r, FLAG_EDGE, false, 1.0)
			if unviewed.has("f:" + code):
				_draw_new_dot(r)
		elif seen.has(code) and tex != null:
			_sheet.draw_rect(r, SEEN_BACK)
			_sheet.draw_texture_rect(tex, r, false, SEEN_TINT)
			_draw_question(r, Color(1.0, 1.0, 1.0, 0.9))
		else:
			_draw_unknown(r)


func _draw_math() -> void:
	var thresholds: Array = _data.get("math_thresholds", [10, 50, 200])
	var solved: PackedInt32Array = _data.get("math_solved", PackedInt32Array())
	var unviewed: Dictionary = _data.get("unviewed", {})
	var row_h: float = _math_row_h()
	var w: float = _sheet.size.x
	var lfs: int = int(round(_panel_rect.size.x * MATH_LABEL_FRAC))
	var cfs: int = int(round(_panel_rect.size.x * MATH_COUNT_FRAC))
	var star_r: float = lfs * 0.62
	for i in range(MATH_LABELS.size()):
		var y0: float = i * row_h
		var n: int = solved[i] if i < solved.size() else 0
		var stars: int = _stars_for(n, thresholds)
		# 별 셋은 오른쪽 위, 이름은 그 왼쪽에 들어가는 만큼.
		var stars_w: float = star_r * 2.0 * thresholds.size() + 4.0 * (thresholds.size() - 1)
		var label: String = tr(MATH_LABELS[i])
		var fs: int = lfs
		while fs > BUTTON_LABEL_MIN and _font_heavy.get_string_size(
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - stars_w - 10.0:
			fs -= 1
		var label_base: float = y0 + row_h * 0.30 + fs * 0.36
		_sheet.draw_string(_font_heavy, Vector2(0.0, label_base), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
		for s in range(thresholds.size()):
			var c := Vector2(w - stars_w + star_r + s * (star_r * 2.0 + 4.0), y0 + row_h * 0.30)
			_draw_star(c, star_r, s < stars)
		if unviewed.has("m:%d" % i):
			_sheet.draw_circle(Vector2(w - stars_w - 8.0, y0 + row_h * 0.30 - star_r * 0.6), NEW_DOT_R * 0.8, NEW_DOT)
		# 막대는 다음 별까지. 별을 다 받으면 가득 찬 막대에 MAX.
		var lo: int = 0 if stars == 0 else int(thresholds[stars - 1])
		var hi: int = int(thresholds[stars]) if stars < thresholds.size() else n
		var frac: float = 1.0 if stars >= thresholds.size() else float(n - lo) / float(maxi(1, hi - lo))
		var count: String = ("%d  %s" % [n, tr(MAX_TEXT)]) if stars >= thresholds.size() else "%d / %d" % [n, hi]
		var count_w: float = _font_bold.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var bar_y: float = y0 + row_h * 0.62
		_draw_bar(_sheet, Rect2(0.0, bar_y, w - count_w - 10.0, MATH_BAR_H), frac)
		_sheet.draw_string(_font_bold, Vector2(w - count_w, bar_y + MATH_BAR_H * 0.5 + cfs * 0.36),
			count, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, INFO_COLOR)


func _draw_star(c: Vector2, r: float, on: bool) -> void:
	var pts := PackedVector2Array()
	for k in range(10):
		var a: float = -PI * 0.5 + k * PI / 5.0
		var rr: float = r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	_sheet.draw_colored_polygon(pts, STAR_ON if on else STAR_OFF)
	var ring := pts.duplicate()
	ring.append(pts[0])
	_sheet.draw_polyline(ring, STAR_EDGE if on else STAR_OFF.darkened(0.2), 1.5, true)


func _draw_colors() -> void:
	var lay: Dictionary = _color_layout(_sheet.size.x)
	var names: Array = _data.get("color_names", [])
	var rgb: Array = _data.get("color_rgb", [])
	var collected: Dictionary = _data.get("collected_colors", {})
	var unviewed: Dictionary = _data.get("unviewed", {})
	for h in lay.headers:
		var got := 0
		for ink in range(names.size()):
			if ink != h.word and collected.has(_color_key(h.word, ink)):
				got += 1
		_draw_header(h.y, tr(str(names[h.word])), got, names.size() - 1)
	var band: Vector2 = _visible_band()
	for cell in lay.cells:
		var r: Rect2 = cell.rect
		if r.end.y < band.x or r.position.y > band.y:
			continue
		var key: String = _color_key(cell.word, cell.ink)
		if not collected.has(key):
			_draw_unknown(r)
			continue
		var cell_box := _pill(COLOR_CELL_FILL, CELL_RADIUS)
		cell_box.border_color = COLOR_CELL_EDGE
		cell_box.set_border_width_all(1)
		_sheet.draw_style_box(cell_box, r)
		# 게임에서 본 그대로 — 단어는 cell.word, 칠한 색은 cell.ink.
		var word: String = tr(str(names[cell.word]))
		var fs: int = int(round(r.size.y * COLOR_WORD_FRAC))
		while fs > 7 and _font_heavy.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x * 0.88:
			fs -= 1
		var tw: float = _font_heavy.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos: Vector2 = r.position + Vector2((r.size.x - tw) * 0.5, r.size.y * 0.5 + fs * 0.36)
		_sheet.draw_string_outline(_font_heavy, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			maxi(2, int(round(fs * COLOR_OUTLINE_FRAC))), COLOR_OUTLINE)
		_sheet.draw_string(_font_heavy, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			rgb[cell.ink] if cell.ink < rgb.size() else INK)
		if unviewed.has("c:" + key):
			_draw_new_dot(r)


# ---- 누르기 ----

func _on_sheet_input(event: InputEvent) -> void:
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
	else:
		return
	if pressed:
		_press_pos = event.position
		_pressing = true
	elif released and _pressing:
		_pressing = false
		if event.position.distance_to(_press_pos) <= TAP_SLOP:
			tap_at(event.position)


## 시트 좌표의 한 점을 눌렀을 때. 체커가 직접 부른다.
func tap_at(p: Vector2) -> void:
	match _tab:
		Tab.FLAGS:
			var collected: Dictionary = _data.get("collected_flags", {})
			var seen: Dictionary = _data.get("seen_flags", {})
			for cell in _flag_layout(_sheet.size.x).cells:
				if cell.rect.has_point(p):
					var code: String = str(cell.record.code)
					if collected.has(code):
						_info_text = tr(str(cell.record.name))
					elif seen.has(code):
						_info_text = tr(INFO_SEEN)
					else:
						_info_text = tr(INFO_UNSEEN)
					break
		Tab.COLORS:
			var names: Array = _data.get("color_names", [])
			var collected_c: Dictionary = _data.get("collected_colors", {})
			for cell in _color_layout(_sheet.size.x).cells:
				if cell.rect.has_point(p):
					if collected_c.has(_color_key(cell.word, cell.ink)):
						_info_text = tr(INFO_COLOR_FORMAT) % [
							tr(str(names[cell.word])), tr(str(names[cell.ink])).to_lower()]
					else:
						_info_text = tr(INFO_UNSEEN)
					break
	_info.queue_redraw()


## 지금 아랫줄에 나온 글. 체커용.
func info_text() -> String:
	return _info_text


## 판 바깥을 누르면 닫는다 — 설정 팝업과 같다.
func _gui_input(event: InputEvent) -> void:
	if _is_press(event) and not _panel_rect.has_point(event.position):
		close_pressed.emit()


func _process(delta: float) -> void:
	super._process(delta)
	# 스크롤하면 보이는 칸이 바뀌므로 다시 그린다(_visible_band). 스크롤 신호가
	# 따로 있지만 관성 스크롤까지 따라가려면 이쪽이 간단하다.
	if visible and _scroll != null and _sheet != null \
			and _scroll.scroll_vertical != int(_sheet.get_meta("drawn_at", -1)):
		_sheet.set_meta("drawn_at", _scroll.scroll_vertical)
		_sheet.queue_redraw()
