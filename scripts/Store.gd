class_name Store
extends Node

## Google Play 결제와 게임 사이. 지금 파는 것은 "광고 제거" 하나다.
##
## PlayGames.gd, Ads.gd 와 같은 이유로 감싼다. 플러그인의 BillingClient 는
## 싱글턴이 없으면 모든 호출을 조용히 삼키고 아무 신호도 보내지 않는다 — PC 에서
## 버튼이 영영 답을 기다리지 않도록 "쓸 수 없음"을 기록해 두고, 결제를 청하면
## 즉시 false 로 답한다. 플러그인 스크립트는 경로로 읽어 addons 가 빠져도 게임이
## 파싱된다.
##
## 소유 여부는 Google Play 가 정한다. 연결될 때와 앱으로 돌아올 때마다 구매
## 내역을 다시 묻고, 그 답으로 ownership_changed 를 보낸다. 환불되면 내역에서
## 빠지므로 광고 제거도 풀린다. 조회가 실패했을 때는 아무것도 바꾸지 않는다 —
## 인터넷이 끊겼다고 산 사람의 광고가 되살아나면 안 된다.
##
## 한 번 사는 상품은 구매 확인(acknowledge)을 해야 한다. 안 하면 Google 이 3일
## 뒤 자동으로 환불한다. 확인이 실패해도 다음 조회에서 is_acknowledged 가
## false 로 다시 오므로 그때 또 한다.
##
## 결제는 Play 콘솔에 올린 빌드가 있어야 동작한다. 결제 플러그인이 든 빌드를
## 테스트 트랙에 한 번 올리고, 상품을 활성화하고, 폰의 계정을 라이선스
## 테스터에 넣기 전까지는 상품 조회가 실패하고 결제 창이 열리지 않는다.

signal ownership_changed(owns_remove_ads: bool)

const BILLING_SCRIPT := "res://addons/GodotGooglePlayBilling/BillingClient.gd"
const SINGLETON := "GodotGooglePlayBilling"
## Play 콘솔의 인앱 상품 ID 와 글자 하나까지 같아야 한다. 만든 뒤에는 바꿀 수 없다.
const REMOVE_ADS_PRODUCT_ID := "remove_ads"
# 연결이 끊긴 뒤 다시 잇기까지.
const RETRY_SECONDS := 30.0

# BillingClient 의 열거형 값. 플러그인 스크립트를 이름으로 부르지 않으려고
# 옮겨 적었고, tools/check_store.gd 가 플러그인의 값과 같은지 본다.
const RESPONSE_OK := 0
const RESPONSE_USER_CANCELED := 1
const RESPONSE_ITEM_ALREADY_OWNED := 7
const PURCHASE_STATE_PURCHASED := 1
const PURCHASE_STATE_PENDING := 2
const PRODUCT_TYPE_INAPP := 0

var available: bool = false
var _client: Object
var _connected: bool = false
var _product_ready: bool = false


## 안드로이드에서만 결제에 연결한다. 다른 곳에서는 available 이 false 로 남는다.
func start() -> void:
	if not OS.has_feature("android"):
		return
	if not Engine.has_singleton(SINGLETON):
		push_warning("store: %s singleton not found — was the plugin exported?" % SINGLETON)
		return
	var script: Script = load(BILLING_SCRIPT)
	if script == null:
		push_warning("store: %s is missing — no purchases this run" % BILLING_SCRIPT)
		return
	var client: Node = script.new()
	add_child(client)
	_attach(client)
	print("[결제] Google Play 결제에 연결한다")
	_client.call("start_connection")


# 플러그인(또는 체커의 가짜)을 붙인다. 체커가 같은 길로 들어오도록 start 에서
# 떼어 두었다.
func _attach(client: Object) -> void:
	_client = client
	available = true
	client.connect("connected", _on_connected)
	client.connect("disconnected", _on_disconnected)
	client.connect("connect_error", _on_connect_error)
	client.connect("query_product_details_response", _on_product_details)
	client.connect("query_purchases_response", _on_purchases_queried)
	client.connect("on_purchase_updated", _on_purchase_updated)
	client.connect("acknowledge_purchase_response", _on_acknowledged)


## 광고 제거 결제 창을 연다. 열었으면 true 이고, 결과는 ownership_changed 로
## 온다. 연결 전이거나 상품 정보를 아직 못 받았으면 false.
func buy() -> bool:
	if not available or not _connected:
		return false
	if not _product_ready:
		# 상품 정보를 먼저 받아야 결제 창을 열 수 있다(플러그인의 규칙). 다시
		# 청해 두고 이번에는 못 연다고 답한다.
		_query_product()
		return false
	var result: Dictionary = _client.call("purchase", REMOVE_ADS_PRODUCT_ID)
	var code := int(result.get("response_code", -1))
	if code != RESPONSE_OK:
		push_warning("store: could not open the purchase sheet (%d) %s" % [code, result.get("debug_message", "")])
		return false
	return true


## 구매 내역을 다시 묻는다. 답은 ownership_changed 로 온다.
func refresh() -> void:
	if available and _connected:
		_client.call("query_purchases", PRODUCT_TYPE_INAPP)


# 앱 밖에서 일이 생길 수 있다 — Play 스토어에서 환불받거나, 대기 중이던 결제가
# 끝나거나. 돌아올 때마다 다시 묻는다.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		refresh()


func _query_product() -> void:
	_client.call("query_product_details", PackedStringArray([REMOVE_ADS_PRODUCT_ID]), PRODUCT_TYPE_INAPP)


func _on_connected() -> void:
	_connected = true
	print("[결제] 연결됨 — 상품과 구매 내역을 묻는다")
	_query_product()
	refresh()


func _on_disconnected() -> void:
	_connected = false
	_schedule_reconnect()


func _on_connect_error(code: int, message: String) -> void:
	_connected = false
	push_warning("store: could not connect to Google Play billing (%d) %s" % [code, message])
	_schedule_reconnect()


func _schedule_reconnect() -> void:
	if is_inside_tree():
		get_tree().create_timer(RETRY_SECONDS).timeout.connect(_reconnect, CONNECT_ONE_SHOT)


func _reconnect() -> void:
	if available and not _connected:
		_client.call("start_connection")


func _on_product_details(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code != RESPONSE_OK:
		push_warning("store: product query failed (%d) %s — is %s active in Play Console?" % [
			code, response.get("debug_message", ""), REMOVE_ADS_PRODUCT_ID])
		return
	var details: Array = response.get("product_details", [])
	_product_ready = not details.is_empty()
	if _product_ready:
		print("[결제] 상품 %s 확인됨" % REMOVE_ADS_PRODUCT_ID)
	else:
		push_warning("store: Play knows no product %s — create and activate it in Play Console" % REMOVE_ADS_PRODUCT_ID)


func _on_purchases_queried(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code != RESPONSE_OK:
		push_warning("store: purchase query failed (%d) %s — keeping what we had" % [
			code, response.get("debug_message", "")])
		return
	var owned := false
	for purchase in response.get("purchases", []):
		if _is_remove_ads(purchase) and int(purchase.get("purchase_state", 0)) == PURCHASE_STATE_PURCHASED:
			owned = true
			_acknowledge_if_needed(purchase)
	ownership_changed.emit(owned)


func _on_purchase_updated(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code == RESPONSE_OK:
		for purchase in response.get("purchases", []):
			if not _is_remove_ads(purchase):
				continue
			var state := int(purchase.get("purchase_state", 0))
			if state == PURCHASE_STATE_PURCHASED:
				_acknowledge_if_needed(purchase)
				print("[결제] 광고 제거 구매 완료")
				ownership_changed.emit(true)
			elif state == PURCHASE_STATE_PENDING:
				# 편의점 결제처럼 나중에 끝나는 결제. 끝나기 전에는 주지 않는다 —
				# 끝나면 같은 신호가 PURCHASED 로 다시 온다.
				print("[결제] 결제 대기 중 — 끝나면 다시 알려 온다")
	elif code == RESPONSE_USER_CANCELED:
		print("[결제] 결제를 취소했다")
	elif code == RESPONSE_ITEM_ALREADY_OWNED:
		# 다른 기기에서 샀거나, 이 기기의 저장이 지워졌다. 내역을 다시 받아 되살린다.
		print("[결제] 이미 산 상품 — 구매 내역을 다시 묻는다")
		refresh()
	else:
		push_warning("store: purchase failed (%d) %s" % [code, response.get("debug_message", "")])


func _acknowledge_if_needed(purchase: Dictionary) -> void:
	if bool(purchase.get("is_acknowledged", false)):
		return
	_client.call("acknowledge_purchase", str(purchase.get("purchase_token", "")))


func _on_acknowledged(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code != RESPONSE_OK:
		push_warning("store: acknowledging the purchase failed (%d) — retried on the next purchase query" % code)


func _is_remove_ads(purchase: Dictionary) -> bool:
	return REMOVE_ADS_PRODUCT_ID in Array(purchase.get("product_ids", []))
