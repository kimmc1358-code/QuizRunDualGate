extends SceneTree

# 광고용 숏츠 영상을 찍는다. 게임이 스스로 정답 게이트로만 날며, Godot 의 Movie
# Maker 가 소리까지 프레임 하나 놓치지 않고 저장한다.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1080x1920 --fixed-fps 60 \
#       --write-movie <dir>/sky.png --script res://tools/capture_promo.gd -- --mode 0 --seconds 11 --lang en
#
# --write-movie 가 .png 면 무손실 프레임 + 같은 이름의 .wav 가 나온다. 자르고 잇는
# 것은 ffmpeg 몫이다 — 이 스크립트는 통과한 순간을 초 단위로 찍어 주므로, 그걸 보고
# 어디부터 어디를 쓸지 정한다.
#
# Movie Maker 는 실시간이 아니라 고정 프레임으로 돈다. PC 가 느려도 영상은 60fps
# 그대로고, 매 프레임 delta 가 1/60 이라 조종도 실제 게임과 같은 물리로 한다.
#
# 조종: 정답 칸 가운데보다 TAP_BELOW_PX 만큼 아래로 내려가면 탭한다. 탭 한 번에
# 45px 오르고(300²/2·1000) 다시 떨어지므로, 캐릭터는 정답 칸 가운데를 위아래 ±22px
# 로 오간다 — 판정 여유(초반 구멍 1.2배에서 ±49px)에 넉넉히 들어간다. 멀리 아래면
# 쿨다운만 지키며 연타해 빨리 오른다. 탭은 게임의 _unhandled_input 으로 넣어서,
# 실제 탭과 똑같이 소리와 반짝이가 난다.
#
# 부스트는 게이트마다 계획(--plan)을 따른다. 내내 누르면 모든 게이트가 TURBO! 로
# 끝나 영상이 한 가지로만 보였다. full 은 게이트가 생길 때부터 눌러 바가 절반
# 남고(TURBO!, x2), half 는 바가 절반 남았을 때 눌러 나머지 절반을 반 시간에
# 와서 1/4 쯤 남고(BOOST!, x1.5), none 은 누르지 않아 보너스 없이 평소 속도로
# 지난다. 평소 속도가 섞여야 누르는 순간의 가속도 눈에 띈다.
#
# 판을 시작하고 게이트를 지나므로 광고 카운터, 도감, 해금 진행도가 세이브 파일에
# 적힌다. 파일 전체를 받아 두었다가 끝에 되돌린다(체커들과 같은 이유).

const SAVE_PATH := "user://savegame.cfg"
const TAP_BELOW_PX := 20.0     # 정답 칸 가운데보다 이만큼 내려가면 탭
const FAR_BELOW_PX := 60.0     # 이보다 멀면 상승 중이어도 연타
const TAP_COOLDOWN := 0.12
const RISING_FAST := -60.0     # 이보다 빠르게 오르는 중이면 가까울 때는 참는다

var mode := 0
var seconds := 11.0
var plan := PackedStringArray(["full", "none", "half"])   # 게이트마다 돌아가며
var lang := ""   # "en" 이나 "ko". 비우면 이 PC 에 저장된 언어 그대로
var main: Node2D
var _save := PackedByteArray()
var _had_save := false
var _t := 0.0
var _last_tap := -10.0
var _boosting := false
var _remaining := 1.0   # 직전 프레임의 부스트 바 — 통과한 게이트가 어느 등급이었는지 알려 준다


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		match args[i]:
			"--mode": mode = int(args[i + 1])
			"--seconds": seconds = float(args[i + 1])
			"--plan": plan = args[i + 1].split(",")
			"--lang": lang = args[i + 1]
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save = FileAccess.get_file_as_bytes(SAVE_PATH)
	main = load("res://scenes/Main.tscn").instantiate()
	root.call_deferred("add_child", main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	while main.get("boot_pending"):
		await process_frame
	main.set("tutorial_seen", true)
	# 언어를 바꾸면 화면이 다시 지어지고 선택이 세이브에 적힌다 — 끝에 되돌린다.
	if lang != "":
		main.call("set_language_korean", lang == "ko")
	# 부스트 버튼은 게임 기본값인 오른쪽에. 왼쪽이면 아래 칸으로 내려간 캐릭터(화면
	# 왼쪽 PLAYER_X)가 버튼 뒤로 숨는다. 세이브에 적히지만 끝에 되돌린다.
	main.call("set_boost_button_on_left", false)
	main.call("_apply_mode", mode)
	main.set("current_mode", mode)
	main.call("_reset_game")
	main.set("current_mode", mode)
	main.call("_start_countdown")

	var total := int(round(seconds * 60.0))
	var played := false
	var passed_before: int = main.get("gates_passed")
	var passes: Array = []
	var play_start := -1.0
	for frame in range(total):
		await process_frame
		_t = float(frame + 1) / 60.0
		var state: int = main.get("state")
		if state == main.State.PLAYING:
			if not played:
				played = true
				play_start = _t
			var passed: int = main.get("gates_passed")
			if passed != passed_before:
				passes.append("%.2f %s" % [_t, _tier(_remaining)])
				passed_before = passed
			# 통과 확인이 먼저다. _drive 가 바를 새 게이트 값으로 읽기 전에, 직전 프레임의
			# 바로 이번 게이트의 등급을 매긴다.
			_drive()
		elif played and state != main.State.COUNTDOWN:
			print("promo: DIED at %.2fs — this take is no good" % _t)
			break

	if _boosting:
		main.call("_on_boost_released")
	print("promo: mode %d, play starts %.2fs, gates passed at %s" % [mode, play_start, str(passes)])
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save)
		f.close()
	quit(0)


func _drive() -> void:
	var step: String = plan[int(main.get("gates_passed")) % plan.size()]
	var remaining: float = main.call("_boost_bar_remaining")
	var want: bool = step == "full" or (step == "half" and remaining <= 0.5)
	if want and not _boosting:
		main.call("_on_boost_pressed")
		_boosting = true
	elif not want and _boosting:
		main.call("_on_boost_released")
		_boosting = false
	_remaining = remaining
	var g = _next_gate()
	if g == null:
		return
	var target: float = ((g.top_zone_top + g.top_zone_bottom) if g.top_correct \
		else (g.bottom_zone_top + g.bottom_zone_bottom)) * 0.5
	var y: float = main.get("player_y")
	var v: float = main.get("player_vel")
	if _t - _last_tap < TAP_COOLDOWN:
		return
	var below: float = y - target
	if below > FAR_BELOW_PX or (below > TAP_BELOW_PX and v > RISING_FAST):
		_tap()


func _tier(remaining: float) -> String:
	if remaining >= float(main.get("boost_bonus_best_threshold")):
		return "TURBO"
	if remaining >= float(main.get("boost_bonus_mid_threshold")):
		return "BOOST"
	return "plain"


# 아직 판정 안 된 게이트 중 가장 앞의 것.
func _next_gate():
	var best = null
	for g in main.get("gates"):
		if g.resolved:
			continue
		if best == null or g.x < best.x:
			best = g
	return best


func _tap() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(240, 300)
	main.call("_unhandled_input", ev)
	_last_tap = _t
