extends SceneTree

# 분석이 동의를 지키는지, 그리고 게임의 실제 흐름이 맞는 이벤트를 맞는 값으로
# 남기는지 본다 — 플러그인 없이, 가짜 Firebase 를 끼워서.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_analytics.gd
#
# 동의 규칙(Analytics.gd 참고): Google UMP 가 NOT_REQUIRED 라고 한 곳에서만 켠다.
# REQUIRED 와 OBTAINED(유럽), 그리고 아직 모름(UNKNOWN, 오프라인)은 끈 채로 둔다.
# 꺼져 있는 동안의 이벤트는 쌓지 않고 버린다.
#
# 판을 시작하고 끝내고 튜토리얼을 마치므로 세이브 파일에 적힌다. 파일 전체를 받아
# 두었다가 끝에 되돌린다 — 몇 값만 되돌리면 빠뜨린 값이 남는다.

const SAVE_PATH := "user://savegame.cfg"
const FAKE_ANALYTICS := """extends Node
var calls: Array = []
func set_consent(d): calls.append(["consent", d])
func set_analytics_collection_enabled(b): calls.append(["collect", b])
func log_event(n, p): calls.append(["event", n, p])
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


func _expect(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("  ok    " + ok_msg)
	else:
		fails += 1
		print("  FAIL: " + fail_msg)


func _events(fake: Node, event_name: String) -> Array:
	var out := []
	for c in fake.calls:
		if c[0] == "event" and c[1] == event_name:
			out.append(c[2])
	return out


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var analytics = main.get("analytics")
	if analytics == null:
		_expect(false, "", "Main has no Analytics node")
		_finish()
		return
	_expect(not analytics.available and not analytics.collecting,
		"PC: no plugin, so nothing is available and nothing collects",
		"PC: analytics claims to be available or collecting with no plugin")
	main.call("_log_event", "level_start", {"level_name": "flags"})   # 오류 없이 버려져야 한다

	# 여기서부터 가짜 Firebase.
	var script := GDScript.new()
	script.source_code = FAKE_ANALYTICS
	script.reload()
	var fake: Node = script.new()
	analytics.set("_analytics", fake)
	analytics.set("available", true)
	analytics.call("_on_analytics_initialized", true)
	_expect(fake.calls.size() == 2 and fake.calls[0][0] == "consent" and fake.calls[0][1]["analytics_storage"] == "denied"
			and fake.calls[1] == ["collect", false],
		"before any consent answer: every signal denied, collection off",
		"before any consent answer the plugin got %s" % [fake.calls])
	fake.calls.clear()
	main.call("_log_event", "level_start", {"level_name": "flags"})
	_expect(fake.calls.is_empty(), "events while off are dropped, not queued",
		"an event went out before consent: %s" % [fake.calls])

	# 유럽 밖 — Ads 가 받은 답을 Main 이 넘기는 실제 길로.
	var ads = main.get("ads")
	ads.set("consent_status", "NOT_REQUIRED")
	main.call("_on_ads_consent_changed")
	var granted: bool = fake.calls.size() >= 2 and fake.calls[0][0] == "consent"
	if granted:
		for k in ["analytics_storage", "ad_storage", "ad_user_data", "ad_personalization"]:
			granted = granted and fake.calls[0][1].get(k) == "granted"
	_expect(granted and fake.calls[1] == ["collect", true] and analytics.collecting,
		"consent NOT_REQUIRED -> all four signals granted and collection on",
		"NOT_REQUIRED did not switch collection on: %s" % [fake.calls])
	fake.calls.clear()
	main.call("_on_ads_consent_changed")
	_expect(fake.calls.is_empty(), "the same answer twice sends nothing again",
		"a repeated consent answer was re-sent: %s" % [fake.calls])

	# 판 시작과 끝.
	main.set("tutorial_seen", true)
	main.call("_apply_mode", 1)
	main.set("current_mode", 1)
	main.call("_reset_game")
	main.set("current_mode", 1)
	fake.calls.clear()
	main.call("_start_countdown")
	var starts := _events(fake, "level_start")
	_expect(starts.size() == 1 and starts[0].get("level_name") == "math",
		"a run start logs level_start with the mode (math)",
		"run start logged %s" % [starts])
	main.set("score", 1234)
	main.set("gates_passed", 17)
	main.set("max_combo", 9)
	fake.calls.clear()
	main.call("_finish_run")
	var ends := _events(fake, "post_score")
	_expect(ends.size() == 1 and ends[0].get("level_name") == "math" and ends[0].get("score") == 1234
			and ends[0].get("gates") == 17 and ends[0].get("max_combo") == 9,
		"a run end logs post_score with mode, score 1234, 17 gates, combo 9",
		"run end logged %s" % [ends])
	main.get("gameover_popup").visible = false

	# 결과 화면 x2 의 결과. 부활(이어 뛰기)은 2026-11-28 에 빠졌다.
	main.set("last_run_stardust", 30)
	main.set("dust_doubled", false)
	fake.calls.clear()
	main.call("_on_double_ad_finished", Ads.Reward.SKIPPED)
	main.call("_on_double_ad_finished", Ads.Reward.EARNED)
	var doubles := _events(fake, "double_stardust")
	_expect(doubles.size() == 2 and doubles[0].get("result") == "skipped"
			and doubles[1].get("result") == "watched" and doubles[1].get("amount") == 30,
		"x2 results are logged as skipped, then watched with the amount",
		"x2 results logged %s" % [doubles])
	main.get("gameover_popup").visible = false

	# 튜토리얼.
	main.call("_reset_game")
	fake.calls.clear()
	main.call("_begin_tutorial")
	main.call("_on_tutorial_finished")
	_expect(_events(fake, "tutorial_begin").size() == 1 and _events(fake, "tutorial_complete").size() == 1,
		"the tutorial logs its begin and its end", "tutorial events: %s" % [fake.calls])

	# 유럽: 답을 받았어도(OBTAINED) 분석은 끈다.
	for status in ["REQUIRED", "OBTAINED", "UNKNOWN"]:
		ads.set("consent_status", status)
		fake.calls.clear()
		main.call("_on_ads_consent_changed")
		main.call("_log_event", "level_start", {"level_name": "flags"})
		_expect(not analytics.collecting and _events(fake, "level_start").is_empty(),
			"consent %s -> collection off, events dropped" % status,
			"consent %s still collected: %s" % [status, fake.calls])

	analytics.set("_analytics", null)
	analytics.set("available", false)
	analytics.set("collecting", false)
	fake.free()
	_finish()


func _finish() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("")
	print("check_analytics: %s" % ("ok" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails > 0 else 0)
