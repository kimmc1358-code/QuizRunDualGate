extends SceneTree

# 광고가 게임에 제대로 이어져 있는지 본다 — 플러그인 없이, 플러그인이 보낼
# 결과를 대신 넣어서.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ads_wiring.gd
#
# 실제 광고는 폰에서만 뜬다. 여기서는 Ads 에 가짜 AdMob 을 끼우고, 광고가
# 준비됐다/닫혔다/보상을 줬다를 차례로 흉내 내며 Main 이 어떻게 반응하는지 본다.
#
#   리워드 광고(결과 화면의 x2): 끝까지 보면 이번 판의 스타더스트를 한 번 더
#     준다. 중간에 닫으면 아무것도 주지 않고 버튼이 남는다. 광고가 없으면 주지 않는다.
#   전면광고: 떠 있는 동안 카운트다운이 서 있다. 카운터는 광고가 실제로 보인
#     뒤에만 비고, 준비된 것이 없거나 띄우지 못하면 그대로 남는다.
#   소리: 전체 화면 광고 동안 Master 가 꺼지고, 닫히면 돌아온다.
#   배너: 없다(2026-11-27). 다시 불러오는 길에서도 배너를 청하지 않는다.
#
# 판을 시작하고 끝내는 함수를 부르므로 광고 카운터가 세이브 파일에 적힌다.
# 파일 전체를 받아 두었다가 끝에 되돌린다 — 몇 값만 되돌리면 빠뜨린 값이 남는다.

const SAVE_PATH := "user://savegame.cfg"
const FAKE_ADMOB := """extends Node
var calls: Array = []
func show_interstitial_ad(id): calls.append("show_interstitial " + id)
func show_rewarded_ad(id): calls.append("show_rewarded " + id)
func load_interstitial_ad(): calls.append("load_interstitial")
func load_rewarded_ad(): calls.append("load_rewarded")
func load_banner_ad(): calls.append("load_banner")
"""
# 동의(UMP) 쪽 가짜. status 와 form_available 을 바꿔 Google 의 답을 흉내 낸다.
const FAKE_CONSENT := """extends Node
var calls: Array = []
var status := "UNKNOWN"
var form_available := true
func update_consent_info(_p = null): calls.append("update_consent_info")
func get_consent_status(): return UserConsent.new(status)
func is_consent_form_available(): return form_available
func load_consent_form(): calls.append("load_consent_form")
func show_consent_form(): calls.append("show_consent_form")
func initialize(): calls.append("initialize")
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


func _ok(msg: String) -> void:
	print("  ok    " + msg)


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var ads = main.get("ads")
	if ads == null:
		_fail("Main has no Ads node")
		_finish()
		return
	if ads.available:
		_fail("Ads says it is available on a PC with no plugin")

	# ---- 결과 화면 x2: PC ----
	# 광고가 아예 없는 PC 디버그 빌드는 곧장 준다(개발 중 확인용).
	_dust_setup(main, 40)
	var pc_before: int = main.get("stardust_total")
	main.call("_on_double_stardust_pressed")
	_expect(int(main.get("stardust_total")) == pc_before + 40 and main.get("dust_doubled"),
		"PC debug: x2 grants the run's stardust again at once", "PC debug: x2 did not grant")

	# 여기서부터 가짜 AdMob.
	var script := GDScript.new()
	script.source_code = FAKE_ADMOB
	script.reload()
	var fake: Node = script.new()
	ads.set("_admob", fake)
	ads.set("available", true)
	var master_muted := func() -> bool: return AudioServer.is_bus_mute(0)

	# ---- 결과 화면 x2 ----
	_dust_setup(main, 50)
	var dust0: int = main.get("stardust_total")
	ads.set("_rewarded_id", "d1")
	main.call("_on_double_stardust_pressed")
	_expect(fake.calls.has("show_rewarded d1") and int(main.get("stardust_total")) == dust0,
		"x2 shows a rewarded ad and grants nothing yet", "x2 granted before the ad, or showed none")
	ads.call("_set_showing", true)
	_expect(master_muted.call(), "sound is off during the ad", "sound stayed on during the ad")
	ads.set("_reward_earned", true)
	ads.call("_on_rewarded_finished", true)
	_expect(int(main.get("stardust_total")) == dust0 + 50 and main.get("dust_doubled"),
		"watched to the end -> the run's stardust is granted again", "watched, but no stardust granted")
	_expect(main.get("run_rewarded"), "a watched x2 marks the run as rewarded (no interstitial count)",
		"a watched x2 did not mark the run as rewarded")
	_expect(not master_muted.call(), "sound is back after the ad", "sound stayed off after the ad")
	_expect(fake.calls.has("load_rewarded"), "the next rewarded ad is requested", "no rewarded ad was re-requested")
	main.call("_on_double_stardust_pressed")
	_expect(int(main.get("stardust_total")) == dust0 + 50, "x2 is once a run", "x2 granted twice in one run")

	_dust_setup(main, 50)
	dust0 = main.get("stardust_total")
	ads.set("_rewarded_id", "d2")
	main.call("_on_double_stardust_pressed")
	ads.call("_on_rewarded_finished", true)
	var over: Control = main.get("gameover_popup")
	_expect(int(main.get("stardust_total")) == dust0 and not main.get("dust_doubled")
		and not over.get("_dust_no_ad"),
		"closed early -> nothing granted, the x2 stays to press again", "closed early but stardust was granted, or the button went")

	_dust_setup(main, 50)
	dust0 = main.get("stardust_total")
	ads.set("_rewarded_id", "")
	main.call("_on_double_stardust_pressed")
	_expect(int(main.get("stardust_total")) == dust0 and over.get("_dust_no_ad"),
		"no ad ready -> nothing granted, the button reads AD NOT READY", "no ad but stardust was granted, or the button stayed live")

	_dust_setup(main, 50)
	dust0 = main.get("stardust_total")
	ads.set("_rewarded_id", "d3")
	main.call("_on_double_stardust_pressed")
	ads.call("_on_rewarded_finished", false)
	_expect(int(main.get("stardust_total")) == dust0 and over.get("_dust_no_ad"),
		"the ad failed to show -> nothing granted", "the ad failed but stardust was granted")

	_dust_setup(main, 50)
	dust0 = main.get("stardust_total")
	main.set("ads_removed", true)
	var shown_before: int = fake.calls.size()
	main.call("_on_double_stardust_pressed")
	_expect(int(main.get("stardust_total")) == dust0 + 50 and fake.calls.size() == shown_before,
		"ads removed -> x2 grants at once with no ad", "ads removed but x2 asked for an ad or granted nothing")
	main.set("ads_removed", false)

	# ---- 전면광고 ----
	var every: int = main.get("interstitial_every_restarts")
	main.set("games_played_total", int(main.get("interstitial_free_games")) + 10)
	main.set("restarts_since_interstitial", every + 5)   # _reset_game 이 하나 더 세도 차례다
	ads.set("_interstitial_id", "i1")
	main.call("_on_gameover_play_again_pressed")
	_expect(fake.calls.has("show_interstitial i1"), "PLAY AGAIN shows the interstitial when it is due",
		"the interstitial was due but never shown")
	_expect(main.get("ad_hold_countdown"), "the countdown is held behind the ad", "the countdown is not held")
	var before: int = main.get("restarts_since_interstitial")
	# 카운트다운은 READY -> START -> 시작의 두 단계라, 한 번 흘려서는 멈춤이 없어도
	# 상태가 COUNTDOWN 에 남는다(처음에 이 검사가 그렇게 거저 통과했다). 여러 번
	# 흘리고, 상태뿐 아니라 단계와 남은 시간이 그대로인지를 본다.
	var phase_before: int = main.get("countdown_phase")
	var timer_before: float = main.get("countdown_timer")
	for i in range(3):
		main.call("_update_countdown", 30.0)
	_expect(main.get("state") == main.State.COUNTDOWN
			and int(main.get("countdown_phase")) == phase_before
			and is_equal_approx(float(main.get("countdown_timer")), timer_before),
		"90s pass behind the ad and the countdown has not moved",
		"the countdown ran behind the ad (state %s, phase %d -> %d, timer %.2f -> %.2f)" % [
			main.get("state"), phase_before, main.get("countdown_phase"), timer_before, main.get("countdown_timer")])
	_expect(int(main.get("restarts_since_interstitial")) == before,
		"the counter is not reset while the ad is up", "the counter was reset before the ad closed")
	ads.call("_on_interstitial_finished", true)
	_expect(not main.get("ad_hold_countdown") and int(main.get("restarts_since_interstitial")) == 0,
		"closing the ad frees the countdown and resets the counter",
		"after closing: hold=%s counter=%d" % [main.get("ad_hold_countdown"), main.get("restarts_since_interstitial")])
	for i in range(3):
		if main.get("state") == main.State.COUNTDOWN:
			main.call("_update_countdown", 30.0)
	_expect(main.get("state") == main.State.PLAYING, "then the countdown runs out into the run",
		"the countdown never finished after the ad")

	# 준비된 것이 없으면 카운터를 그대로 두고 다음 기회로.
	main.set("restarts_since_interstitial", every + 5)
	ads.set("_interstitial_id", "")
	var due: int = main.get("restarts_since_interstitial")
	var shown: bool = main.call("_ad_try_interstitial")
	_expect(not shown and int(main.get("restarts_since_interstitial")) == due and not main.get("ad_hold_countdown"),
		"no interstitial ready -> counter kept, nothing held", "no interstitial ready but the counter or hold moved")
	# 띄우려다 실패해도 카운터는 그대로.
	ads.set("_interstitial_id", "i2")
	main.call("_ad_try_interstitial")
	ads.call("_on_interstitial_finished", false)
	_expect(int(main.get("restarts_since_interstitial")) == due and not main.get("ad_hold_countdown"),
		"the interstitial failed to show -> counter kept, countdown free",
		"a failed interstitial reset the counter or left the countdown held")

	# ---- 배너는 없다 ----
	# 2026-11-27 에 뺐다. 광고를 다시 불러오는 길에서 배너를 청하지 않아야 한다.
	fake.calls.clear()
	ads.call("_load_all")
	_expect(not fake.calls.has("load_banner"), "no banner is ever requested",
		"a banner was requested (%s)" % [fake.calls])

	# ---- 광고 동의 (Google UMP) ----
	#
	# 유럽 사용자에게는 광고를 청하기 전에 동의 화면을 띄워야 하고, 나머지 지역은
	# Google 이 "필요 없음"이라고 답한다. 광고 SDK 의 initialize 는 동의가 정리된
	# 뒤에야 불려야 하고, 무슨 일이 있어도 두 번 불리면 안 된다. 그리고 동의를
	# 묻지 못한 날(오프라인, AdMob 에 메시지가 없음)에도 광고를 막아서는 안 된다
	# — 막으면 그 실행 내내 부활 광고까지 사라진다.
	var cscript := GDScript.new()
	cscript.source_code = FAKE_CONSENT
	cscript.reload()
	var settings = main.get("settings_popup")

	# 유럽 밖.
	var c1: Node = cscript.new()
	_consent_reset(ads, c1)
	ads.call("_begin_consent")
	_expect(c1.calls == ["update_consent_info"],
		"consent: Google is asked first and the SDK waits for the answer",
		"consent: before any answer the plugin already got %s" % [c1.calls])
	c1.status = "NOT_REQUIRED"
	ads.call("_on_consent_info_updated")
	_expect(c1.calls.has("initialize") and not c1.calls.has("load_consent_form"),
		"consent not required -> the SDK starts with no form",
		"consent not required, but the plugin got %s" % [c1.calls])
	_expect(not ads.call("privacy_options_available") and not settings.get("_ad_privacy_enabled"),
		"outside Europe the settings' ad privacy link stays dimmed",
		"the ad privacy link was lit for a player with no consent to change")

	# 유럽.
	var c2: Node = cscript.new()
	_consent_reset(ads, c2)
	ads.call("_begin_consent")
	c2.status = "REQUIRED"
	ads.call("_on_consent_info_updated")
	_expect(c2.calls.has("load_consent_form") and not c2.calls.has("initialize"),
		"consent required -> the form loads and the SDK keeps waiting",
		"consent required, but the plugin got %s" % [c2.calls])
	ads.call("_on_consent_form_loaded")
	_expect(c2.calls.has("show_consent_form"), "the loaded form is shown",
		"the consent form loaded but was never shown")
	c2.status = "OBTAINED"
	ads.call("_on_consent_form_dismissed")
	_expect(c2.calls.count("initialize") == 1, "the form closes -> the SDK starts, once",
		"after the form the SDK started %d times" % c2.calls.count("initialize"))
	_expect(ads.call("privacy_options_available") and settings.get("_ad_privacy_enabled"),
		"in Europe the settings' ad privacy link comes alive",
		"consent was obtained but the settings link stayed dimmed — Google requires a way to change it")
	# 설정에서 다시 고르기. 폼은 다시 뜨지만 SDK 는 이미 돌고 있다.
	c2.calls.clear()
	main.call("_on_ad_privacy_pressed")
	ads.call("_on_consent_form_loaded")
	ads.call("_on_consent_form_dismissed")
	_expect(c2.calls.has("load_consent_form") and c2.calls.has("show_consent_form") and not c2.calls.has("initialize"),
		"the settings link brings the form back without restarting the SDK",
		"re-opening the consent from settings sent %s" % [c2.calls])

	# 동의가 필요한데 폼이 없다 — AdMob 에 GDPR 메시지를 안 만든 경우.
	var c3: Node = cscript.new()
	c3.form_available = false
	_consent_reset(ads, c3)
	ads.call("_begin_consent")
	c3.status = "REQUIRED"
	ads.call("_on_consent_info_updated")
	_expect(c3.calls.has("initialize") and not c3.calls.has("load_consent_form"),
		"consent required but no form exists -> ads still start",
		"with no form to show the plugin got %s" % [c3.calls])

	# 묻는 것 자체가 실패 — 오프라인.
	var c4: Node = cscript.new()
	_consent_reset(ads, c4)
	ads.call("_begin_consent")
	ads.call("_on_consent_info_update_failed")
	_expect(c4.calls.has("initialize"), "the consent lookup failed -> ads still start",
		"a failed consent lookup kept the SDK from ever starting")
	ads.call("_on_consent_form_failed")
	_expect(c4.calls.count("initialize") == 1, "the SDK is never started twice",
		"the SDK was started %d times" % c4.calls.count("initialize"))

	ads.set("_admob", null)
	ads.set("available", false)
	for c in [c1, c2, c3, c4]:
		c.free()

	_finish()


func _consent_reset(ads: Node, fake: Node) -> void:
	ads.set("_admob", fake)
	ads.set("available", true)
	ads.set("_sdk_started", false)
	ads.set("consent_status", "UNKNOWN")


## A run over with `amount` stardust earned and the x2 on offer.
func _dust_setup(main: Node2D, amount: int) -> void:
	main.set("last_run_stardust", amount)
	main.set("dust_doubled", false)
	main.get("gameover_popup").call("set_stardust", amount, true, main.get("ads_removed"))



func _expect(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		_ok(ok_msg)
	else:
		_fail(fail_msg)


func _finish() -> void:
	AudioServer.set_bus_mute(0, false)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("")
	if fails == 0:
		print("check_ads_wiring: ok")
		quit(0)
	else:
		print("check_ads_wiring: %d failure(s)" % fails)
		quit(1)
