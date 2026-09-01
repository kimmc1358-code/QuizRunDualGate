extends SceneTree

# 팝업 아트를 미리 구워 assets/ui_assets/popup/baked/ 에 저장한다.
#
#   godot --headless --path . --script tools/bake_popup_art.gd
#   godot --headless --path . --import        (구운 PNG 를 임포트)
#
# 왜 필요한가: PopupBase._nine_patch / _load_icon_from 은 픽셀 단위 처리를
# GDScript 로 돌린다. 결과는 좋지만 느려서, 팝업 셋을 만드는 데만 부팅에서
# 9.6초가 걸렸다(게임오버 팝업 혼자 6.6초). 계산 코드는 그대로 두고 결과만
# 파일로 남겨, 런타임에는 읽기만 하게 한다.
#
# 아트를 바꾸거나 크기 상수를 바꾸면 다시 돌려야 한다. 캐시 키에 파일명과
# 크기가 들어가므로, 안 맞는 항목은 그냥 무시되고 예전처럼 계산으로 떨어진다
# (느려질 뿐 깨지지는 않는다).

const POPUP_BASE := "res://scripts/PopupBase.gd"


func _init() -> void:
	var base = load(POPUP_BASE)
	base.bake_writing = true
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# 팝업 조립은 로고 화면이 끝난 뒤 _boot_load 에서 일어난다(부팅을 늦추지
	# 않으려고 미뤄 둔 것). 그러니 여기서는 그게 끝날 때까지 돌려 준다 —
	# 두 프레임만 기다리면 아무것도 안 구워진 채로 끝난다.
	var frames := 0
	while main.get("boot_pending") and frames < 600:
		await process_frame
		frames += 1
	if main.get("boot_pending"):
		printerr("부팅이 끝나지 않았다 — 구울 것이 없다")
		quit(1)
		return
	await process_frame
	base.bake_flush()
	print("완료")
	quit(0)
