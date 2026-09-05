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

	print("")
	if fails == 0:
		print("check_ad_ids: OK")
	else:
		print("check_ad_ids: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
