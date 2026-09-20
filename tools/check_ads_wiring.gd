extends SceneTree

# 광고가 게임에 제대로 이어져 있는지 본다 — 플러그인 없이, 플러그인이 보낼
# 결과를 대신 넣어서.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ads_wiring.gd
#
# 실제 광고는 폰에서만 뜬다. 여기서는 Ads 에 가짜 AdMob 을 끼우고, 광고가
# 준비됐다/닫혔다/보상을 줬다를 차례로 흉내 내며 Main 이 어떻게 반응하는지 본다.
#
#   부활 광고: 끝까지 보면 이어 달린다. 중간에 닫으면 팝업에 남는다. 준비된
#     광고가 없거나 띄우지 못하면 그냥 이어 준다(주인이 정한 규칙).
#   전면광고: 떠 있는 동안 카운트다운이 서 있다. 카운터는 광고가 실제로 보인
#     뒤에만 비고, 준비된 것이 없거나 띄우지 못하면 그대로 남는다.
#   소리: 전체 화면 광고 동안 Master 가 꺼지고, 닫히면 돌아온다.
#   배너: 모드 선택 화면이 자리를 비워 줄 때만, 그 화면에서만 보인다. 16:9 는
#     자리가 없어 거절한다.
#
# 판을 시작하고 끝내는 함수를 부르므로 광고 카운터가 세이브 파일에 적힌다.
# 파일 전체를 받아 두었다가 끝에 되돌린다(check_hidden_unlock.gd 와 같은 이유).

const SAVE_PATH := "user://savegame.cfg"
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

	# PC 그대로: 부활 광고를 누르면 곧장 이어 달린다.
	_revive_setup(main)
	main.call("_on_revive_watch_ad")
	_expect(main.get("run_revived"), "PC: pressing watch-ad continues at once", "PC: watch-ad did nothing")

	# 여기서부터 가짜 AdMob.
	var script := GDScript.new()
	script.source_code = FAKE_ADMOB
	script.reload()
	var fake: Node = script.new()
	ads.set("_admob", fake)
	ads.set("available", true)
	var master_muted := func() -> bool: return AudioServer.is_bus_mute(0)

	# ---- 부활: 끝까지 봄 ----
	_revive_setup(main)
	ads.set("_rewarded_id", "r1")
	main.call("_on_revive_watch_ad")
	_expect(fake.calls.has("show_rewarded r1"), "rewarded ad is shown", "the rewarded ad was never shown")
	_expect(not main.get("run_revived") and main.get("revive_panel").visible,
		"the run waits while the ad is up", "the run continued before the ad closed")
	ads.call("_set_showing", true)
	_expect(master_muted.call(), "sound is off during the ad", "sound stayed on during the ad")
	ads.set("_reward_earned", true)
	ads.call("_on_rewarded_finished", true)
	_expect(main.get("run_revived") and not main.get("revive_panel").visible,
		"watched to the end -> the run continues", "watched to the end but the run did not continue")
	_expect(not master_muted.call(), "sound is back after the ad", "sound stayed off after the ad")
	_expect(fake.calls.has("load_rewarded"), "the next rewarded ad is requested", "no rewarded ad was re-requested")

	# ---- 부활: 중간에 닫음 ----
	_revive_setup(main)
	ads.set("_rewarded_id", "r2")
	main.call("_on_revive_watch_ad")
	ads.call("_on_rewarded_finished", true)
	_expect(not main.get("run_revived") and main.get("revive_panel").visible,
		"closed early -> still on the revive popup", "closed early but the run continued anyway")
	# 그 자리에서 다시 누르면 준비된 광고가 없다 -> 그냥 이어 준다.
	main.call("_on_revive_watch_ad")
	_expect(main.get("run_revived"), "no ad ready -> the run continues free",
		"no ad ready and the button did nothing")

	# ---- 부활: 띄우지 못함 ----
	_revive_setup(main)
	ads.set("_rewarded_id", "r3")
	main.call("_on_revive_watch_ad")
	ads.call("_on_rewarded_finished", false)
	_expect(main.get("run_revived"), "the ad failed to show -> the run continues",
		"the ad failed to show and the player was left stuck")

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

	# ---- 배너 ----
	var screen = main.get("mode_select_panel")
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	for case in [[width * 16.0 / 9.0, false], [width * 20.0 / 9.0, true]]:
		screen.size = Vector2(width, case[0])
		screen.call("_layout")
		main.call("_set_state", main.State.MODE_SELECT)
		fake.calls.clear()
		ads.call("_on_banner_loaded", "b1")
		main.call("_apply_banner_height", 150.0, 1080.0)
		var label := "480x%.0f" % case[0]
		if case[1]:
			_expect(main.get("banner_reserved") and fake.calls.has("show_banner b1"),
				"%s: a 50dp banner gets its space and shows on mode select" % label,
				"%s: the banner should fit but reserved=%s calls=%s" % [label, main.get("banner_reserved"), fake.calls])
			# 같은 상태를 다시 청하면 아무것도 보내지 않는다. 화면이 바뀔 때마다
			# 청했더니 플러그인이 "이미 안 보인다"는 오류를 매번 남겼다.
			fake.calls.clear()
			main.call("_update_banner")
			main.call("_set_state", main.State.MODE_SELECT)
			_expect(fake.calls.is_empty(), "%s: asking again for the same banner state sends nothing" % label,
				"%s: the same banner state was requested again (%s)" % [label, fake.calls])
			fake.calls.clear()
			main.call("_set_state", main.State.PLAYING)
			_expect(fake.calls.has("hide_banner b1"), "%s: leaving mode select hides the banner" % label,
				"%s: the banner stayed up into the game" % label)
		else:
			_expect(not main.get("banner_reserved") and not fake.calls.has("show_banner b1"),
				"%s: no room, so no banner" % label,
				"%s: the screen had no room but the banner showed" % label)
	screen.call("set_banner_reserve", 0.0)

	_finish()


func _revive_setup(main: Node2D) -> void:
	main.set("run_revived", false)
	main.call("_offer_revive")


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
