extends PopupBase

## 설치 후 첫 판을 시작하기 직전에 한 번만 뜨는 안내. 가속 바에 남은 만큼
## 점수가 붙는다는 것을 알려 준다.
##
## 이 하나만 따로 안내하는 이유가 있다. "상단의 문제를 보고 맞는 게이트로
## 간다"는 화면만 봐도 읽히지만, 가속 버튼과 점수의 관계는 그렇지 않다 —
## 버튼을 눌러도 바가 줄어드는 속도는 그대로이고(게이트가 먼저 도착할 뿐),
## 그래서 화면에서는 "누르니까 점수가 는다"가 보이지 않는다. 게다가 바는
## 줄어드는 물건이라 "남기면 이득"과 정반대로 읽히기 쉽다.
##
## 그래서 글로 설명하는 대신 실제 바를 세 단계로 늘어놓고 옆에 배율을 적는다.
## 게임에서 보게 될 그림 그대로라, 안내를 읽은 뒤 화면에서 같은 것을 알아볼 수
## 있다.
##
## 아트와 수치는 전부 Main 이 넘겨준다(set_boost_info) — 여기에 다시 적으면
## 튜닝을 바꿨을 때 안내문만 옛 숫자를 말하게 된다.

signal ok_pressed

const TITLE_TEXT := "BOOST BONUS"
const TITLE_SIZE_FRAC := 0.082         # 판 너비 대비
const TITLE_COLOR := Color(0.055, 0.180, 0.435, 1.0)

const BODY_TEXT := "Hold BOOST and the gate arrives sooner,\nso the bar still has some left.\nThe more it has left, the more you score."
const BODY_SIZE_FRAC := 0.046
const BODY_COLOR := Color(0.42, 0.44, 0.48, 1.0)

# 바 한 줄의 높이와 그 오른쪽 배율 글자.
const ROW_HEIGHT_FRAC := 0.088         # 판 너비 대비
const ROW_GAP_FRAC := 0.038
const ROW_LABEL_WIDTH_FRAC := 0.20     # 판 안쪽 폭 대비 — 배율이 들어갈 칸
const ROW_LABEL_SIZE_FRAC := 0.060
const ROW_LABEL_COLOR := Color(0.055, 0.180, 0.435, 1.0)

const PAD_AFTER_TITLE_FRAC := 0.055    # 판 너비 대비
const PAD_AFTER_BODY_FRAC := 0.070
const PAD_BEFORE_BUTTON_FRAC := 0.075

const OK_TEXT := "OK"
const OK_WIDTH_FRAC := 0.52            # 판 안쪽 폭 대비
const OK_HEIGHT_FRAC := 0.155          # 판 너비 대비

var _title: Control
var _body: Label
var _rows: Array[Control] = []
var _ok: Button

# Main 이 넘겨준다. 기본값은 아무것도 안 그리는 상태다.
var _track: Texture2D
var _fills: Array[Texture2D] = []
var _fill_inset := 0.176
var _thresholds := PackedFloat32Array([0.12, 0.48])
var _multipliers := PackedFloat32Array([0.0, 0.5, 1.0])


const PANEL_WIDTH_FRAC := 0.86


## 판 높이는 내용에 맞춘다.
##
## 다른 팝업처럼 화면 높이 대비 비율로 두면 안 된다. 여기 담긴 것들은 전부 판
## '너비' 기준으로 크기가 정해지고 판 너비는 화면 폭(항상 480)에 묶여 있어서,
## 내용 높이는 어느 기기에서나 같은 픽셀이다. 그런데 판만 화면 높이를 따라가면
## 긴 화면에서 위아래가 휑하게 남는다 — 처음에 0.62 로 두었더니 20:9 에서
## 660px 판에 400px 짜리 내용이 떠 있었다.
func panel_size_frac() -> Vector2:
	if size.y <= 0.0:
		return Vector2(PANEL_WIDTH_FRAC, 0.55)
	var pw: float = size.x * PANEL_WIDTH_FRAC
	var inner_w: float = pw - pw * CONTENT_SIDE_FRAC * 2.0
	var ph: float = _metrics(inner_w)["total"] / (1.0 - CONTENT_TOP_FRAC - CONTENT_BOTTOM_FRAC)
	return Vector2(PANEL_WIDTH_FRAC, clampf(ph / size.y, 0.20, 0.92))


## 안쪽 폭 하나로 정해지는 조각별 높이. 판 크기를 정할 때와 실제로 배치할 때
## 같은 답이 나와야 해서 한 군데에 둔다.
func _metrics(pw: float) -> Dictionary:
	var body_size: int = maxi(9, int(round(pw * BODY_SIZE_FRAC)))
	var body_h := 0.0
	if _body != null:
		_body.add_theme_font_size_override("font_size", body_size)
		if _font_bold != null:
			_body.add_theme_font_override("font", _font_bold)
		body_h = _body.get_minimum_size().y
	var m := {
		"title": pw * TITLE_SIZE_FRAC * 1.5,
		"body": body_h,
		"body_size": body_size,
		"row": pw * ROW_HEIGHT_FRAC,
		"row_gap": pw * ROW_GAP_FRAC,
		"ok_h": pw * OK_HEIGHT_FRAC,
		"ok_w": pw * OK_WIDTH_FRAC,
	}
	m["total"] = m["title"] + pw * PAD_AFTER_TITLE_FRAC \
		+ m["body"] + pw * PAD_AFTER_BODY_FRAC \
		+ m["row"] * 3.0 + m["row_gap"] * 2.0 \
		+ pw * PAD_BEFORE_BUTTON_FRAC + m["ok_h"]
	return m


func _build_content() -> void:
	_title = Control.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.draw.connect(_draw_title)
	add_child(_title)

	_body = Label.new()
	_body.text = BODY_TEXT
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_color_override("font_color", BODY_COLOR)
	add_child(_body)

	_rows.clear()
	for i in range(3):
		var row := Control.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.draw.connect(_draw_row.bind(i))
		add_child(row)
		_rows.append(row)

	_ok = _make_button(GOLD_FILE, GOLD_CORNER, OK_TEXT, null, true)
	_ok.pressed.connect(func(): ok_pressed.emit())
	add_child(_ok)


## Main 의 아트와 수치를 그대로 받는다. thresholds 는 [mid, best],
## multipliers 는 [none, mid, best] 로 Main 의 boost_bonus_* 와 같은 순서다.
func set_boost_info(track: Texture2D, fills: Array[Texture2D], fill_inset: float,
		thresholds: PackedFloat32Array, multipliers: PackedFloat32Array) -> void:
	_track = track
	_fills = fills
	_fill_inset = fill_inset
	if thresholds.size() >= 2:
		_thresholds = thresholds
	if multipliers.size() >= 3:
		_multipliers = multipliers
	for row in _rows:
		row.queue_redraw()


## 한 단계를 대표할 잔량. 문턱에서 뽑으므로 튜닝을 바꾸면 그림도 따라간다 —
## 0.10/0.30/0.79 처럼 박아 두면 문턱만 옮겼을 때 안내 그림이 거짓말을 한다.
##
## 첫 줄은 문턱 '바로 아래'를 쓴다. 절반으로 잡았더니 게이지가 점 하나로 보여
## 고장 난 것처럼 읽혔고, "이만큼 남겨도 아직 보너스가 없다"는 뜻도 안 살았다.
func _row_remaining(tier: int) -> float:
	var mid: float = _thresholds[0]
	var best: float = _thresholds[1]
	match tier:
		0: return mid * 0.85
		1: return (mid + best) * 0.5
		_: return best + (1.0 - best) * 0.6


func _row_label(tier: int) -> String:
	var total: float = 1.0 + _multipliers[clampi(tier, 0, _multipliers.size() - 1)]
	# 1.0 -> "x1", 1.5 -> "x1.5". 소수점 뒤 0 은 떼어 낸다.
	var text: String = "%.1f" % total
	if text.ends_with(".0"):
		text = text.substr(0, text.length() - 2)
	return "×" + text


func _layout_content(inner: Rect2) -> void:
	var pw: float = inner.size.x
	var m: Dictionary = _metrics(pw)
	var title_h: float = m["title"]
	var body_h: float = m["body"]
	var row_h: float = m["row"]
	var row_gap: float = m["row_gap"]
	var ok_h: float = m["ok_h"]
	var ok_w: float = m["ok_w"]
	var y: float = inner.position.y + (inner.size.y - float(m["total"])) * 0.5

	_title.position = Vector2(inner.position.x, y)
	_title.size = Vector2(pw, title_h)
	_title.queue_redraw()
	y += title_h + pw * PAD_AFTER_TITLE_FRAC

	_body.position = Vector2(inner.position.x, y)
	_body.size = Vector2(pw, body_h)
	y += body_h + pw * PAD_AFTER_BODY_FRAC

	for i in range(_rows.size()):
		_rows[i].position = Vector2(inner.position.x, y)
		_rows[i].size = Vector2(pw, row_h)
		_rows[i].queue_redraw()
		y += row_h + (row_gap if i < _rows.size() - 1 else 0.0)
	y += pw * PAD_BEFORE_BUTTON_FRAC

	_place(_ok, inner.position.x + (pw - ok_w) * 0.5, y, ok_w, ok_h)


func _draw_title() -> void:
	var font: Font = _font_heavy if _font_heavy != null else ThemeDB.fallback_font
	var size: int = maxi(10, int(round(_title.size.x * TITLE_SIZE_FRAC)))
	var w: float = font.get_string_size(TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_title.draw_string(font,
		Vector2((_title.size.x - w) * 0.5, _title.size.y * 0.5 + size * 0.36),
		TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TITLE_COLOR)


# 한 줄: 실제 트랙 아트에 그 단계의 채움을 얹고, 오른쪽에 배율.
#
# 게임 화면과 같은 3-slice 로 그린다 — 캡슐의 둥근 끝이 폭에 상관없이 둥글게
# 남아야 하고, 그래야 안내에서 본 것과 화면에서 보는 것이 같은 물건으로 읽힌다.
func _draw_row(tier: int) -> void:
	if tier < 0 or tier >= _rows.size() or _track == null:
		return
	var row: Control = _rows[tier]
	var label_w: float = row.size.x * ROW_LABEL_WIDTH_FRAC
	var bar := Rect2(Vector2.ZERO, Vector2(maxf(0.0, row.size.x - label_w), row.size.y))
	_draw_capsule(row, _track, bar, _track.get_height() * 0.5)

	var inset: float = bar.size.y * _fill_inset
	var well := Rect2(bar.position + Vector2(inset, inset), bar.size - Vector2(inset, inset) * 2.0)
	var remaining: float = _row_remaining(tier)
	if tier < _fills.size() and _fills[tier] != null and well.size.y > 0.0:
		var fill: Texture2D = _fills[tier]
		_draw_capsule(row, fill,
			Rect2(well.position, Vector2(well.size.x * remaining, well.size.y)),
			fill.get_height() * 0.5)

	var font: Font = _font_heavy if _font_heavy != null else ThemeDB.fallback_font
	var size: int = maxi(9, int(round(row.size.x * ROW_LABEL_SIZE_FRAC)))
	var text: String = _row_label(tier)
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	row.draw_string(font,
		Vector2(bar.end.x + (label_w - tw) * 0.5, row.size.y * 0.5 + size * 0.36),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ROW_LABEL_COLOR)


# 좌우 끝은 원본 크기로, 가운데만 늘린다. Main._draw_horizontal_slice 와 같은
# 그림을 내지만 그쪽은 Main 의 것이고 이 팝업은 Main 을 모른다.
func _draw_capsule(ci: CanvasItem, texture: Texture2D, rect: Rect2, cap: float) -> void:
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var tw: float = float(texture.get_width())
	var th: float = float(texture.get_height())
	var scale: float = rect.size.y / th
	var cap_w: float = minf(cap * scale, rect.size.x * 0.5)
	var src_cap: float = minf(cap, tw * 0.5)
	# 왼쪽 끝
	ci.draw_texture_rect_region(texture,
		Rect2(rect.position, Vector2(cap_w, rect.size.y)),
		Rect2(0.0, 0.0, src_cap, th))
	# 오른쪽 끝
	ci.draw_texture_rect_region(texture,
		Rect2(Vector2(rect.end.x - cap_w, rect.position.y), Vector2(cap_w, rect.size.y)),
		Rect2(tw - src_cap, 0.0, src_cap, th))
	# 가운데
	var mid_w: float = rect.size.x - cap_w * 2.0
	if mid_w > 0.0:
		ci.draw_texture_rect_region(texture,
			Rect2(rect.position + Vector2(cap_w, 0.0), Vector2(mid_w, rect.size.y)),
			Rect2(src_cap, 0.0, maxf(1.0, tw - src_cap * 2.0), th))
