extends SceneTree

# 판이 끝난 뒤의 음악 — 깔리는가, 낮게 깔리는가, 그리고 제때 원래대로
# 돌아오는가.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_gameover_bgm.gd
#
# 두 가지가 조용히 어긋날 수 있다.
#
# 하나, 낮추는 것을 잊는다. 소리는 나므로 화면으로는 멀쩡하고, 게임오버
# 효과음과 곡이 같은 크기로 서로를 밟는 것은 나란히 들어 봐야 안다.
#
# 둘, 돌아오지 않는다. 판을 떠나는 길이 셋인데(PLAY AGAIN / HOME / 일시정지)
# 음악을 되돌리는 것은 _set_state 와 _start_countdown 두 곳뿐이라, 어느 길이
# 그 둘을 안 지나면 게임 내내 낮은 게임오버 곡이 깔린 채로 논다.
#
# 부활 팝업이 있던 때(~2026-11-28)는 부활 팝업에서 게임오버 팝업으로 넘어갈
# 때 곡이 다시 시작하지 않는지도 보았다.

const SAVE_PATH := "user://savegame.cfg"

var _fail := 0
var _had_save := false
var _save_backup := ""


func _init() -> void:
	# _finish_run 이 최고 기록을 쓴다. 통째로 떠 두고 끝나면 되돌린다.
	_backup_save()
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SAVE_PATH)


func _restore_save() -> void:
	if not _had_save:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("could not restore %s" % SAVE_PATH)
		return
	f.store_string(_save_backup)
	f.close()


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


# 크로스페이드가 끝나기를 실제 시간으로 기다린다. 프레임 수로 세면 헤드리스의
# 빠른 프레임 때문에 훨씬 짧은 시간이 된다.
func _settle(main: Node2D) -> void:
	await create_timer(float(main.get("BGM_CROSSFADE_TIME")) * 1.5 + 0.1).timeout


func _active(main: Node2D) -> AudioStreamPlayer:
	var players: Array = main.get("bgm_players")
	return players[int(main.get("bgm_active"))]


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node2D = root.get_child(root.get_child_count() - 1)
	while main.get("boot_pending"):
		await process_frame

	var quiet: float = float(main.get("gameover_bgm_db"))
	var over_path: String = main.call("_resolve_audio", main.get("BGM_GAMEOVER_NAME"))
	_ok(quiet < -0.5, "낮추는 값이 실제로 낮다 (%.1f dB)" % quiet)
	# 2026-11-27 에 1.x 곡을 모두 지웠다 — 2.0 곡은 새로 만든다. 곡이 없는 동안
	# 재생 코드는 조용히 아무것도 안 하므로(_resolve_audio 가 "" 를 준다) 볼 것이
	# 없다. 실패로 두면 곡이 올 때까지 검사 묶음이 늘 빨갛고, 그러면 진짜 실패가
	# 묻힌다. 곡이 들어오면 아래가 그대로 다시 돈다.
	if over_path == "":
		print("  건너뜀 — 게임오버 곡(%s)이 아직 없다" % main.get("BGM_GAMEOVER_NAME"))
		_finish()
		return

	# ---- 판을 하나 시작한다 ----
	main.call("_apply_mode", 0)
	main.call("_reset_game")
	main.call("_start_countdown")
	await _settle(main)
	var run_path: String = str(main.get("bgm_current_path"))
	_ok(run_path != over_path, "판이 도는 동안은 게임오버 곡이 아니다 (%s)" % run_path.get_file())
	_ok(absf(_active(main).volume_db) < 0.01,
		"그 곡은 원래 크기다 (%.1f dB)" % _active(main).volume_db)

	# ---- 죽는다: 곧장 게임오버 팝업 ----
	main.set("score", 4200)
	main.call("_game_over")
	await _settle(main)
	_ok(str(main.get("bgm_current_path")) == over_path, "게임오버 팝업에 게임오버 곡이 깔린다")
	_ok(absf(_active(main).volume_db - quiet) < 0.01,
		"낮춘 크기로 깔린다 (%.1f dB, want %.1f)" % [_active(main).volume_db, quiet])
	_ok(_active(main).playing, "실제로 재생 중이다")

	# ---- 다시 하기 ----
	main.call("_reset_game")
	main.call("_start_countdown")
	await _settle(main)
	_ok(str(main.get("bgm_current_path")) == run_path, "PLAY AGAIN 이면 판의 곡으로 돌아온다")
	_ok(absf(_active(main).volume_db) < 0.01,
		"원래 크기로 돌아온다 (%.1f dB)" % _active(main).volume_db)

	# ---- 홈으로 ----
	main.set("score", 900)
	main.call("_game_over")
	await _settle(main)
	_ok(str(main.get("bgm_current_path")) == over_path, "다시 죽으면 다시 게임오버 곡")
	main.call("_reset_game")
	main.call("_set_state", 0)   # State.MODE_SELECT
	await _settle(main)
	var menu_path: String = main.call("_resolve_audio", main.get("BGM_MENU_NAME"))
	_ok(str(main.get("bgm_current_path")) == menu_path, "HOME 이면 메뉴 곡으로 돌아온다")
	_ok(absf(_active(main).volume_db) < 0.01, "메뉴 곡도 원래 크기다")

	_finish()


func _finish() -> void:
	_restore_save()
	if _fail == 0:
		print("check_gameover_bgm: ok")
		quit(0)
	else:
		print("check_gameover_bgm: %d failure(s)" % _fail)
		quit(1)
