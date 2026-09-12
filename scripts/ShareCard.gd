class_name ShareCard
extends Node

## 공유 버튼이 보내는 점수 카드 한 장과, 그 옆에 붙는 문구.
##
## 게임 화면을 찍지 않고 카드를 따로 그린다. 게임오버 팝업을 그대로 찍으면
## PLAY AGAIN·HOME 버튼까지 같이 나가서, 받는 사람에게는 누를 수 없는 버튼이
## 박힌 스크린샷이 된다. 카드는 모드 선택 화면의 카드 색을 바탕으로 로고,
## 캐릭터, 모드 이름, 점수만 올린다.
##
## 화면에 붙이지 않은 SubViewport 에 한 번 그리고 그 결과를 Image 로 받는다.
## 헤드리스(더미 렌더러)에서는 빈 그림이 나오므로, 자리는 card_layout 이 따로
## 계산해 tools/check_share.gd 가 잴 수 있게 했다.
##
## 카드 색, 모드 이름, 로고 파일은 ModeSelectScreen 의 것을 그대로 쓴다. 여기에
## 한 벌 더 적어 두면 카드 색을 고치는 날 공유 카드만 옛 색으로 남는다.

const MSS := preload("res://scripts/ModeSelectScreen.gd")

# 4:5 세로. 인스타그램 피드가 자르지 않는 가장 긴 비율이고, 세로로 긴 만큼
# 정사각형보다 캐릭터와 점수를 크게 둘 수 있다.
const CARD_SIZE := Vector2i(1080, 1350)
# 모드 카드처럼 흰 테두리를 두른다.
const FRAME_INSET := 36.0
const FRAME_WIDTH := 18
const FRAME_RADIUS := 72
# 글자가 넘지 않을 폭. 테두리 안쪽(972px)보다 좁혀 양옆에 숨 쉴 틈을 둔다.
const CONTENT_WIDTH := 900.0

# 위에서부터 차례로 쌓는다. 맺음말만 아래끝에 붙인다.
const LOGO_TOP := 90.0
const LOGO_MAX := Vector2(820, 240)
const PILL_GAP := 30.0
const PILL_TEXT_SIZE := 54
const PILL_PAD := Vector2(40, 12)
const PILL_COLOR := Color(0.05, 0.07, 0.13, 0.30)   # 모드 카드 이름판처럼 옅은 어둠
const CHARACTER_GAP := 40.0
const CHARACTER_MAX := Vector2(560, 330)
const LABEL_GAP := 20.0
const LABEL_SIZE := 64
# 점수는 가능한 크게, 넘치면 CONTENT_WIDTH 에 맞을 때까지 줄인다. int 끝까지
# (2,147,483,647 — 13자)도 SCORE_MIN_SIZE 위에서 들어가는 것을 체커가 본다.
const SCORE_SIZE := 150
const SCORE_MIN_SIZE := 72
const FOOTER_BOTTOM := 100.0   # 카드 아래끝에서 맺음말 아래끝까지
const FOOTER_SIZE := 50
const OUTLINE_FRAC := 0.22     # 글자 크기 대비 외곽선 두께

const LABEL_SCORE := "SCORE"
const LABEL_NEW_BEST := "NEW BEST!"
const FOOTER_TEXT := "Can you beat me?"
# {score} 와 {mode} 는 이름으로 넣는다. 한국어는 모드가 먼저, 점수가 나중에
# 오는데 % 는 순서를 바꿀 수 없다.
const SHARE_TEXT := "I scored {score} in {mode} on QuizRun: Dual Gate! Can you beat me?"
const CHOOSER_TITLE := "Share your score"

var _bold: Font
var _heavy: Font


## 공유 창에 이미지와 함께 넘길 문구. 스토어 주소가 있으면 줄을 바꿔 붙인다.
func share_text(mode: int, score_value: int) -> String:
	var line: String = tr(SHARE_TEXT).format({
		"score": ScoreFormat.grouped(score_value),
		"mode": tr(MSS.CARD_NAMES[mode]),
	})
	if ExternalLinks.is_set(ExternalLinks.STORE_URL):
		line += "\n" + ExternalLinks.STORE_URL.strip_edges()
	return line


## 공유 창 맨 위에 뜨는 제목.
func chooser_title() -> String:
	return tr(CHOOSER_TITLE)


func logo_texture() -> Texture2D:
	var path: String = MSS.ART_DIR + MSS.TITLE_FILE
	if not ResourceLoader.exists(path):
		push_warning("share card: missing %s" % path)
		return null
	return load(path)


## 카드 위 조각들의 자리와 글자. 그리는 쪽과 체커가 같은 답을 보도록 계산은
## 여기 한 번만 있다.
func card_layout(mode: int, score_value: int, new_record: bool,
		logo: Texture2D, face: Texture2D) -> Dictionary:
	_ensure_fonts()
	var w := float(CARD_SIZE.x)
	var h := float(CARD_SIZE.y)
	var out := {}

	# 글자 줄은 카드 전체 폭이 아니라 가운데 CONTENT_WIDTH 에 둔다. 가운데
	# 정렬이라 그림은 같지만, 전체 폭으로 잡으면 사각형이 흰 테두리 밖까지
	# 걸쳐 "테두리 안에 있는가"를 잴 수 없다.
	var text_x: float = (w - CONTENT_WIDTH) * 0.5

	var y := LOGO_TOP
	var logo_size := _fit(logo, LOGO_MAX)
	out.logo = Rect2(Vector2((w - logo_size.x) * 0.5, y), logo_size)
	y = out.logo.end.y + PILL_GAP

	out.mode_name = tr(MSS.CARD_NAMES[mode])
	var pill_text_w: float = _bold.get_string_size(
		out.mode_name, HORIZONTAL_ALIGNMENT_LEFT, -1, PILL_TEXT_SIZE).x
	var pill_size := Vector2(pill_text_w + PILL_PAD.x * 2.0,
		_bold.get_height(PILL_TEXT_SIZE) + PILL_PAD.y * 2.0)
	out.pill = Rect2(Vector2((w - pill_size.x) * 0.5, y), pill_size)
	y = out.pill.end.y + CHARACTER_GAP

	var face_size := _fit(face, CHARACTER_MAX)
	out.character = Rect2(Vector2((w - face_size.x) * 0.5, y), face_size)
	y = out.character.end.y + LABEL_GAP

	out.label_text = tr(LABEL_NEW_BEST) if new_record else tr(LABEL_SCORE)
	out.label = Rect2(Vector2(text_x, y), Vector2(CONTENT_WIDTH, _heavy.get_height(LABEL_SIZE)))
	out.label_width = _heavy.get_string_size(
		out.label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	y = out.label.end.y

	out.digits = ScoreFormat.grouped(score_value)
	var size: int = SCORE_SIZE
	while size > SCORE_MIN_SIZE and _heavy.get_string_size(
			out.digits, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > CONTENT_WIDTH:
		size -= 2
	out.score_size = size
	out.score_width = _heavy.get_string_size(out.digits, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	out.score = Rect2(Vector2(text_x, y), Vector2(CONTENT_WIDTH, _heavy.get_height(size)))

	out.footer_text = tr(FOOTER_TEXT)
	var footer_h: float = _bold.get_height(FOOTER_SIZE)
	out.footer = Rect2(Vector2(text_x, h - FOOTER_BOTTOM - footer_h), Vector2(CONTENT_WIDTH, footer_h))
	out.footer_width = _bold.get_string_size(
		out.footer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE).x

	var inner: float = FRAME_INSET + FRAME_WIDTH
	out.frame_inner = Rect2(Vector2(inner, inner), Vector2(w - inner * 2.0, h - inner * 2.0))
	return out


## 카드를 그려 Image 로 돌려준다. 그리는 데 한 프레임이 걸린다. 렌더러가
## 없으면(헤드리스) null 이나 빈 이미지가 올 수 있다.
func render(mode: int, score_value: int, new_record: bool, face: Texture2D) -> Image:
	# 렌더러가 없으면 frame_post_draw 가 오지 않아 아래 await 가 영영 안 풀린다.
	# 헤드리스 체커에서 SHARE 를 눌렀다가 그대로 멈춘 적이 있다.
	if DisplayServer.get_name() == "headless":
		return null
	var logo := logo_texture()
	var lay := card_layout(mode, score_value, new_record, logo, face)

	var vp := SubViewport.new()
	vp.size = CARD_SIZE
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(CARD_SIZE)
	vp.add_child(root)

	_add_background(root, mode)
	_add_frame(root)
	if logo != null:
		_add_texture(root, logo, lay.logo)
	_add_pill(root, lay.pill)
	_add_label(root, lay.mode_name, lay.pill, _bold, PILL_TEXT_SIZE, Color.WHITE, Color.WHITE, 0)
	if face != null:
		_add_texture(root, face, lay.character)
	var label_fill: Color = MSS.CARD_BEST_COLOR if new_record else Color.WHITE
	var label_ring: Color = MSS.CARD_BEST_OUTLINE if new_record else PopupBase.INK
	_add_label(root, lay.label_text, lay.label, _heavy, LABEL_SIZE, label_fill, label_ring,
		_ring(LABEL_SIZE))
	_add_label(root, lay.digits, lay.score, _heavy, lay.score_size, Color.WHITE, PopupBase.INK,
		_ring(lay.score_size))
	_add_label(root, lay.footer_text, lay.footer, _bold, FOOTER_SIZE, Color.WHITE, PopupBase.INK,
		_ring(FOOTER_SIZE))

	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


func _ensure_fonts() -> void:
	if _heavy != null:
		return
	# 모드 선택 화면과 같은 두 굵기. 축은 문자열이 아니라 정수 태그로 건다 —
	# 문자열 키는 조용히 무시된다(ModeSelectScreen._load_fonts).
	var base: Font = AppFont.base()
	var wght: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	_bold = _weighted(base, wght, MSS.FONT_WEIGHT_BOLD)
	_heavy = _weighted(base, wght, MSS.FONT_WEIGHT_HEAVY)


func _weighted(base: Font, wght_tag: int, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {wght_tag: weight}
	return fv


func _ring(font_size: int) -> int:
	return maxi(1, int(round(font_size * OUTLINE_FRAC)))


# 비율을 지킨 채 상자 안에 들어가는 가장 큰 크기.
func _fit(tex: Texture2D, box: Vector2) -> Vector2:
	if tex == null or tex.get_width() <= 0 or tex.get_height() <= 0:
		return Vector2.ZERO
	var size := Vector2(tex.get_width(), tex.get_height())
	return size * minf(box.x / size.x, box.y / size.y)


func _add_background(parent: Control, mode: int) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, MSS.CARD_FILL_TOP[mode])
	gradient.set_color(1, MSS.CARD_FILL_BOTTOM[mode])
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.0, 0.0)
	fill.fill_to = Vector2(0.0, 1.0)
	fill.width = 4
	fill.height = 256
	var rect := TextureRect.new()
	rect.texture = fill
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(CARD_SIZE)
	parent.add_child(rect)


func _add_frame(parent: Control) -> void:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(FRAME_WIDTH)
	box.border_color = Color.WHITE
	box.set_corner_radius_all(FRAME_RADIUS)
	box.anti_aliasing = true
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.position = Vector2(FRAME_INSET, FRAME_INSET)
	panel.size = Vector2(CARD_SIZE) - Vector2(FRAME_INSET, FRAME_INSET) * 2.0
	parent.add_child(panel)


func _add_pill(parent: Control, rect: Rect2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = PILL_COLOR
	box.set_corner_radius_all(int(rect.size.y * 0.5))
	box.anti_aliasing = true
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.position = rect.position
	panel.size = rect.size
	parent.add_child(panel)


func _add_texture(parent: Control, tex: Texture2D, rect: Rect2) -> void:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = rect.position
	t.size = rect.size
	parent.add_child(t)


func _add_label(parent: Control, text: String, rect: Rect2, font: Font, font_size: int,
		fill: Color, ring_color: Color, ring: int) -> void:
	var settings := LabelSettings.new()
	settings.font = font
	settings.font_size = font_size
	settings.font_color = fill
	if ring > 0:
		settings.outline_size = ring
		settings.outline_color = ring_color
	var label := Label.new()
	# 글자는 이미 번역해서 넘긴다. 켜 두면 Label 이 한 번 더 tr() 을 건다.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.label_settings = settings
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	parent.add_child(label)
