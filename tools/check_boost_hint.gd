extends SceneTree

# 가속 보너스 안내가 설치 후 딱 한 번만 뜨는지, 그리고 안내에 적힌 숫자가
# 실제 튜닝을 따라가는지.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_boost_hint.gd
#
# 눈으로 잡기 어려운 이유가 두 가지다. 첫째, 이 팝업은 설치 직후 한 번만 뜨므로
# 개발 중에는 거의 안 보인다 — 두 번째 판부터는 무슨 짓을 해도 안 뜨니 "안 뜬다"가
# 정상인지 고장인지 구분이 안 된다. 둘째, 팝업이 카운트다운을 대신 걸어 주는
# 구조라, 여기가 끊기면 START 를 눌러도 아무 일이 안 일어난다.
#
# 보는 것:
#   1. 새 설치의 첫 START 에서 뜨고, 그동안 판은 시작되지 않는다.
#   2. OK 를 누르면 닫히고 그때 카운트다운이 걸린다.
#   3. 두 번째 판부터는 안 뜨고 바로 시작한다.
#   4. 앱을 껐다 켜도 안 뜬다 — 실행 단위로 저장하면 껐다 켤 때마다 다시 뜬다.
#   5. 안내에 적힌 배율이 Main 의 boost_bonus_* 를 따라간다. 여기가 끊기면
#      튜닝을 바꿔도 안내문만 옛 숫자를 말한다.

# 판을 굴리지는 않지만 저장 파일에 쓴다(안내를 봤다는 표시). 통째로 되돌린다 —
# tools/check_hidden_unlock.gd 와 같은 방식이다.
const SAVE_PATH := "user://savegame.cfg"

var fails := 0
var _save_backup: String = ""
var _had_save := false


func _init() -> void:
	root.call_deferred("add_child", load("res://scenes/Main.tscn").instantiate())
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


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


func _run() -> void:
	await process_frame
	await process_frame
	var m: Node2D = root.get_child(root.get_child_count() - 1)
	while m.get("boot_pending"):
		await process_frame
	var popup = m.get("boost_hint_popup")
	if popup == null:
		print("  FAIL: no boost_hint_popup")
		quit(1)
		return
	_backup_save()
	print("check_boost_hint:")
	print("")

	# ---- 1. 새 설치의 첫 START ----
	m.set("boost_hint_seen", false)
	m.call("_save_boost_hint_seen")
	m.call("_set_state", 0)   # MODE_SELECT
	m.call("_reset_game")
	m.call("_on_mode_selected", 0)
	await process_frame
	print("  첫 START -> 팝업 %s, 상태 %d, run_active %s" % [
		"보임" if popup.visible else "안 보임", m.get("state"), m.get("run_active")])
	if not popup.visible:
		_fail("새 설치의 첫 START 인데 안내가 안 떴다")
	if m.get("run_active"):
		_fail("안내가 떠 있는데 판이 이미 시작됐다 — 뒤에서 게이트가 흐르는 채로 읽게 된다")

	# ---- 2. OK 가 판을 이어서 걸어 주는가 ----
	m.call("_on_boost_hint_ok")
	await process_frame
	print("  OK -> 팝업 %s, 상태 %d, run_active %s" % [
		"보임" if popup.visible else "닫힘", m.get("state"), m.get("run_active")])
	if popup.visible:
		_fail("OK 를 눌렀는데 안내가 안 닫혔다")
	if not m.get("run_active"):
		_fail("OK 를 눌렀는데 판이 시작되지 않았다 — START 를 눌러도 아무 일이 없는 상태다")
	if not m.get("boost_hint_seen"):
		_fail("OK 를 눌렀는데 봤다는 표시가 안 섰다")

	# ---- 3. 두 번째 판 ----
	m.call("_reset_game")
	m.call("_set_state", 0)
	m.call("_on_mode_selected", 0)
	await process_frame
	print("  두 번째 START -> 팝업 %s, run_active %s" % [
		"보임" if popup.visible else "안 보임", m.get("run_active")])
	if popup.visible:
		_fail("두 번째 판에서도 안내가 떴다")
	if not m.get("run_active"):
		_fail("두 번째 판이 시작되지 않았다")

	# ---- 4. 껐다 켜도 안 뜬다 ----
	m.call("_reset_game")
	var fresh: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(fresh)
	await process_frame
	while fresh.get("boot_pending"):
		await process_frame
	print("")
	print("  재실행 -> boost_hint_seen %s" % fresh.get("boost_hint_seen"))
	if not fresh.get("boost_hint_seen"):
		_fail("앱을 다시 띄우니 안내를 안 본 것으로 돌아갔다 — 켤 때마다 다시 뜬다")
	fresh.queue_free()

	# ---- 5. 안내의 숫자가 튜닝을 따라가는가 ----
	#
	# 값을 흔들어 보고 따라오는지로 본다. 지금 값과 비교만 하면, 팝업이 "×2" 를
	# 박아 놓고 있어도 마침 같은 값이라 통과한다.
	print("")
	var labels: Array[String] = []
	for tier in range(3):
		labels.append(str(popup.call("_row_label", tier)))
	print("  기본 배율 -> %s" % str(labels))
	if labels[2] == labels[0]:
		_fail("최고 단계와 최하 단계의 배율 표기가 같다 — 표가 안 읽히고 있다")

	var was_best: float = m.get("boost_bonus_best_multiplier")
	m.set("boost_bonus_best_multiplier", 2.5)
	m.call("_show_boost_hint")
	await process_frame
	var probed: String = str(popup.call("_row_label", 2))
	print("  best_multiplier 2.5 -> %s" % probed)
	if probed != "×3.5":
		_fail("배율을 2.5 로 바꿨는데 안내는 %s 라고 한다 — 숫자가 박혀 있다" % probed)
	m.set("boost_bonus_best_multiplier", was_best)
	popup.visible = false

	# 그리고 그림도 문턱을 따라가는가.
	var was_thr: float = m.get("boost_bonus_best_threshold")
	var before_fill: float = float(popup.call("_row_remaining", 2))
	m.set("boost_bonus_best_threshold", 0.80)
	m.call("_show_boost_hint")
	await process_frame
	var after_fill: float = float(popup.call("_row_remaining", 2))
	print("  best_threshold 0.48 -> 0.80 일 때 셋째 줄 게이지 %.2f -> %.2f" % [
		before_fill, after_fill])
	if after_fill <= before_fill + 0.01:
		_fail("문턱을 올렸는데 안내 그림의 게이지가 안 따라왔다")
	m.set("boost_bonus_best_threshold", was_thr)
	popup.visible = false

	_restore_save()
	print("")
	if fails == 0:
		print("check_boost_hint: OK")
	else:
		print("check_boost_hint: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
