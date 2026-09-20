extends SceneTree

# 로그인과 순위표 흐름을 Play 게임즈 플러그인 없이 본다 — 플러그인이 보내 올
# 결과를 직접 넣어서.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_play_games.gd
#
# 진짜 로그인은 기기에서만 된다. 여기서 보는 것은 그 결과를 받는 쪽이다: 결과가
# 오면 세 팝업과 메인 화면이 제대로 바뀌는가, 결과가 안 오는 PC 에서 멈추지
# 않는가, 사진이 이름보다 늦게 와도 들어가는가, 창을 닫아 결과가 끊겨도 버튼이
# 다시 먹는가, 어느 순위표에 무엇이 올라가는가. 결과를 넣는 입구는 플러그인
# 신호가 부르는 바로 그 함수들(_on_authenticated / _apply_player /
# _on_image_stored)이라, 여기서 통과하면 기기에서도 같은 길을 지난다.
#
# 판을 끝내는 _finish_run 을 부르므로 진짜 저장 파일에 최고 기록이 쓰인다.
# 통째로 떠 두고 끝날 때 되돌린다(CLAUDE.md 의 저장 파일 규칙).

const AVATAR_PATH := "user://_check_play_games_avatar.png"
# 남의 사진. 실제로 있는 파일이어야 한다 — 없는 경로를 흘려 보내면, 경로를
# 가리지 않는 코드도 파일을 못 읽어 사진이 비어 남으므로 검사가 거저 통과한다.
const OTHER_PATH := "user://_check_play_games_other.png"
const SAVE_PATH := "user://savegame.cfg"

var _fail := 0
var _had_save := false
var _save_backup := ""


# 로그인 창을 여는 클라이언트 흉내. 불린 횟수만 센다.
class FakeSignInClient extends Node:
	var calls := 0
	func sign_in() -> void:
		calls += 1
	func is_authenticated() -> void:
		pass


# 순위표 클라이언트 흉내. 무엇을 어느 순위표에 올리고 열었는지 적어 둔다.
class FakeLeaderboardsClient extends Node:
	var submitted: Array = []
	var shown: Array = []
	func submit_score(leaderboard_id: String, score: int) -> void:
		submitted.append([leaderboard_id, score])
	func show_leaderboard(leaderboard_id: String) -> void:
		shown.append(leaderboard_id)


func _init() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SAVE_PATH)
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


func _remove_avatar() -> void:
	for path in [AVATAR_PATH, OTHER_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var pg: Node = main.get("play_games")
	_ok(pg != null, "Main 이 PlayGames 를 만든다")
	if pg == null:
		_finish()
		return
	# 인스펙터 스위치가 켜진 채 커밋되면 모든 테스트 빌드가 가짜 계정으로 뜬다.
	_ok(not bool(main.get("debug_fake_sign_in")), "debug_fake_sign_in 이 꺼져 있다 (Main.tscn 에 켜진 채 저장되지 않았다)")

	print("")
	print("PC — 플러그인 없음")
	_ok(not bool(pg.get("available")), "쓸 수 없음으로 잡힌다")
	var results: Array = []
	pg.connect("sign_in_finished", func(ok: bool) -> void: results.append(ok))
	main.call("_on_login_pressed")
	await process_frame
	_ok(results == [false], "로그인을 누르면 곧바로 실패로 답한다 — 결과를 기다리며 멈추지 않는다")
	_ok(not bool(pg.get("busy")), "누른 뒤 busy 로 남지 않는다")
	_ok(not bool(main.get("player_logged_in")), "로그인 안 된 채로 남는다")

	var settings: Control = main.get("settings_popup")
	settings.call("ensure_built")
	main.call("_open_settings")
	await process_frame
	var login_btn: Control = settings.get("_login")
	var account: Control = settings.get("_account")
	var account_w_out: float = account.size.x
	_ok(login_btn.visible, "로그인 전 설정: LOGIN 버튼이 보인다")
	settings.visible = false

	print("")
	print("게임오버 팝업이 떠 있는 동안 로그인이 끝난다")
	var over: Control = main.get("gameover_popup")
	over.call("ensure_built")
	over.call("set_result", null, 0.0, 1200, 5, 3000, false, false, 1200)
	over.visible = true
	await process_frame
	var cap: Label = over.get("_google_button").get_node("Caption")
	var google_text: String = str(over.get("GOOGLE_TEXT"))
	var board_text: String = TranslationServer.translate(str(over.get("LEADERBOARD_TEXT")))
	_ok(cap.text == google_text, "로그인 전: LOGIN WITH GOOGLE")
	var fired: Array = []
	over.connect("login_pressed", func() -> void: fired.append("login"))
	over.connect("leaderboard_pressed", func() -> void: fired.append("leaderboard"))

	_remove_avatar()
	pg.call("_on_authenticated", true)
	pg.call("_apply_player", "김철수", AVATAR_PATH)
	await process_frame
	_ok(bool(main.get("player_logged_in")), "인증되면 Main 이 로그인 상태가 된다")
	_ok(str(main.get("player_display_name")) == "김철수", "이름이 넘어온다")
	_ok(main.get("player_avatar") == null, "사진 파일이 아직 없으면 비어 있다 — 없는 파일을 억지로 읽지 않는다")
	_ok(cap.text == board_text, "떠 있던 게임오버 팝업이 곧바로 LEADERBOARD 로 바뀐다")
	over.call("_on_google_button_pressed")
	_ok(fired == ["leaderboard"], "그때 누르면 로그인이 아니라 순위표로 간다")

	print("")
	print("사진이 늦게 도착한다")
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 0.0, 1.0))
	img.save_png(AVATAR_PATH)
	var other := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	other.fill(Color(0.0, 0.0, 1.0, 1.0))
	other.save_png(OTHER_PATH)
	pg.call("_on_image_stored", OTHER_PATH)
	await process_frame
	_ok(main.get("player_avatar") == null, "다른 사람의 사진이 도착해도 받지 않는다 — 그 파일이 실제로 있어도")
	pg.call("_on_image_stored", AVATAR_PATH)
	await process_frame
	var av: Texture2D = main.get("player_avatar")
	_ok(av != null and av.get_width() == 8, "내 사진이 도착하면 들어간다")

	print("")
	print("로그인 뒤의 설정과 메인 화면")
	main.call("_open_settings")
	await process_frame
	_ok(not login_btn.visible, "LOGIN 버튼이 사라진다 — 로그아웃이 없으므로 LOGOUT 도 없다")
	var text: String = str(settings.get("_account_text"))
	_ok(text.contains("김철수"), "계정 줄에 이름이 나온다 (%s)" % text)
	_ok(settings.get("_avatar") == av, "계정 줄의 사진이 그 사진이다")
	_ok(account.size.x > account_w_out + 1.0,
		"버튼이 비운 자리를 이름이 쓴다 (%.0f -> %.0f)" % [account_w_out, account.size.x])
	settings.visible = false
	main.call("_on_mode_select_login_pressed")
	await process_frame
	_ok(settings.visible, "로그인한 뒤 메인 화면의 사람 모양은 설정을 연다")
	settings.visible = false

	print("")
	print("계정이 빠진다 (다시 켰을 때의 조용한 확인이 false)")
	pg.call("_on_authenticated", false)
	await process_frame
	_ok(not bool(main.get("player_logged_in")), "로그인 상태가 풀린다")
	_ok(main.get("player_avatar") == null and str(main.get("player_display_name")) == "",
		"이름과 사진도 비워진다")
	_ok(cap.text == google_text, "떠 있던 게임오버 팝업도 LOGIN WITH GOOGLE 로 돌아온다")
	main.call("_open_settings")
	await process_frame
	_ok(login_btn.visible, "설정에 LOGIN 버튼이 돌아온다")
	settings.visible = false
	over.visible = false

	print("")
	print("로그인 창이 떠 있는 동안 (기기 흉내)")
	var fake := FakeSignInClient.new()
	pg.add_child(fake)
	pg.set("_sign_in_client", fake)
	pg.set("available", true)
	results.clear()
	pg.call("sign_in")
	pg.call("sign_in")
	_ok(fake.calls == 1 and bool(pg.get("busy")), "창이 떠 있는 동안의 연타는 창을 한 번만 연다")
	var stale: int = int(pg.get("_attempt")) - 1
	pg.call("_on_sign_in_timeout", stale)
	_ok(bool(pg.get("busy")) and results.is_empty(), "지난 시도의 시간 초과는 지금 시도를 끊지 않는다")
	pg.call("_on_sign_in_timeout", int(pg.get("_attempt")))
	_ok(not bool(pg.get("busy")) and results == [false],
		"답이 끝내 안 오면 풀려서 실패로 답한다 — 버튼이 영영 먹통이 되지 않는다")
	pg.call("sign_in")
	_ok(fake.calls == 2, "풀린 뒤에는 다시 누를 수 있다")
	pg.call("_on_authenticated", false)
	pg.set("available", false)
	pg.set("_sign_in_client", null)
	fake.queue_free()

	await _check_leaderboards(main, pg)

	_remove_avatar()
	_finish()


# 어느 순위표에 무엇이 올라가는가. 모드마다 순위표가 따로라, 모드를 하나 잘못
# 짚으면 SKY 기록이 OCEAN 순위표에 올라가도 화면은 멀쩡하다 — 기기에서 순위표를
# 열어 봐야 알고, 그때는 이미 남의 순위표가 더럽혀진 뒤다.
func _check_leaderboards(main: Node2D, pg: Node) -> void:
	print("")
	print("순위표")
	var ids: Array = main.get("MODE_LEADERBOARD_ID")
	var bests: PackedInt32Array = main.get("leaderboard_bests")
	_ok(ids.size() == bests.size(), "순위표 ID 가 모드 수(%d)만큼 있다" % bests.size())
	var unique := {}
	for id in ids:
		unique[str(id)] = true
	_ok(unique.size() == ids.size() and not unique.has(""), "ID 가 비어 있지 않고 서로 다르다")

	var lb := FakeLeaderboardsClient.new()
	pg.add_child(lb)
	pg.set("_leaderboards_client", lb)

	# 로그인 전에 쌓인 기록. SKY 와 OCEAN 에만 있다.
	for m in range(bests.size()):
		bests[m] = 0
	bests[0] = 1200
	bests[2] = 3300
	main.set("leaderboard_bests", bests)

	main.call("_submit_leaderboard", 0)
	main.call("_on_gameover_leaderboard_pressed")
	_ok(lb.submitted.is_empty() and lb.shown.is_empty(), "로그인 전에는 올리지도 열지도 않는다")

	pg.call("_on_authenticated", true)
	await process_frame
	_ok(lb.submitted == [[ids[0], 1200], [ids[2], 3300]],
		"로그인하는 순간 로그인 전의 기록을 제 순위표에 올린다 — 기록 없는 모드는 건너뛴다 (%s)" % str(lb.submitted))
	lb.submitted.clear()
	pg.call("_apply_player", "김철수", "")
	await process_frame
	_ok(lb.submitted.is_empty(), "로그인 한 번에 한 번만 — 이름이 뒤따라 와도 다시 올리지 않는다")

	# 판 끝: 이번 판이 쌓인 기록보다 낮으면 쌓인 기록을 보낸다.
	main.set("current_mode", 2)
	main.set("score", 900)
	main.set("leaderboard_score", 900)
	main.call("_finish_run")
	await process_frame
	_ok(lb.submitted == [[ids[2], 3300]],
		"판이 끝나면 그 모드 순위표에 쌓아 둔 최고 기록을 올린다 (%s)" % str(lb.submitted))
	lb.submitted.clear()

	# 부활한 판: 순위표는 첫 실수 지점의 점수까지만 센다.
	main.set("current_mode", 1)
	main.set("score", 5000)
	main.set("leaderboard_score", 4000)
	main.call("_finish_run")
	await process_frame
	_ok(lb.submitted == [[ids[1], 4000]],
		"부활한 판은 최종 점수가 아니라 멈춘 점수로 올라간다 (%s)" % str(lb.submitted))

	main.call("_on_gameover_leaderboard_pressed")
	_ok(lb.shown == [ids[1]], "게임오버의 LEADERBOARD 는 방금 끝난 판의 모드 순위표를 연다")
	lb.shown.clear()
	main.call("_on_mode_select_leaderboard_pressed", 3)
	_ok(lb.shown == [ids[3]], "메인 화면의 LEADERBOARD 는 고른 카드의 모드 순위표를 연다")
	lb.shown.clear()
	var gameover: Control = main.get("gameover_popup")
	gameover.visible = false

	# 로그인 전의 메인 화면 LEADERBOARD: 로그인부터. PC 에서는 실패하므로 열리지
	# 않아야 하고, 기다리던 연결도 남지 않아야 한다 — 남으면 나중의 아무 로그인
	# 결과에 순위표가 불쑥 뜬다.
	pg.call("_on_authenticated", false)
	await process_frame
	var before: int = pg.get_signal_connection_list("sign_in_finished").size()
	main.call("_on_mode_select_leaderboard_pressed", 0)
	await process_frame
	var after: int = pg.get_signal_connection_list("sign_in_finished").size()
	_ok(lb.shown.is_empty(), "로그인에 실패하면 순위표를 열지 않는다")
	_ok(after == before, "기다리던 연결이 남지 않는다 (%d -> %d)" % [before, after])

	await _check_submit_retry(pg, lb, ids)

	pg.set("_leaderboards_client", null)
	lb.queue_free()


# 제출이 실패하면 다시 로그인해 한 번만 더 보낸다. 폰에서 Play 서명 빌드로
# 바뀐 뒤 모든 제출이 26502 CLIENT_RECONNECT_REQUIRED 로 실패한 적이 있다.
# 한 번뿐이어야 한다 — 끝없이 되풀이하면 실패가 계속될 때 로그인 창만 돈다.
func _check_submit_retry(pg: Node, lb: Node, ids: Array) -> void:
	print("")
	print("순위표 제출 실패 뒤 재시도")
	var connections: int = pg.get_signal_connection_list("sign_in_finished").size()
	var signer := FakeSignInClient.new()
	pg.add_child(signer)
	pg.set("_sign_in_client", signer)
	pg.set("available", true)
	pg.call("_on_authenticated", true)
	await process_frame
	lb.submitted.clear()

	pg.call("submit_score", ids[0], 500)
	pg.call("_on_score_submitted", false, ids[0])
	_ok(signer.calls == 1 and lb.submitted == [[ids[0], 500]],
		"실패하면 다시 로그인부터 한다 — 연결이 새로 되기 전에는 다시 보내지 않는다")
	pg.call("_on_authenticated", true)
	await process_frame
	_ok(lb.submitted == [[ids[0], 500], [ids[0], 500]],
		"다시 로그인되면 같은 점수를 한 번 더 보낸다 (%s)" % str(lb.submitted))
	pg.call("_on_score_submitted", false, ids[0])
	_ok(signer.calls == 1, "다시 보낸 것도 실패하면 거기서 멈춘다 — 로그인을 되풀이하지 않는다")

	lb.submitted.clear()
	pg.call("submit_score", ids[0], 600)
	pg.call("_on_score_submitted", false, ids[0])
	_ok(signer.calls == 2, "다음에 새로 보낸 점수는 다시 한 번 기회를 얻는다")
	pg.call("_on_authenticated", true)
	await process_frame

	lb.submitted.clear()
	pg.call("submit_score", ids[1], 700)
	pg.call("submit_score", ids[2], 800)
	pg.call("_on_score_submitted", false, ids[1])
	pg.call("_on_score_submitted", false, ids[2])
	_ok(signer.calls == 3, "두 순위표가 함께 실패해도 다시 로그인은 한 번 (%d)" % signer.calls)
	lb.submitted.clear()
	pg.call("_on_authenticated", true)
	await process_frame
	_ok(lb.submitted.size() == 2 and lb.submitted.has([ids[1], 700]) and lb.submitted.has([ids[2], 800]),
		"다시 로그인되면 둘 다 다시 보낸다 (%s)" % str(lb.submitted))

	pg.call("submit_score", ids[3], 900)
	pg.call("_on_score_submitted", false, ids[3])
	lb.submitted.clear()
	pg.call("_on_authenticated", false)
	await process_frame
	_ok(lb.submitted.is_empty(), "다시 로그인에 실패하면 보내지 않는다")
	_ok(pg.get_signal_connection_list("sign_in_finished").size() == connections,
		"재시도가 기다리던 연결이 남지 않는다")

	pg.set("available", false)
	pg.set("_sign_in_client", null)
	signer.queue_free()


func _finish() -> void:
	# 저장 파일을 통째로 되돌린다.
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_backup)
			f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if _fail == 0:
		print("check_play_games: ok")
		quit(0)
	else:
		print("check_play_games: %d failure(s)" % _fail)
		quit(1)
