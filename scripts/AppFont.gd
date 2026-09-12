class_name AppFont
extends RefCounted

## 이 게임이 쓰는 글꼴을 잡는 한 곳.
##
## Fredoka 한 벌로 시작했는데 한글 글리프가 없다. 없는 글리프는 Godot 이 기기의
## 시스템 폰트에서 끌어다 쓰므로 글자가 사라지지는 않지만, 그 폰트가 무엇인지는
## 기기마다 다르고 대개 Fredoka 의 둥근 라틴 옆에 밋밋한 고딕이 앉는다. 한글
## 폰트를 fallback 으로 붙여 두면 어느 기기에서나 같은 얼굴이 나온다.
##
## fallback 은 '기본' 폰트 한 벌에만 걸면 된다. 이 프로젝트는 굵기를
## FontVariation 으로 만드는데(_weighted), FontVariation 은 굵기만 바꾸고 글리프는
## base_font 에서 찾으므로 굵기마다 따로 걸 필요가 없다.
##
## 네 화면이 각자 load() 하던 것을 여기로 모았다. 따로 불러 두면 fallback 을
## 붙이는 곳도 넷이 되고, 그중 하나를 빠뜨리면 그 화면에서만 한글이 다른
## 폰트로 나온다 — 화면을 나란히 놓고 보기 전에는 알기 어려운 종류다.

const BASE_PATH := "res://assets/fonts/Fredoka.ttf"
## 한글용 — 카페24 써라운드. 없으면 시스템 폰트로 대체되므로 글자가 깨지지는
## 않는다.
##
## 받은 파일 이름 그대로 두어도 되도록 몇 가지를 훑는다. 배포처에 따라
## 버전이 파일 이름에 붙어 오는데, 그것 때문에 "왜 한글이 안 바뀌지"로
## 시간을 쓰게 하고 싶지 않다.
const KOREAN_CANDIDATES := [
	"res://assets/fonts/Cafe24Ssurround-v2.0.otf",
	"res://assets/fonts/Cafe24Ssurround.otf",
	"res://assets/fonts/Cafe24Ssurround-v2.0.ttf",
	"res://assets/fonts/Cafe24Ssurround.ttf",
]

static var _base: Font = null
static var _warned := false


## 라틴은 Fredoka, 한글은 KOREAN_PATH. 한 번만 만들고 다시 쓴다.
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
