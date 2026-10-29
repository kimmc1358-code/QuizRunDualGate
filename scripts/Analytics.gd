class_name Analytics
extends Node

## Firebase Analytics 와 게임 사이. 게임은 이 노드만 부르고, 플러그인
## (addons/godotx_firebase) 이름은 여기서만 나온다.
##
## Ads.gd · PlayGames.gd 와 같은 이유로 감싼다. 플러그인 싱글턴은 안드로이드에만
## 있어서, 그대로 부르면 PC 와 체커에서 매 호출이 오류가 된다. 여기서는 없으면
## available 을 false 로 두고 모든 기록을 조용히 버린다.
##
## ---- 수집은 꺼진 채로 시작한다 ----
##
## 내보내기 설정의 firebase/privacy_safe_defaults 가 매니페스트에 "수집 꺼짐, 동의
## 신호 전부 거부"를 심는다. 그래서 이 노드가 켜기 전에는 first_open 같은 자동
## 이벤트도 나가지 않는다.
##
## 켜는 것은 Google UMP 가 "동의 필요 없음"(NOT_REQUIRED)이라고 답했을 때뿐이다 —
## 한국을 비롯한 유럽 밖이다. 유럽은 끈 채로 둔다. UMP 의 OBTAINED 는 "답을 받았다"
## 이지 "분석에 동의했다"가 아니어서, 그걸로 켜면 거절한 사람까지 수집하게 된다.
## 동의를 묻지 못한 날(오프라인)도 지역을 모르니 끈다. 광고와 반대다 — 광고는 막으면
## 부활이 사라지지만, 분석은 하루 빠져도 잃는 것이 통계 한 줄이다.

const CORE_SINGLETON := "GodotxFirebaseCore"
const ANALYTICS_SINGLETON := "GodotxFirebaseAnalytics"
## 분석 화면에 남는 모드 이름. Mode 순서와 같다 — 번역되지 않는 고정 이름이라야
## 언어를 바꿔도 같은 모드가 한 줄로 모인다.
const MODE_NAMES := ["flags", "math", "colors", "mix"]

var available: bool = false
## 지금 실제로 수집 중인가. 체커가 이걸로 동의 처리를 본다.
var collecting: bool = false
var _core: Object
var _analytics: Object
var _initialized: bool = false
var _consent := "UNKNOWN"
var _applied: bool = false


## 안드로이드에서만 플러그인을 깨운다. Core 가 먼저 뜨고, 그다음 Analytics 다.
func start() -> void:
	if not OS.has_feature("android"):
		return
	if not Engine.has_singleton(CORE_SINGLETON) or not Engine.has_singleton(ANALYTICS_SINGLETON):
		push_warning("analytics: Firebase singletons not found — was godotx_firebase exported with Core and Analytics on?")
		return
	_core = Engine.get_singleton(CORE_SINGLETON)
	_analytics = Engine.get_singleton(ANALYTICS_SINGLETON)
	_core.connect("core_initialized", _on_core_initialized)
	_analytics.connect("analytics_initialized", _on_analytics_initialized)
	available = true
	_core.call("initialize")


func _on_core_initialized(ok: bool) -> void:
	if ok:
		_analytics.call("initialize")
	else:
		push_warning("analytics: Firebase Core failed to initialize")


func _on_analytics_initialized(ok: bool) -> void:
	_initialized = ok
	print("[분석] Firebase Analytics 준비 %s" % ("됨" if ok else "실패"))
	_apply_consent()


## Ads 가 Google UMP 에서 동의 상태를 새로 읽을 때마다 넘겨준다.
func set_consent_status(status: String) -> void:
	_consent = status
	_apply_consent()


func _apply_consent() -> void:
	if not available or not _initialized:
		return
	var allow: bool = _consent == "NOT_REQUIRED"
	if _applied and allow == collecting:
		return
	_applied = true
	collecting = allow
	var state := "granted" if allow else "denied"
	_analytics.call("set_consent", {
		"analytics_storage": state,
		"ad_storage": state,
		"ad_user_data": state,
		"ad_personalization": state,
	})
	_analytics.call("set_analytics_collection_enabled", allow)
	print("[분석] 수집 %s (동의 상태: %s)" % ["켬" if allow else "끔", _consent])


## 이벤트 하나. 수집이 꺼져 있으면 버린다 — 쌓아 두었다가 나중에 보내면 동의하지
## 않은 시간의 행동까지 나가게 된다.
func log_event(event_name: String, params: Dictionary = {}) -> void:
	if not collecting:
		return
	_analytics.call("log_event", event_name, params)


static func mode_name(mode: int) -> String:
	return MODE_NAMES[mode] if mode >= 0 and mode < MODE_NAMES.size() else "unknown"
