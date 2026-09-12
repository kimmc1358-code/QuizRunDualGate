extends SceneTree

# 실제 광고 단위가 테스트 빌드로 새어 나가지 않는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ad_ids.gd
#
# 이 프로젝트에서 대가가 가장 큰 규칙이다. 자기 앱의 실제 광고를 자기나 지인이
# 클릭하면 Google 은 무효 트래픽으로 보고 AdMob 계정을 정지시키며, 정지되면 같은
# 계정으로 낼 앞으로의 모든 앱이 함께 막힌다. 그런데 화면에 나타나는 증상은
# "광고가 나온다" 뿐이다 — 테스트 광고와 실제 광고는 라벨 하나 차이라, 잘못된
# 빌드를 손에 들고도 몇 주 동안 모를 수 있다.
#
# 보는 것:
#   1. 지금 빌드가 어느 모드인지, 그리고 그 모드에 맞는 값이 실제로 나오는지.
#   2. 테스트 모드에서 네 창구가 전부 TEST_* 를 돌려주는지 — 하나라도 LIVE_* 에
#      물려 있으면 여기서 걸린다.
#   3. 실제 모드라면 네 값이 다 채워져 있고 테스트 값과 같지 않은지.
#   4. ID 모양. 앱 ID 만 '~' 로 나뉘고 단위는 '/' 로 나뉜다. 바꿔 넣으면 광고가
#      그냥 안 나오는데, 그 증상으로는 원인을 못 찾는다.
#   5. 테스트 ID 가 Google 이 공개한 데모 값 그대로인지. 한 글자 틀리면 역시
#      조용히 안 나온다. 아래 표는 AdIds 의 복사본이 아니라 바깥 기준값이므로,
#      AdIds 만 고치면 여기서 걸리는 것이 맞는 동작이다.

# https://developers.google.com/admob/android/test-ads
const GOOGLE_DEMO := {
	"app": "ca-app-pub-3940256099942544~3347511713",
	"banner": "ca-app-pub-3940256099942544/6300978111",
	"interstitial": "ca-app-pub-3940256099942544/1033173712",
	"rewarded": "ca-app-pub-3940256099942544/5224354917",
}

var fails := 0


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)


func _shape(label: String, id: String, is_app: bool) -> void:
	if not id.begins_with("ca-app-pub-"):
		_fail("%s 가 'ca-app-pub-' 로 시작하지 않는다: '%s'" % [label, id])
		return
	if is_app:
		if not id.contains("~") or id.contains("/"):
			_fail("%s 는 앱 ID 라 '~' 로 나뉘어야 한다: '%s'" % [label, id])
	else:
		if not id.contains("/") or id.contains("~"):
			_fail("%s 는 광고 단위라 '/' 로 나뉘어야 한다 (앱 ID 를 넣지 않았는지): '%s'" % [label, id])


# ---- 6. 매니페스트에 들어갈 앱 ID ----
#
# 광고 앱 ID 는 AdIds 가 아니라 AdmobPlugin 이 빌드 때 이 파일에서 읽어
# 매니페스트에 넣는다. AdIds 의 잠금이 아무리 단단해도 이 파일이 실제 앱 ID 를
# 들고 있으면 APK 는 실제 앱으로 나간다. 파일이 없거나 키가 빠지면 플러그인은
# 조용히 씬의 Admob 노드를 찾으러 가므로, "있고, 읽히고, 값이 맞다"까지 본다.
const EXPORT_CFG := "res://addons/AdmobPlugin/android_export.cfg"


func _check_export_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(EXPORT_CFG) != OK:
		_fail("%s 를 읽지 못했다 — 플러그인이 씬에서 앱 ID 를 찾다가 빈 채로 빌드된다" % EXPORT_CFG)
		return
	for key in [["General", "is_real"], ["Debug", "app_id"], ["Release", "app_id"]]:
		if not cfg.has_section_key(key[0], key[1]):
			_fail("%s 에 [%s] %s 가 없다 — 플러그인이 이 파일을 버리고 씬을 뒤진다" % [EXPORT_CFG, key[0], key[1]])
			return
	var is_real: bool = cfg.get_value("General", "is_real")
	var debug_app: String = cfg.get_value("Debug", "app_id")
	var release_app: String = cfg.get_value("Release", "app_id")
	print("  export cfg    is_real=%s  debug=%s  release=%s" % [is_real, debug_app, release_app])
	if AdIds.use_test_ads():
		if is_real:
			_fail("테스트 모드인데 %s 의 is_real 이 true 다 — APK 가 Release 앱 ID 를 단다" % EXPORT_CFG)
		for pair in [["Debug", debug_app], ["Release", release_app]]:
			if pair[1] != GOOGLE_DEMO["app"]:
				_fail("테스트 모드인데 %s 의 [%s] app_id 가 Google 테스트 앱 ID 가 아니다: '%s'" % [
					EXPORT_CFG, pair[0], pair[1]])
	else:
		if not is_real:
			_fail("LIVE 모드인데 %s 의 is_real 이 false 다 — 테스트 앱 ID 로 나간다" % EXPORT_CFG)
		if release_app != AdIds.LIVE_APP_ID.strip_edges():
			_fail("%s 의 [Release] app_id 가 AdIds.LIVE_APP_ID 와 다르다" % EXPORT_CFG)


# ---- 7. 실행 중 광고 단위 ----
#
# 게임이 실제로 쓰는 노드는 Ads.make_admob_node 가 만든다. 같은 함수로 하나
# 만들어 들여다본다 — 테스트 모드면 is_real 이 꺼져 있고, 실제 칸은 전부 비어
# 있어야 한다. is_real 이 어쩌다 켜져도 빈 단위라 아무것도 못 불러오게 하는 두
# 번째 벽이다.
func _check_admob_node() -> void:
	var script: Script = load(Ads.ADMOB_SCRIPT)
	if script == null:
		_fail("%s 가 없다 — 플러그인이 빠졌다" % Ads.ADMOB_SCRIPT)
		return
	var ads := Ads.new()
	var node: Node = ads.make_admob_node(script)
	var reals := []
	for prop in node.get_property_list():
		var name: String = prop.name
		if name.begins_with("android_real_") and name.ends_with("_id"):
			reals.append(name)
	if reals.is_empty():
		_fail("Admob 노드에서 android_real_*_id 속성을 하나도 못 찾았다 — 플러그인이 바뀌었나")
	if AdIds.use_test_ads():
		if node.get("is_real"):
			_fail("테스트 모드인데 광고 노드의 is_real 이 켜져 있다")
		for name in reals:
			if str(node.get(name)) != "":
				_fail("테스트 모드인데 광고 노드의 %s 에 값이 있다: '%s'" % [name, node.get(name)])
		for pair in [["android_debug_banner_id", "banner"], ["android_debug_interstitial_id", "interstitial"],
				["android_debug_rewarded_id", "rewarded"], ["android_debug_application_id", "app"]]:
			if str(node.get(pair[0])) != GOOGLE_DEMO[pair[1]]:
				_fail("광고 노드의 %s 가 Google 데모 값이 아니다: '%s'" % [pair[0], node.get(pair[0])])
		if fails == 0:
			print("  admob node    is_real=false, %d real unit fields empty, debug units = Google demo" % reals.size())
	else:
		if not node.get("is_real"):
			_fail("LIVE 모드인데 광고 노드의 is_real 이 꺼져 있다")
	node.free()
	ads.free()


# ---- 8. 씬에 박힌 Admob 노드가 없는가 ----
#
# 게임은 노드를 코드로 만든다. 누가 씬에 Admob 노드를 끌어다 놓으면, 설정
# 파일이 깨졌을 때 플러그인이 그 노드의 인스펙터 값(실제 앱 ID 가 들어 있을 수
# 있다)으로 빌드한다. 그 길 자체를 없애 둔다.
func _check_no_scene_node() -> void:
	var found := []
	_scan_scenes("res://", found)
	for path in found:
		_fail("%s 에 Admob 노드가 있다 — Ads.gd 가 만드는 노드 하나만 있어야 한다" % path)


func _scan_scenes(dir: String, found: Array) -> void:
	if dir.begins_with("res://addons") or dir.begins_with("res://android") or dir.begins_with("res://.godot"):
		return
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			var text := FileAccess.get_file_as_string(dir.path_join(file))
			if text.contains("AdmobPlugin/Admob.gd"):
				found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_scan_scenes(dir.path_join(sub), found)


func _init() -> void:
	print("check_ad_ids: %s" % AdIds.describe())
	print("  FORCE_TEST_ADS=%s  is_debug_build=%s  ->  use_test_ads=%s" % [
		AdIds.FORCE_TEST_ADS, OS.is_debug_build(), AdIds.use_test_ads()])
	print("")

	var got := {
		"app": AdIds.app_id(),
		"banner": AdIds.banner_id(),
		"interstitial": AdIds.interstitial_id(),
		"rewarded": AdIds.rewarded_id(),
	}
	var live := {
		"app": AdIds.LIVE_APP_ID.strip_edges(),
		"banner": AdIds.LIVE_BANNER.strip_edges(),
		"interstitial": AdIds.LIVE_INTERSTITIAL.strip_edges(),
		"rewarded": AdIds.LIVE_REWARDED.strip_edges(),
	}
	var test := {
		"app": AdIds.TEST_APP_ID,
		"banner": AdIds.TEST_BANNER,
		"interstitial": AdIds.TEST_INTERSTITIAL,
		"rewarded": AdIds.TEST_REWARDED,
	}

	for key in ["app", "banner", "interstitial", "rewarded"]:
		print("  %-13s %s" % [key, got[key] if got[key] != "" else "(비어 있음)"])
	print("")

	# ---- 4+5. 테스트 상수 자체가 성한가 ----
	for key in GOOGLE_DEMO:
		_shape("TEST " + key, test[key], key == "app")
		if test[key] != GOOGLE_DEMO[key]:
			_fail("TEST %s 가 Google 데모 값과 다르다\n        AdIds:  %s\n        Google: %s" % [
				key, test[key], GOOGLE_DEMO[key]])

	if AdIds.use_test_ads():
		# ---- 2. 테스트 모드: 네 창구가 전부 테스트 값이어야 한다 ----
		for key in got:
			if got[key] != test[key]:
				_fail("테스트 모드인데 %s 창구가 테스트 값을 안 돌려준다 — '%s'%s" % [
					key, got[key],
					" (실제 단위다!)" if live[key] != "" and got[key] == live[key] else ""])
		if not AdIds.is_configured():
			_fail("테스트 모드인데 is_configured() 가 false 다 — 테스트 상수 중 빈 것이 있다")
		if fails == 0:
			print("  테스트 모드: 네 창구 모두 Google 데모 단위. 실제 단위는 나가지 않는다.")
	else:
		# ---- 3. 실제 모드: 의도한 것인지 값으로 확인한다 ----
		print("  ** LIVE 모드다. 실제 사용자에게 실제 광고가 나간다. **")
		for key in got:
			if live[key] == "":
				_fail("LIVE 모드인데 %s 실제 단위가 비어 있다" % key)
			elif live[key] == test[key]:
				_fail("LIVE %s 에 테스트 단위가 들어가 있다 — 수익이 0 이 되고 사용자에게 'Test Ad' 가 보인다" % key)
			else:
				_shape("LIVE " + key, live[key], key == "app")
		if not AdIds.is_configured():
			_fail("LIVE 모드인데 is_configured() 가 false 다 — 이 상태로는 광고가 아예 안 나간다")

	_check_export_config()
	_check_admob_node()
	_check_no_scene_node()

	print("")
	if fails == 0:
		print("check_ad_ids: OK")
	else:
		print("check_ad_ids: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
