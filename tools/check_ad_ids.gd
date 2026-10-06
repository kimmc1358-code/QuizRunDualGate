extends SceneTree

# 실제 광고 단위가 테스트 빌드로 새어 나가지 않는지, 그리고 출시 빌드에는 실제
# 단위가 빠짐없이 들어가는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_ad_ids.gd
#
# 이 프로젝트에서 대가가 가장 큰 규칙이다. 자기 앱의 실제 광고를 자기나 지인이
# 클릭하면 Google 은 무효 트래픽으로 보고 AdMob 계정을 정지시키며, 정지되면 같은
# 계정으로 낼 앞으로의 모든 앱이 함께 막힌다. 그런데 화면에 나타나는 증상은
# "광고가 나온다" 뿐이다 — 테스트 광고와 실제 광고는 라벨 하나 차이라, 잘못된
# 빌드를 손에 들고도 몇 주 동안 모를 수 있다. 반대쪽 실수도 조용하다 — 출시
# 빌드에 테스트 단위가 들어가면 "Test Ad" 가 뜨고 수익이 0 인데 아무것도 깨지지
# 않는다.
#
# 이 체커는 언제나 에디터(디버그) 실행 파일로 돈다. 그래서 AdIds.use_test_ads()
# 는 여기서 늘 참이고, 그것만 보면 릴리스 빌드가 무엇을 쓸지는 영영 검사되지
# 않는다 — 출시 전 이 체커는 실제 값을 한 번도 본 적이 없었다. 그래서 두 빌드를
# 따로 묻는다:
#
#   디버그 빌드 — AdIds.use_test_ads_in(true), make_admob_node(script, false).
#     FORCE_TEST_ADS 가 어떻든 무조건 Google 데모 단위여야 한다.
#   릴리스 빌드 — AdIds.use_test_ads_in(false), make_admob_node(script, live).
#     FORCE_TEST_ADS 가 켜져 있으면 데모 단위, 꺼져 있으면 실제 단위 넷 전부.
#
# 그 밖에 보는 것:
#   - ID 모양. 앱 ID 만 '~' 로 나뉘고 단위는 '/' 로 나뉜다. 바꿔 넣으면 광고가
#     그냥 안 나오는데, 그 증상으로는 원인을 못 찾는다.
#   - 실제 ID 넷이 한 계정(같은 pub- 번호)에서 나왔는지. 다른 앱의 단위를 붙여
#     넣으면 역시 조용히 안 나온다.
#   - 테스트 ID 가 Google 이 공개한 데모 값 그대로인지. 아래 표는 AdIds 의 복사본이
#     아니라 바깥 기준값이므로, AdIds 만 고치면 여기서 걸리는 것이 맞는 동작이다.

# https://developers.google.com/admob/android/test-ads
const GOOGLE_DEMO := {
	"app": "ca-app-pub-3940256099942544~3347511713",
	"banner": "ca-app-pub-3940256099942544/6300978111",
	"interstitial": "ca-app-pub-3940256099942544/1033173712",
	"rewarded": "ca-app-pub-3940256099942544/5224354917",
}
const KEYS := ["app", "banner", "interstitial", "rewarded"]

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


# 'ca-app-pub-6214…~…' 에서 계정 번호까지만.
func _publisher(id: String) -> String:
	var cut: int = id.find("~") if id.contains("~") else id.find("/")
	return id.substr(0, cut) if cut > 0 else id


func _live() -> Dictionary:
	return {
		"app": AdIds.LIVE_APP_ID.strip_edges(),
		"banner": AdIds.LIVE_BANNER.strip_edges(),
		"interstitial": AdIds.LIVE_INTERSTITIAL.strip_edges(),
		"rewarded": AdIds.LIVE_REWARDED.strip_edges(),
	}


# ---- 매니페스트에 들어갈 앱 ID ----
#
# 광고 앱 ID 는 AdIds 가 아니라 AdmobPlugin 이 빌드 때 이 파일에서 읽어
# 매니페스트에 넣는다. 파일이 없거나 키가 빠지면 플러그인은 조용히 씬의 Admob
# 노드를 찾으러 가므로, "있고, 읽히고, 값이 맞다"까지 본다.
#
# 플러그인은 [Debug]/[Release] 를 빌드 종류로 고르지 않고 is_real 하나로 고른다.
# 그래서 출시 상태에서는 디버그 빌드도 실제 앱 ID 를 단다 — 광고 단위가 데모라
# 실제 광고는 안 나가지만, is_real 이 FORCE_TEST_ADS 와 같이 움직이는지가 곧
# 앱 ID 의 진실이다.
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
	if debug_app != GOOGLE_DEMO["app"]:
		_fail("%s 의 [Debug] app_id 가 Google 테스트 앱 ID 가 아니다: '%s'" % [EXPORT_CFG, debug_app])
	if AdIds.FORCE_TEST_ADS:
		if is_real:
			_fail("FORCE_TEST_ADS 가 켜져 있는데 %s 의 is_real 이 true 다 — APK 가 실제 앱 ID 를 단다" % EXPORT_CFG)
		if release_app != GOOGLE_DEMO["app"]:
			_fail("FORCE_TEST_ADS 가 켜져 있는데 %s 의 [Release] app_id 가 Google 테스트 앱 ID 가 아니다: '%s'" % [
				EXPORT_CFG, release_app])
	else:
		if not is_real:
			_fail("출시 상태인데 %s 의 is_real 이 false 다 — 실제 단위가 테스트 앱 ID 에 붙어 광고가 안 나온다" % EXPORT_CFG)
		if release_app != AdIds.LIVE_APP_ID.strip_edges():
			_fail("%s 의 [Release] app_id 가 AdIds.LIVE_APP_ID 와 다르다: '%s'" % [EXPORT_CFG, release_app])


# ---- 실행 중 광고 단위 ----
#
# 게임이 실제로 쓰는 노드는 Ads.make_admob_node 가 만든다. 같은 함수로 디버그
# 빌드의 노드와 릴리스 빌드의 노드를 하나씩 만들어 들여다본다.
func _check_admob_nodes() -> void:
	var script: Script = load(Ads.ADMOB_SCRIPT)
	if script == null:
		_fail("%s 가 없다 — 플러그인이 빠졌다" % Ads.ADMOB_SCRIPT)
		return
	var ads := Ads.new()
	var debug_node: Node = ads.make_admob_node(script, not AdIds.use_test_ads_in(true))
	var release_node: Node = ads.make_admob_node(script, not AdIds.use_test_ads_in(false))
	var reals := []
	for prop in debug_node.get_property_list():
		var name: String = prop.name
		if name.begins_with("android_real_") and name.ends_with("_id"):
			reals.append(name)
	if reals.is_empty():
		_fail("Admob 노드에서 android_real_*_id 속성을 하나도 못 찾았다 — 플러그인이 바뀌었나")

	# 디버그 빌드: 무조건 데모. 실제 칸은 비어 있어서, is_real 이 어쩌다 켜져도
	# 불러올 것이 없다.
	_expect_test_node("debug build", debug_node, reals)

	if AdIds.FORCE_TEST_ADS:
		_expect_test_node("release build (FORCE_TEST_ADS)", release_node, reals)
	else:
		var live := _live()
		var want := {
			"android_real_application_id": live["app"],
			"android_real_banner_id": live["banner"],
			"android_real_interstitial_id": live["interstitial"],
			"android_real_rewarded_id": live["rewarded"],
		}
		if not release_node.get("is_real"):
			_fail("출시 상태인데 릴리스 빌드의 광고 노드가 is_real 을 끈 채로 만들어진다")
		for name in reals:
			var got: String = str(release_node.get(name))
			if want.has(name):
				if got != want[name]:
					_fail("릴리스 빌드의 %s 가 AdIds 의 실제 값과 다르다: '%s'" % [name, got])
			elif got != "":
				# 안 쓰는 형식(보상형 전면, 앱 오픈, 네이티브)은 비어 있어야 한다.
				_fail("릴리스 빌드에서 안 쓰는 %s 에 값이 있다: '%s'" % [name, got])
		print("  release node  is_real=true, banner/interstitial/rewarded/app = AdIds.LIVE_*")
	debug_node.free()
	release_node.free()
	ads.free()


func _expect_test_node(label: String, node: Node, reals: Array) -> void:
	var before := fails
	if node.get("is_real"):
		_fail("%s 의 광고 노드가 is_real 을 켜고 만들어진다" % label)
	for name in reals:
		if str(node.get(name)) != "":
			_fail("%s 의 광고 노드 %s 에 값이 있다: '%s'" % [label, name, node.get(name)])
	for pair in [["android_debug_banner_id", "banner"], ["android_debug_interstitial_id", "interstitial"],
			["android_debug_rewarded_id", "rewarded"], ["android_debug_application_id", "app"]]:
		if str(node.get(pair[0])) != GOOGLE_DEMO[pair[1]]:
			_fail("%s 의 광고 노드 %s 가 Google 데모 값이 아니다: '%s'" % [label, pair[0], node.get(pair[0])])
	if fails == before:
		print("  %-13s is_real=false, %d real unit fields empty, units = Google demo" % [label.split(" ")[0] + " node", reals.size()])


# ---- 씬에 박힌 Admob 노드가 없는가 ----
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
	print("  FORCE_TEST_ADS=%s  ->  debug builds use test ads: %s, release builds use test ads: %s" % [
		AdIds.FORCE_TEST_ADS, AdIds.use_test_ads_in(true), AdIds.use_test_ads_in(false)])
	if not AdIds.FORCE_TEST_ADS:
		print("  ** 출시 상태다. 릴리스 빌드는 실제 사용자에게 실제 광고를 내보낸다. **")
	print("")

	var test := {
		"app": AdIds.TEST_APP_ID,
		"banner": AdIds.TEST_BANNER,
		"interstitial": AdIds.TEST_INTERSTITIAL,
		"rewarded": AdIds.TEST_REWARDED,
	}
	var live := _live()

	# ---- 테스트 상수 자체가 성한가 ----
	for key in GOOGLE_DEMO:
		_shape("TEST " + key, test[key], key == "app")
		if test[key] != GOOGLE_DEMO[key]:
			_fail("TEST %s 가 Google 데모 값과 다르다\n        AdIds:  %s\n        Google: %s" % [
				key, test[key], GOOGLE_DEMO[key]])

	# ---- 디버그 빌드는 무엇을 하든 테스트 광고 ----
	# 두 번째 잠금. FORCE_TEST_ADS 를 꺼도 이게 남아 있어야, 출시 상태의 코드로
	# 개발하면서 뽑는 디버그 빌드가 계정을 위험하게 만들지 않는다.
	if not AdIds.use_test_ads_in(true):
		_fail("디버그 빌드가 실제 광고를 쓰게 되어 있다 — AdIds 의 두 번째 잠금이 풀렸다")
	# 이 체커 자신이 디버그 빌드이므로, 네 창구가 지금 돌려주는 값이 곧 디버그
	# 빌드가 쓰는 값이다.
	var got := {
		"app": AdIds.app_id(),
		"banner": AdIds.banner_id(),
		"interstitial": AdIds.interstitial_id(),
		"rewarded": AdIds.rewarded_id(),
	}
	if OS.is_debug_build():
		for key in KEYS:
			if got[key] != test[key]:
				_fail("디버그 빌드의 %s 창구가 테스트 값을 안 돌려준다 — '%s'%s" % [
					key, got[key], " (실제 단위다!)" if live[key] != "" and got[key] == live[key] else ""])

	# ---- 실제 값 ----
	if not AdIds.FORCE_TEST_ADS:
		for key in KEYS:
			if live[key] == "":
				_fail("출시 상태인데 %s 실제 단위가 비어 있다 — 릴리스 빌드에서 광고가 아예 안 나간다" % key)
			elif live[key] == test[key]:
				_fail("LIVE %s 에 테스트 단위가 들어가 있다 — 수익이 0 이 되고 사용자에게 'Test Ad' 가 보인다" % key)
	for key in KEYS:
		if live[key] != "":
			_shape("LIVE " + key, live[key], key == "app")
	var publishers := {}
	for key in KEYS:
		if live[key] != "":
			publishers[_publisher(live[key])] = true
	if publishers.size() > 1:
		_fail("실제 ID 넷이 서로 다른 계정에서 나왔다: %s" % [publishers.keys()])
	elif not AdIds.FORCE_TEST_ADS:
		print("  live          4 ids, one account (%s)" % publishers.keys()[0])

	_check_export_config()
	_check_admob_nodes()
	_check_no_scene_node()

	print("")
	if fails == 0:
		print("check_ad_ids: OK")
	else:
		print("check_ad_ids: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
