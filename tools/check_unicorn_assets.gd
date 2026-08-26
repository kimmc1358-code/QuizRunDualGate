extends SceneTree

# DREAM 모드 유니콘 아트 점검용. 파일을 넣은 뒤 실행하면 3개 파일의 존재 여부,
# 시트 해상도, 격자 분할이 딱 떨어지는지, 4개 모드 전부 캐릭터가 보이는 상태인지
# 확인해 준다. 아직 없는 파일은 SKY 아트로 대체되며 그 사실도 함께 출력한다.
#
#   godot --headless --path . --script res://tools/check_unicorn_assets.gd
var main: Node = null
var frames := 0
var out_dir := ""


func _initialize() -> void:
	out_dir = OS.get_environment("OCEAN_SHOT_DIR")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames != 8:
		if frames > 200:
			quit(1)
		return false

	var M = load("res://scripts/Main.gd")
	var d: int = M.Mode.DREAM
	var dir: String = M.MODE_CHARACTER_DIR[d]
	print("=== DREAM 캐릭터 폴더: %s ===" % dir)
	var ok := true
	for f in [M.MODE_CHARACTER_FLY_FILE[d], M.MODE_CHARACTER_HAPPY_FILE[d], M.MODE_CHARACTER_SAD_FILE[d]]:
		var p: String = dir + f
		var exists: bool = ResourceLoader.exists(p)
		var extra := ""
		if exists:
			var tex: Texture2D = load(p)
			extra = " — %dx%d" % [tex.get_width(), tex.get_height()]
			if f == M.MODE_CHARACTER_FLY_FILE[d]:
				var g: Vector2i = M.MODE_CHARACTER_SHEET_GRID[d]
				extra += " → %dx%d 격자, 한 칸 %dx%d" % [g.x, g.y, tex.get_width() / g.x, tex.get_height() / g.y]
				if tex.get_width() % g.x != 0 or tex.get_height() % g.y != 0:
					extra += "  <<< 격자로 나누어떨어지지 않음"
					ok = false
		print("  %-20s %s%s" % [f, "있음" if exists else "없음 (SKY로 대체)", extra])

	for mode in range(4):
		main._apply_mode(mode)
		var label: String = ["SKY", "JUNGLE", "OCEAN", "DREAM"][mode]
		var n: int = main.flap_frames.size()
		print("  %-6s 프레임 %d개 | happy=%s sad=%s" % [
			label, n,
			"O" if main.happy_face_texture != null else "X",
			"O" if main.sad_face_texture != null else "X"])
		if n == 0 or main.happy_face_texture == null or main.sad_face_texture == null:
			ok = false
			print("    !! 캐릭터가 화면에 안 보이는 상태")

	main._apply_mode(M.Mode.DREAM)
	main._set_state(main.State.READY)
	main._on_play_pressed()
	main.state = main.State.PLAYING
	main.player_y = 430.0
	if out_dir != "":
		var img: Image = root.get_texture().get_image()
		img.save_png("%s/dream_character.png" % out_dir)

	print("\nRESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return true
