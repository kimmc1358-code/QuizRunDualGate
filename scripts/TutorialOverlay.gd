extends Control

## 게임 화면에 처음 들어왔을 때 한 번 도는 튜토리얼.
##
## 화면을 어둡게 덮고 한 번에 하나씩만 구멍을 내어 밝힌다. 캐릭터 -> 퀴즈 ->
## 가속(버튼과 바) 순서로, 각각 그 자리에서 무엇을 하는지 한 줄로 말한다.
##
## 메뉴에서 설명하지 않고 게임 화면 위에서 하는 이유가 있다. 여기서 말하는
## 것들은 전부 "화면의 이 물건"에 관한 것이라, 그 물건을 옆에 두고 봐야
## 옮겨진다 — 메뉴에서 그림으로 보여 주면 실제 화면에서 같은 것을 다시 찾아야
## 한다. 특히 가속 보너스는 버튼과 바가 화면 반대쪽 끝에 떨어져 있어서, 둘을
## 동시에 밝히지 않으면 관계가 안 읽힌다.
##
## 판은 멈춰 있다. Main 이 State.COUNTDOWN 에서 시계를 세워 둔 채 띄우므로
## 게이트도 캐릭터도 그 자리에 있고, 뒤에서 무엇이 흘러가지 않는다.
##
## 구멍의 자리와 문구는 전부 Main 이 넘긴다(begin) — 이 화면은 게임의 배치를
## 모르고, 알게 두면 HUD 를 옮길 때마다 두 군데를 고쳐야 한다.

signal finished

const FONT_WEIGHT_BOLD := 600
const FONT_WEIGHT_HEAVY := 700

const SCRIM_COLOR := Color(0.02, 0.03, 0.07, 0.78)
# 구멍 둘레의 밝은 테두리. 어둡게만 덮으면 "덜 어두운 곳"으로 보이지,
# 가리키는 것으로는 안 읽힌다.
const RING_COLOR := Color(1.0, 0.88, 0.35, 0.95)
const RING_WIDTH := 3.0
const RING_PAD := 6.0            # 구멍을 대상보다 이만큼 넓게 — 딱 맞추면 갑갑하다

# 설명 판.
const CARD_COLOR := Color(0.06, 0.09, 0.16, 0.94)
const CARD_RADIUS := 14
const CARD_MARGIN_X_FRAC := 0.07     # 화면 폭 대비 좌우 여백
const CARD_PAD_FRAC := 0.045         # 화면 폭 대비 판 안쪽 여백
const CARD_GAP := 18.0               # 구멍과 판 사이
const TEXT_SIZE_FRAC := 0.048        # 화면 폭 대비
# 한 줄이 판을 넘으면 글자를 줄여 맞춘다. 문구를 고칠 때마다 폭을 재 보게
# 하는 대신, 넘치면 알아서 작아지고 이 바닥 밑으로 가면 체커가 잡는다.
const TEXT_MIN_SIZE := 13
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const TEXT_LINE_GAP := 1.30          # 줄 간격, 글자 크기 대비

const STEP_LABEL_SIZE_FRAC := 0.034
const STEP_LABEL_COLOR := Color(1.0, 0.82, 0.30, 1.0)

const HINT_SIZE_FRAC := 0.036
const HINT_COLOR := Color(0.80, 0.84, 0.92, 0.85)
const HINT_TEXT := "TAP TO CONTINUE"
const HINT_LAST_TEXT := "TAP TO START"
const HINT_BOTTOM_FRAC := 0.055      # 화면 높이 대비, 아래에서

# 탭 표시: 채운 원 + 퍼지는 링. 손가락 그림이 없어 직접 그린다 — 링이 커지며
# 옅어지는 것만으로 "여기를 눌러라"는 충분히 읽힌다.
const TAP_PERIOD := 1.1              # 초
const TAP_DOT_RADIUS := 13.0
const TAP_DOT_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const TAP_RING_MAX := 40.0
const TAP_RING_WIDTH := 3.0
const TAP_RING_COLOR := Color(1.0, 0.88, 0.35, 1.0)

var _steps: Array = []
var _index: int = 0
var _elapsed: float = 0.0
var _font_bold: Font
var _font_heavy: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var base: Font = AppFont.base()
	var wght: int = TextServerManager.get_primary_interface().name_to_tag("weight")
	_font_bold = _weighted(base, wght, FONT_WEIGHT_BOLD)
	_font_heavy = _weighted(base, wght, FONT_WEIGHT_HEAVY)
	set_process(false)


func _weighted(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv


## 단계 목록을 받아 첫 단계부터 시작한다.
##
## 각 단계는 Dictionary:
##   "holes": Array[Dictionary] — 밝힐 자리. 각각 {"rect": Rect2, "round": float}
##            round 는 모서리 반지름이고, 크게 주면 원이 된다.
##   "text":  String  — 줄바꿈 포함 한두 줄
##   "tap":   Vector2 — 탭 표시를 놓을 자리. 안 쓰면 생략
func begin(steps: Array) -> void:
	_steps = steps
	_index = 0
	_elapsed = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	# 탭 표시가 뛰는 단계에서만 매 프레임 다시 그린다. 나머지는 정지 화면이라
	# 스크림을 한 줄씩 칠하는 비용을 매 프레임 낼 이유가 없다.
	if _current().has("tap"):
		queue_redraw()


func _current() -> Dictionary:
	if _index < 0 or _index >= _steps.size():
		return {}
	return _steps[_index]


func _gui_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER):
		tapped = true
	if not tapped:
		return
	accept_event()
	_index += 1
	_elapsed = 0.0
	if _index >= _steps.size():
		visible = false
		set_process(false)
		finished.emit()
		return
	queue_redraw()


# ---- 그리기 ----

func _draw() -> void:
	var step: Dictionary = _current()
	if step.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var holes: Array = step.get("holes", [])
	_draw_scrim(holes)
	for hole in holes:
		_draw_ring(hole)
	_draw_card(step, holes)
	if step.has("tap"):
		_draw_tap(step["tap"])
	_draw_hint()


# 어두운 덮개에 구멍을 낸다.
#
# 구멍이 걸치지 않는 세로 구간은 통째로 한 번에 칠하고, 걸치는 구간만 한 줄씩
# 칠한다. 화면 전체를 한 줄씩 칠하면 1000줄이 넘는데, 실제로 구멍이 있는 것은
# 그중 백여 줄뿐이다.
func _draw_scrim(holes: Array) -> void:
	if holes.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), SCRIM_COLOR, true)
		return
	# 구멍들의 세로 구간을 위에서부터 훑는다.
	var bands: Array = []
	for hole in holes:
		var r: Rect2 = _hole_rect(hole)
		bands.append([maxf(0.0, r.position.y), minf(size.y, r.end.y)])
	bands.sort_custom(func(a, b): return a[0] < b[0])

	var y: float = 0.0
	for band in bands:
		var top: float = float(band[0])
		var bottom: float = float(band[1])
		if top > y:
			draw_rect(Rect2(0.0, y, size.x, top - y), SCRIM_COLOR, true)
		# 이미 지나온 구간과 겹치면 그만큼만 이어서.
		var from: float = maxf(y, top)
		var row: float = from
		while row < bottom:
			_draw_scrim_row(row, holes)
			row += 1.0
		y = maxf(y, bottom)
	if y < size.y:
		draw_rect(Rect2(0.0, y, size.x, size.y - y), SCRIM_COLOR, true)


# 한 줄에서 구멍이 차지하는 x 구간을 빼고 칠한다.
func _draw_scrim_row(y: float, holes: Array) -> void:
	var cuts: Array = []
	for hole in holes:
		var span: Vector2 = _hole_span(hole, y + 0.5)
		if span.y > span.x:
			cuts.append(span)
	if cuts.is_empty():
		draw_rect(Rect2(0.0, y, size.x, 1.0), SCRIM_COLOR, true)
		return
	cuts.sort_custom(func(a, b): return a.x < b.x)
	var x: float = 0.0
	for cut: Vector2 in cuts:
		if cut.x > x:
			draw_rect(Rect2(x, y, cut.x - x, 1.0), SCRIM_COLOR, true)
		x = maxf(x, cut.y)
	if x < size.x:
		draw_rect(Rect2(x, y, size.x - x, 1.0), SCRIM_COLOR, true)


func _hole_rect(hole: Dictionary) -> Rect2:
	return (hole.get("rect", Rect2()) as Rect2).grow(RING_PAD)


func _hole_radius(hole: Dictionary) -> float:
	var r: Rect2 = _hole_rect(hole)
	return minf(float(hole.get("round", 0.0)), minf(r.size.x, r.size.y) * 0.5)


# 이 줄에서 구멍이 뚫려 있는 x 범위. 모서리 구간에서는 원의 식으로 좁아진다.
func _hole_span(hole: Dictionary, y: float) -> Vector2:
	var r: Rect2 = _hole_rect(hole)
	if y < r.position.y or y > r.end.y:
		return Vector2.ZERO
	var rad: float = _hole_radius(hole)
	var cut: float = 0.0
	if rad > 0.0:
		var dy: float = 0.0
		if y < r.position.y + rad:
			dy = (r.position.y + rad) - y
		elif y > r.end.y - rad:
			dy = y - (r.end.y - rad)
		if dy > 0.0:
			cut = rad - sqrt(maxf(0.0, rad * rad - dy * dy))
	return Vector2(r.position.x + cut, r.end.x - cut)


func _draw_ring(hole: Dictionary) -> void:
	var r: Rect2 = _hole_rect(hole)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.set_corner_radius_all(int(round(_hole_radius(hole))))
	box.set_border_width_all(int(round(RING_WIDTH)))
	box.border_color = RING_COLOR
	box.anti_aliasing = true
	draw_style_box(box, r)


# 설명 판. 구멍 덩어리의 반대쪽 — 구멍이 위쪽이면 아래에, 아래쪽이면 위에.
## 모든 줄이 판 안에 들어가는 가장 큰 글자 크기.
##
## draw_string 은 폭을 넘는 줄을 잘라 낸다 — 문구를 한 단어 늘렸다가 마지막
## 글자가 사라지는 식으로 조용히 깨진다. 넘치면 줄여서 맞추고, 바닥
## (TEXT_MIN_SIZE)까지 줄여도 안 들어가면 문구가 너무 긴 것이므로 체커가 잡는다.
func _fit_text_size(lines: PackedStringArray, room: float) -> int:
	var font: Font = _font_bold if _font_bold != null else ThemeDB.fallback_font
	var s: int = maxi(TEXT_MIN_SIZE, int(round(size.x * TEXT_SIZE_FRAC)))
	while s > TEXT_MIN_SIZE:
		var widest := 0.0
		for line in lines:
			widest = maxf(widest, font.get_string_size(
				line, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x)
		if widest <= room:
			break
		s -= 1
	return s


## 가장 긴 줄이 자리를 얼마나 넘는가. 0 이하면 다 들어간다. 체커용이 아니라
## 위 피팅이 바닥까지 갔을 때 남는 초과분을 재는 값이다.
func _line_overflow(step: Dictionary) -> float:
	var lines: PackedStringArray = str(step.get("text", "")).split("\n")
	var room: float = size.x * (1.0 - CARD_MARGIN_X_FRAC * 2.0) - size.x * CARD_PAD_FRAC * 2.0
	var font: Font = _font_bold if _font_bold != null else ThemeDB.fallback_font
	var s: int = _fit_text_size(lines, room)
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x)
	return widest - room


## 설명 판이 놓일 사각형. 그리는 쪽과 체커가 같은 답을 봐야 하므로 함수로 둔다 —
## 판이 하이라이트를 덮는 것이 정확히 이 계산의 실수였다.
func _card_rect(step: Dictionary) -> Rect2:
	var text: String = str(step.get("text", ""))
	if text.is_empty() or size.x <= 0.0:
		return Rect2()
	var margin: float = size.x * CARD_MARGIN_X_FRAC
	var pad: float = size.x * CARD_PAD_FRAC
	var lines: PackedStringArray = text.split("\n")
	var text_size: int = _fit_text_size(lines, size.x * (1.0 - CARD_MARGIN_X_FRAC * 2.0) - size.x * CARD_PAD_FRAC * 2.0)
	var label_size: int = maxi(8, int(round(size.x * STEP_LABEL_SIZE_FRAC)))
	var card_h: float = pad * 2.0 + label_size * TEXT_LINE_GAP \
		+ text_size * TEXT_LINE_GAP * lines.size()
	return Rect2(margin, _card_y(step.get("holes", []), card_h),
		size.x - margin * 2.0, card_h)


func _draw_card(step: Dictionary, _holes: Array) -> void:
	var card: Rect2 = _card_rect(step)
	if card.size.x <= 0.0:
		return
	var text: String = str(step.get("text", ""))
	var pad: float = size.x * CARD_PAD_FRAC
	var lines: PackedStringArray = text.split("\n")
	var text_size: int = _fit_text_size(lines, size.x * (1.0 - CARD_MARGIN_X_FRAC * 2.0) - size.x * CARD_PAD_FRAC * 2.0)
	var label_size: int = maxi(8, int(round(size.x * STEP_LABEL_SIZE_FRAC)))
	var line_h: float = text_size * TEXT_LINE_GAP
	var label: String = "%d / %d" % [_index + 1, _steps.size()]
	var card_w: float = card.size.x
	var box := StyleBoxFlat.new()
	box.bg_color = CARD_COLOR
	box.set_corner_radius_all(CARD_RADIUS)
	box.anti_aliasing = true
	draw_style_box(box, card)

	var font: Font = _font_bold if _font_bold != null else ThemeDB.fallback_font
	var heavy: Font = _font_heavy if _font_heavy != null else font
	var y: float = card.position.y + pad + label_size
	draw_string(heavy, Vector2(card.position.x, y), label,
		HORIZONTAL_ALIGNMENT_CENTER, card_w, label_size, STEP_LABEL_COLOR)
	y += label_size * (TEXT_LINE_GAP - 1.0) + text_size
	for line in lines:
		draw_string(font, Vector2(card.position.x, y), line,
			HORIZONTAL_ALIGNMENT_CENTER, card_w, text_size, TEXT_COLOR)
		y += line_h


# 설명 판을 놓을 세로 자리.
#
# "구멍이 위쪽이면 아래에" 같은 단순한 규칙으로는 3단계에서 깨진다. 거기서는
# 바가 화면 맨 위, 가속 버튼이 맨 아래라 구멍 덩어리가 화면 전체를 걸치고,
# 위든 아래든 둘 중 하나를 덮는다 — 실제로 판이 바 위에 앉아 정작 가리키는
# 것을 가렸다.
#
# 그래서 구멍이 없는 세로 구간을 전부 구해 그중 가장 넓은 데를 쓴다. 그 구간이
# 위아래 모두 구멍에 막혀 있으면 가운데에, 한쪽만 막혀 있으면 그 구멍 쪽으로
# 붙인다 — 설명은 가리키는 것 가까이 있어야 짝이 지어진다.
func _card_y(holes: Array, card_h: float) -> float:
	if holes.is_empty():
		return (size.y - card_h) * 0.5
	var bands: Array = []
	for hole in holes:
		var r: Rect2 = _hole_rect(hole)
		bands.append(Vector2(r.position.y - CARD_GAP, r.end.y + CARD_GAP))
	bands.sort_custom(func(a, b): return a.x < b.x)

	var best_y: float = (size.y - card_h) * 0.5
	var best_room: float = -1.0
	var cursor: float = 0.0
	var blocked_above := false
	for band: Vector2 in bands:
		var gap: float = band.x - cursor
		if gap > best_room and gap >= card_h:
			best_room = gap
			best_y = _place_in_band(cursor, band.x, card_h, blocked_above, true)
		cursor = maxf(cursor, band.y)
		blocked_above = true
	var tail: float = size.y - cursor
	if tail > best_room and tail >= card_h:
		best_y = _place_in_band(cursor, size.y, card_h, blocked_above, false)
	return clampf(best_y, 0.0, maxf(0.0, size.y - card_h))


func _place_in_band(top: float, bottom: float, card_h: float,
		hole_above: bool, hole_below: bool) -> float:
	if hole_above and hole_below:
		return top + (bottom - top - card_h) * 0.5
	if hole_above:
		return top                      # 위쪽 구멍에 붙인다
	return bottom - card_h              # 아래쪽 구멍에 붙인다


func _draw_tap(at: Vector2) -> void:
	var t: float = fmod(_elapsed, TAP_PERIOD) / TAP_PERIOD
	# 링은 커지며 사라지고, 점은 눌리듯 살짝 작아졌다 돌아온다.
	var ring_r: float = TAP_DOT_RADIUS + (TAP_RING_MAX - TAP_DOT_RADIUS) * t
	var ring := Color(TAP_RING_COLOR.r, TAP_RING_COLOR.g, TAP_RING_COLOR.b,
		TAP_RING_COLOR.a * clampf(1.0 - t, 0.0, 1.0))
	draw_arc(at, ring_r, 0.0, TAU, 48, ring, TAP_RING_WIDTH, true)
	var squash: float = 1.0 - 0.18 * sin(t * PI)
	draw_circle(at, TAP_DOT_RADIUS * squash, TAP_DOT_COLOR)


func _draw_hint() -> void:
	var font: Font = _font_heavy if _font_heavy != null else ThemeDB.fallback_font
	var s: int = maxi(8, int(round(size.x * HINT_SIZE_FRAC)))
	var text: String = tr(HINT_LAST_TEXT) if _index == _steps.size() - 1 else tr(HINT_TEXT)
	draw_string(font, Vector2(0.0, size.y - size.y * HINT_BOTTOM_FRAC), text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, s, HINT_COLOR)
