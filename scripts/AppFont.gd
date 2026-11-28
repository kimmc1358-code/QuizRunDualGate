class_name AppFont
extends RefCounted

## 이 게임이 쓰는 글꼴을 잡는 한 곳.
##
## 라틴과 숫자는 Oxanium, 한글은 Do Hyeon(2026-11-28, 주인이 골랐다). 둘 다 SIL
## OFL 이고 licenses/ 에 사용 허락서가 있다. 제목과 버튼의 Zen Dots(TitleArt)와
## 같은 결 — 네모지고 기하학적인 SF 글꼴 — 이라 고른 것이다. 그 전의 Fredoka 와
## Cafe24 Ssurround 는 둘 다 둥글고 말랑해서 Zen Dots 옆에서 따로 놀았다. 실제
## 팝업에 Oxanium + Orbit, Oxanium + Do Hyeon 을 나란히 끼워 보고 골랐다: Orbit 은
## 굵기가 하나(400)뿐이라 한글 버튼과 "신기록!" 에서 힘이 빠졌다.
##
## Oxanium 은 wght 축(200-800)이 있는 가변 글꼴이라 굵기는 화면마다
## FontVariation 으로 만든다(_weighted). Do Hyeon 은 굵기가 하나다.
##
## 한글은 Oxanium 에 없으므로 fallback 으로 붙인다. 붙이지 않으면 Godot 이 기기의
## 시스템 폰트에서 끌어다 쓰는데, 그것이 무엇인지는 기기마다 다르고 대개 밋밋한
## 고딕이다. fallback 은 '기본' 폰트 한 벌에만 걸면 된다. FontVariation 은 굵기만
## 바꾸고 글리프는 base_font 에서 찾으므로 굵기마다 따로 걸 필요가 없다.
##
## 네 화면이 각자 load() 하던 것을 여기로 모았다. 따로 불러 두면 fallback 을
## 붙이는 곳도 넷이 되고, 그중 하나를 빠뜨리면 그 화면에서만 한글이 다른
## 폰트로 나온다 — 화면을 나란히 놓고 보기 전에는 알기 어려운 종류다.

const BASE_PATH := "res://assets/fonts/Oxanium.ttf"
## 한글용 — Do Hyeon. 없으면 시스템 폰트로 대체되므로 글자가 깨지지는 않는다.
const KOREAN_CANDIDATES := [
	"res://assets/fonts/DoHyeon-Regular.ttf",
]

static var _base: Font = null
static var _warned := false


## 라틴은 Oxanium, 한글은 KOREAN_CANDIDATES. 한 번만 만들고 다시 쓴다.
static func base() -> Font:
	if _base != null:
		return _base
	if not ResourceLoader.exists(BASE_PATH):
		push_warning("AppFont: %s 가 없다 — 기본 글꼴로 그린다" % BASE_PATH)
		_base = ThemeDB.fallback_font
		return _base
	var font: Font = load(BASE_PATH)
	var korean_path: String = _korean_path()
	if korean_path != "":
		# 한 벌 더 얹는다. 이미 붙어 있으면 그대로 둔다 — base() 는 여러 번
		# 불릴 수 있고, 같은 폰트를 계속 덧붙이면 글리프를 찾을 때마다 없는
		# 목록을 길게 훑는다.
		var korean: Font = load(korean_path)
		if not font.fallbacks.has(korean):
			var chain: Array[Font] = font.fallbacks.duplicate()
			chain.append(korean)
			font.fallbacks = chain
	elif not _warned:
		# 한 번만 말한다. 매 화면마다 같은 경고를 쌓아 봐야 읽히지 않는다.
		_warned = true
		push_warning("AppFont: 한글 폰트가 없어 기기 시스템 폰트로 그린다 — %s 중 하나를 넣을 것"
			% ", ".join(KOREAN_CANDIDATES))
	_base = font
	return _base


## 넣어 둔 한글 폰트의 경로. 없으면 빈 문자열.
static func _korean_path() -> String:
	for path in KOREAN_CANDIDATES:
		if ResourceLoader.exists(path):
			return path
	return ""
