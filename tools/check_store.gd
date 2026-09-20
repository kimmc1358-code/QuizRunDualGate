extends SceneTree

# 광고 제거 결제가 게임에 제대로 이어져 있는지 본다 — 플러그인 없이, Google Play
# 가 보낼 답을 대신 넣어서.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_store.gd
#
# 실제 결제는 Play 콘솔에 올린 빌드에서만 된다. 여기서는 Store 에 가짜
# BillingClient 를 끼우고 답을 흉내 내며 게임이 어떻게 반응하는지 본다.
#
#   결제 흐름: 연결되면 상품과 구매 내역을 묻는다. 상품 정보 전에는 결제 창을
#     열지 않는다. 취소와 대기는 아무것도 주지 않는다. 완료되면 구매 확인
#     (acknowledge)을 하고 광고를 없앤다 — 확인을 빠뜨리면 3일 뒤 자동 환불이다.
#   복원과 환불: 저장된 답은 다시 켜도 남는다. 조회 결과에 상품이 없으면 풀리고
#     (환불), 조회가 실패하면 그대로 둔다. "이미 산 상품"이면 내역을 다시 묻는다.
#   광고: 없앤 뒤에는 전면광고가 안 뜨고 카운터도 그대로, 배너는 자리까지 돌려주고,
#     부활은 보상형 광고 없이 곧장 이어 간다.
#   화면: 설정의 버튼은 "ADS REMOVED" 로 눌리지 않고, 모드 선택의 줄은 숨는다.
#   값: Store 가 옮겨 적은 열거형 값이 플러그인의 BillingClient 와 같다.
#
# 광고 상태를 세이브 파일에 적으므로 파일 전체를 받아 두었다가 끝에 되돌린다.

const SAVE_PATH := "user://savegame.cfg"
const FAKE_CLIENT := """extends Node
signal connected
signal disconnected
signal connect_error(code, message)
signal query_product_details_response(response)
signal query_purchases_response(response)
signal on_purchase_updated(response)
signal acknowledge_purchase_response(response)
var calls: Array = []
func start_connection(): calls.append("start")
func query_product_details(ids, _type): calls.append("details " + ",".join(ids))
func query_purchases(_type): calls.append("purchases")
func purchase(id, _a = "", _b = "", _c = false):
	calls.append("purchase " + id)
	return {"response_code": 0}
func acknowledge_purchase(token): calls.append("ack " + token)
"""
const FAKE_ADMOB := """extends Node
var calls: Array = []
func show_interstitial_ad(id): calls.append("show_interstitial " + id)
func show_rewarded_ad(id): calls.append("show_rewarded " + id)
func show_banner_ad(id): calls.append("show_banner " + id)
func hide_banner_ad(id): calls.append("hide_banner " + id)
func load_interstitial_ad(): calls.append("load_interstitial")
func load_rewarded_ad(): calls.append("load_rewarded")
func load_banner_ad(): calls.append("load_banner")
func get_banner_dimension_in_pixels(_id): return Vector2(1080, 150)
"""

var fails := 0
var _save_backup: PackedByteArray
var _had_save := false


func _init() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


func _expect(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("  ok    " + ok_msg)
	else:
		_fail(fail_msg)


func _fake(source: String) -> Node:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script.new()


func _purchase(state: int, acknowledged: bool, token: String) -> Dictionary:
	return {"product_ids": PackedStringArray([Store.REMOVE_ADS_PRODUCT_ID]), "purchase_state": state,
		"is_acknowledged": acknowledged, "purchase_token": token}


func _saved_removed() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return bool(cfg.get_value("ads", "removed", false))


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	# ---- 값: 옮겨 적은 열거형이 플러그인과 같은가 ----
	var client_script: Script = load(Store.BILLING_SCRIPT)
	if client_script == null:
		_fail("%s is missing" % Store.BILLING_SCRIPT)
	else:
		var enums: Dictionary = client_script.get_script_constant_map()
		for pair in [["BillingResponseCode", "OK", Store.RESPONSE_OK],
				["BillingResponseCode", "USER_CANCELED", Store.RESPONSE_USER_CANCELED],
				["BillingResponseCode", "ITEM_ALREADY_OWNED", Store.RESPONSE_ITEM_ALREADY_OWNED],
				["PurchaseState", "PURCHASED", Store.PURCHASE_STATE_PURCHASED],
				["PurchaseState", "PENDING", Store.PURCHASE_STATE_PENDING],
				["ProductType", "INAPP", Store.PRODUCT_TYPE_INAPP]]:
			var table: Dictionary = enums.get(pair[0], {})
			if not table.has(pair[1]) or int(table[pair[1]]) != int(pair[2]):
				_fail("Store's %s.%s is %d but BillingClient says %s" % [pair[0], pair[1], pair[2], table.get(pair[1], "nothing")])
		print("  ok    Store's copied enum values match BillingClient")

	var store = main.get("store")
	if store == null:
		_fail("Main has no Store")
		_finish()
		return
	_expect(not store.available, "PC: the store says it is unavailable", "the store claims to work on a PC")
	main.set("ads_removed", false)
	main.call("_on_remove_ads_pressed")
	_expect(not main.get("ads_removed"), "PC: pressing remove-ads grants nothing", "PC: remove-ads was granted for free")

	# ---- 결제 흐름 ----
	var client := _fake(FAKE_CLIENT)
	store.call("_attach", client)
	store.call("_on_connected")
	_expect(client.calls.has("details " + Store.REMOVE_ADS_PRODUCT_ID) and client.calls.has("purchases"),
		"on connect it asks for the product and the purchases", "on connect it asked for %s" % [client.calls])
	client.calls.clear()
	_expect(not store.buy() and not client.calls.has("purchase " + Store.REMOVE_ADS_PRODUCT_ID),
		"no purchase sheet before the product details arrive", "the sheet opened before the product was known")
	store.call("_on_product_details", {"response_code": 0, "product_details": [{"product_id": Store.REMOVE_ADS_PRODUCT_ID}]})
	_expect(store.buy() and client.calls.has("purchase " + Store.REMOVE_ADS_PRODUCT_ID),
		"then buy() opens the purchase sheet", "buy() did not open the sheet")

	store.call("_on_purchase_updated", {"response_code": Store.RESPONSE_USER_CANCELED})
	_expect(not main.get("ads_removed"), "cancelled -> nothing granted", "a cancelled purchase removed the ads")
	store.call("_on_purchase_updated", {"response_code": 0, "purchases": [_purchase(Store.PURCHASE_STATE_PENDING, false, "t0")]})
	_expect(not main.get("ads_removed") and not client.calls.has("ack t0"),
		"pending -> nothing granted, nothing acknowledged", "a pending purchase was granted or acknowledged")

	# 광고 쪽 가짜를 미리 끼워 둔다 — 없앤 뒤 광고가 안 뜨는지 보려면 광고가 뜰 수
	# 있는 상태여야 한다.
	var ads = main.get("ads")
	var admob := _fake(FAKE_ADMOB)
	ads.set("_admob", admob)
	ads.set("available", true)
	var screen = main.get("mode_select_panel")
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	screen.size = Vector2(width, width * 20.0 / 9.0)
	screen.call("_layout")
	main.call("_set_state", main.State.MODE_SELECT)
	ads.call("_on_banner_loaded", "b1")
	main.call("_apply_banner_height", 150.0, 1080.0)
	_expect(main.get("banner_reserved"), "before buying, 20:9 reserves the banner", "the banner had no room even before buying")

	admob.calls.clear()
	store.call("_on_purchase_updated", {"response_code": 0, "purchases": [_purchase(Store.PURCHASE_STATE_PURCHASED, false, "t1")]})
	_expect(main.get("ads_removed"), "purchased -> ads removed", "a completed purchase did not remove the ads")
	_expect(client.calls.has("ack t1"), "the purchase is acknowledged", "the purchase was never acknowledged — Google would refund it in 3 days")
	_expect(_saved_removed(), "the save file remembers it", "ads_removed was not written to the save")

	# ---- 광고가 정말 없는가 ----
	_expect(not main.get("banner_reserved") and float(screen.get("banner_reserve_px")) == 0.0,
		"the banner's space is given back", "the banner space is still reserved (%s)" % screen.get("banner_reserve_px"))
	# 배너는 같은 상태를 두 번 청하지 않으므로(Ads._apply_banner), 숨김 요청은
	# 산 순간에 한 번 나간다. 그 뒤로는 무엇을 해도 다시 보이면 안 된다.
	_expect(admob.calls.has("hide_banner b1") and not admob.calls.has("show_banner b1"),
		"buying hides the banner on mode select", "the banner was not hidden when the purchase came in (%s)" % [admob.calls])
	admob.calls.clear()
	main.call("_update_banner")
	_expect(not admob.calls.has("show_banner b1"), "and it stays hidden", "the banner showed again after buying")
	var every: int = main.get("interstitial_every_restarts")
	main.set("games_played_total", int(main.get("interstitial_free_games")) + 10)
	main.set("restarts_since_interstitial", every + 5)
	ads.set("_interstitial_id", "i1")
	var due: int = main.get("restarts_since_interstitial")
	var shown: bool = main.call("_ad_try_interstitial")
	_expect(not shown and not admob.calls.has("show_interstitial i1") and int(main.get("restarts_since_interstitial")) == due,
		"no interstitial, counter untouched", "an interstitial still fired after buying")
	main.set("run_revived", false)
	main.call("_offer_revive")
	ads.set("_rewarded_id", "r1")
	main.call("_on_revive_watch_ad")
	_expect(main.get("run_revived") and not admob.calls.has("show_rewarded r1"),
		"revive continues at once, no rewarded ad", "the revive still went through a rewarded ad")

	# ---- 화면 ----
	var settings = main.get("settings_popup")
	settings.call("ensure_built")
	var button: Button = settings.get("_remove_ads")
	var caption: Label = button.get_node("Caption") if button != null else null
	_expect(button != null and button.disabled and caption != null and caption.text == settings.tr("ADS REMOVED"),
		"settings shows a disabled ADS REMOVED", "settings button: disabled=%s text=%s" % [
			button.disabled if button != null else "?", caption.text if caption != null else "?"])
	var link: Button = screen.get("_remove_ads")
	_expect(link != null and not link.visible, "mode select hides its remove-ads line", "the mode select line is still showing")
	var revive = main.get("revive_panel")
	revive.call("ensure_built")
	var ad_button: Button = revive.get("_ad_button")
	var ad_caption: Label = ad_button.get_node("Caption") if ad_button != null else null
	var ad_icon: TextureRect = ad_button.get_node("Icon") if ad_button != null else null
	_expect(ad_caption != null and ad_caption.text == revive.tr("CONTINUE") and ad_icon != null and ad_icon.texture == null,
		"the revive button reads CONTINUE with no ad icon", "revive button: '%s' icon=%s" % [
			ad_caption.text if ad_caption != null else "?", ad_icon.texture if ad_icon != null else "?"])

	# ---- 다시 켜기, 조회 실패, 환불, 이미 산 상품 ----
	main.set("ads_removed", false)
	main.call("_load_ad_state")
	_expect(main.get("ads_removed"), "a relaunch reads it back from the save", "the relaunch forgot the purchase")
	store.call("_on_purchases_queried", {"response_code": 12, "debug_message": "offline"})
	_expect(main.get("ads_removed"), "a failed purchase query changes nothing", "going offline brought the ads back")
	client.calls.clear()
	store.call("_on_purchases_queried", {"response_code": 0, "purchases": [_purchase(Store.PURCHASE_STATE_PURCHASED, false, "t2")]})
	_expect(main.get("ads_removed") and client.calls.has("ack t2"),
		"a query that finds it unacknowledged acknowledges it again", "an unacknowledged purchase from the query was left alone")
	store.call("_on_purchases_queried", {"response_code": 0, "purchases": []})
	_expect(not main.get("ads_removed") and not _saved_removed(), "refunded (gone from the query) -> ads come back",
		"a refund left the ads removed")
	_expect(main.get("banner_reserved"), "and the banner gets its space again", "the banner did not come back after a refund")
	_expect(link.visible, "and the mode select line shows again", "the mode select line stayed hidden after a refund")
	client.calls.clear()
	store.call("_on_purchase_updated", {"response_code": Store.RESPONSE_ITEM_ALREADY_OWNED})
	_expect(client.calls.has("purchases"), "'already owned' asks for the purchases again", "'already owned' did nothing")

	screen.call("set_banner_reserve", 0.0)
	_finish()


func _finish() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("")
	if fails == 0:
		print("check_store: ok")
		quit(0)
	else:
		print("check_store: %d failure(s)" % fails)
		quit(1)
