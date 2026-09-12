class_name Ads
extends Node

## AdMob 과 게임 사이. 게임은 이 노드만 부르고, 플러그인(addons/AdmobPlugin)의
## 이름은 여기서만 나온다.
##
## PlayGames.gd 와 같은 이유로 감싼다. 플러그인의 호출은 안드로이드 싱글턴이
## 없으면 로그만 남기고 아무 신호도 보내지 않는다 — 그대로 이으면 PC 에서 광고
## 버튼이 영영 답을 기다린다. 그래서 "쓸 수 없음"을 기록해 두고, 광고를 청하면
## 즉시 "없다"고 답한다. 플러그인 스크립트는 경로로 읽어 addons 가 빠져도 게임이
## 파싱된다.
##
## ---- 실제 광고가 새지 않게 ----
##
## 광고 단위 ID 는 AdIds 에서만 온다. 테스트 모드(AdIds.use_test_ads)면
## is_real 을 끄고 Google 데모 단위를 쓰며, 실제 칸(android_real_*)은 비워 둔다
## — 누가 is_real 을 켜도 빈 단위라 아무것도 불러오지 못한다. 플러그인은
## 노드의 _ready 에서 단위를 고르므로 값은 add_child 전에 다 넣는다.
##
## 앱 ID 는 여기가 아니라 addons/AdmobPlugin/android_export.cfg 가 빌드 때
## 매니페스트에 넣는다. tools/check_ad_ids.gd 가 둘 다 AdIds 와 맞춰 본다.

signal fullscreen_changed(showing: bool)
## 배너가 준비됐을 때. 높이는 기기 픽셀이다 — 게임 좌표로 바꾸는 것은 받는 쪽.
signal banner_ready(height_device_px: float)

const ADMOB_SCRIPT := "res://addons/AdmobPlugin/Admob.gd"
const LOAD_AD_REQUEST_SCRIPT := "res://addons/AdmobPlugin/model/LoadAdRequest.gd"
const SINGLETON := "AdmobPlugin"
# 불러오기에 실패한 뒤 다시 청하기까지. 인터넷이 끊긴 채 몇 초마다 두드리면
# 요청만 쌓이고, 광고 재고가 없는 날은 오래 기다려도 같다.
const RETRY_SECONDS := 30.0

## show_rewarded 가 done 에 넘기는 결과.
enum Reward { EARNED, SKIPPED, FAILED }

var available: bool = false
var _admob: Object
var _interstitial_id := ""
var _rewarded_id := ""
var _banner_id := ""
var _banner_wanted: bool = false
var _showing: bool = false
var _reward_done: Callable
var _reward_earned: bool = false
var _interstitial_done: Callable


## 안드로이드에서만 플러그인을 띄운다. 다른 곳에서는 available 이 false 로 남는다.
func start() -> void:
	if not OS.has_feature("android"):
		return
	if not Engine.has_singleton(SINGLETON):
		# 안드로이드인데 플러그인이 없다 — 빌드에 AdmobPlugin 이 안 들어간 것이다.
		push_warning("ads: %s singleton not found — was the plugin exported?" % SINGLETON)
		return
	# 성공 쪽도 한 줄씩 남긴다. 광고가 안 뜰 때 logcat 에서 어디까지 갔는지
	# 보려면 실패만 찍어서는 모자란다 — 아무 줄도 없으면 시작조차 안 한 것인지
	# 알 수 없다.
	print("[광고] AdMob 시작 (테스트 광고: %s)" % AdIds.use_test_ads())
	var script: Script = load(ADMOB_SCRIPT)
	if script == null:
		push_warning("ads: %s is missing — no ads this run" % ADMOB_SCRIPT)
		return
	var node: Node = make_admob_node(script)
	_admob = node
	add_child(node)
	available = true
	_connect()
	_admob.call("initialize")


## 플러그인 노드를 만들어 광고 단위를 채운다(트리에는 안 넣는다). 체커가 같은
## 함수로 만든 노드를 들여다본다.
func make_admob_node(script: Script) -> Node:
	var node: Node = script.new()
	var live: bool = not AdIds.use_test_ads()
	node.set("is_real", live)
	node.set("android_debug_application_id", AdIds.TEST_APP_ID)
	node.set("android_debug_banner_id", AdIds.TEST_BANNER)
	node.set("android_debug_interstitial_id", AdIds.TEST_INTERSTITIAL)
	node.set("android_debug_rewarded_id", AdIds.TEST_REWARDED)
	node.set("android_real_application_id", AdIds.LIVE_APP_ID.strip_edges() if live else "")
	node.set("android_real_banner_id", AdIds.LIVE_BANNER.strip_edges() if live else "")
	node.set("android_real_interstitial_id", AdIds.LIVE_INTERSTITIAL.strip_edges() if live else "")
	node.set("android_real_rewarded_id", AdIds.LIVE_REWARDED.strip_edges() if live else "")
	# 안 쓰는 형식은 비운다. 플러그인은 데모 단위를 기본값으로 채워 두는데,
	# 쓰지도 않을 단위가 남아 있으면 "무엇이 나갈 수 있는가"를 볼 때 헷갈린다.
	for format in ["rewarded_interstitial", "app_open", "native"]:
		node.set("android_debug_%s_id" % format, "")
		node.set("android_real_%s_id" % format, "")
	# 전면광고는 한 번 보여 준 것을 다시 못 쓴다. 기본값(false)이면 캐시에 남는다.
	node.set("remove_interstitial_ads_after_displayed", true)
	node.set("remove_rewarded_ads_after_displayed", true)
	var request_script: Script = load(LOAD_AD_REQUEST_SCRIPT)
	if request_script != null:
		var positions: Dictionary = request_script.get_script_constant_map().get("AdPosition", {})
		if positions.has("BOTTOM"):
			node.set("banner_position", positions["BOTTOM"])
	return node


## 전면광고를 띄운다. 준비된 것이 없으면 false 를 돌려주고 done 은 부르지
## 않는다. 띄웠으면 닫힌 뒤 done(shown) 이 한 번 불린다 — shown 이 false 면
## 띄우려다 실패한 것이다.
func show_interstitial(done: Callable) -> bool:
	if not available or _showing or _interstitial_id.is_empty():
		return false
	_interstitial_done = done
	var id := _interstitial_id
	_interstitial_id = ""
	_admob.call("show_interstitial_ad", id)
	return true


## 보상형 광고를 띄운다. 준비된 것이 없으면 false. 띄웠으면 닫힌 뒤
## done(Reward) 이 한 번 불린다 — 끝까지 봤는지(EARNED), 중간에 닫았는지
## (SKIPPED), 띄우지 못했는지(FAILED).
func show_rewarded(done: Callable) -> bool:
	if not available or _showing or _rewarded_id.is_empty():
		return false
	_reward_done = done
	_reward_earned = false
	var id := _rewarded_id
	_rewarded_id = ""
	_admob.call("show_rewarded_ad", id)
	return true


## 배너를 보일지. 아직 안 불러왔으면 기억해 두었다가 불러오는 대로 따른다.
func set_banner_visible(wanted: bool) -> void:
	_banner_wanted = wanted
	_apply_banner()


func _connect() -> void:
	_admob.connect("initialization_completed", func(_status): _on_initialized())
	_admob.connect("interstitial_ad_loaded", func(info, _response): _on_interstitial_loaded(info.get_ad_id()))
	_admob.connect("interstitial_ad_failed_to_load", func(_info, error): _retry(_load_interstitial, "interstitial", error))
	_admob.connect("interstitial_ad_showed_full_screen_content", func(_info): _set_showing(true))
	_admob.connect("interstitial_ad_failed_to_show_full_screen_content", func(_info, _error): _on_interstitial_finished(false))
	_admob.connect("interstitial_ad_dismissed_full_screen_content", func(_info): _on_interstitial_finished(true))
	_admob.connect("rewarded_ad_loaded", func(info, _response): _on_rewarded_loaded(info.get_ad_id()))
	_admob.connect("rewarded_ad_failed_to_load", func(_info, error): _retry(_load_rewarded, "rewarded", error))
	_admob.connect("rewarded_ad_showed_full_screen_content", func(_info): _set_showing(true))
	_admob.connect("rewarded_ad_user_earned_reward", func(_info, _reward): _reward_earned = true)
	_admob.connect("rewarded_ad_failed_to_show_full_screen_content", func(_info, _error): _on_rewarded_finished(false))
	_admob.connect("rewarded_ad_dismissed_full_screen_content", func(_info): _on_rewarded_finished(true))
	_admob.connect("banner_ad_loaded", func(info, _response): _on_banner_loaded(info.get_ad_id()))
	_admob.connect("banner_ad_failed_to_load", func(_info, error): _retry(_load_banner, "banner", error))


func _on_initialized() -> void:
	print("[광고] 초기화 완료 — 전면, 보상형, 배너를 불러온다")
	_load_all()


func _on_interstitial_loaded(id: String) -> void:
	_interstitial_id = id
	print("[광고] 전면광고 준비됨")


func _on_rewarded_loaded(id: String) -> void:
	_rewarded_id = id
	print("[광고] 보상형 광고 준비됨")


func _load_all() -> void:
	_load_interstitial()
	_load_rewarded()
	_load_banner()


func _load_interstitial() -> void:
	_admob.call("load_interstitial_ad")


func _load_rewarded() -> void:
	_admob.call("load_rewarded_ad")


func _load_banner() -> void:
	_admob.call("load_banner_ad")


func _retry(what: Callable, label: String, error: Object) -> void:
	var message := ""
	if error != null and error.has_method("get_message"):
		message = str(error.call("get_message"))
	push_warning("ads: %s failed to load%s — retrying in %ds" % [
		label, "" if message.is_empty() else " (%s)" % message, int(RETRY_SECONDS)])
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(what, CONNECT_ONE_SHOT)


func _set_showing(showing: bool) -> void:
	if _showing == showing:
		return
	_showing = showing
	fullscreen_changed.emit(showing)


func _on_interstitial_finished(shown: bool) -> void:
	_set_showing(false)
	var done := _interstitial_done
	_interstitial_done = Callable()
	_load_interstitial()
	if done.is_valid():
		done.call(shown)


func _on_rewarded_finished(shown: bool) -> void:
	_set_showing(false)
	var done := _reward_done
	_reward_done = Callable()
	var result: int = Reward.FAILED
	if shown:
		result = Reward.EARNED if _reward_earned else Reward.SKIPPED
	_reward_earned = false
	_load_rewarded()
	if done.is_valid():
		done.call(result)


func _on_banner_loaded(id: String) -> void:
	_banner_id = id
	var size: Vector2 = _admob.call("get_banner_dimension_in_pixels", id)
	print("[광고] 배너 준비됨 (%.0fx%.0f 기기 px)" % [size.x, size.y])
	banner_ready.emit(size.y)
	_apply_banner()


func _apply_banner() -> void:
	if not available or _banner_id.is_empty():
		return
	if _banner_wanted:
		_admob.call("show_banner_ad", _banner_id)
	else:
		_admob.call("hide_banner_ad", _banner_id)
