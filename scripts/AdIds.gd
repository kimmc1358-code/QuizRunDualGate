class_name AdIds
extends RefCounted

## AdMob 광고 단위 ID 를 모아 둔 한 곳, 그리고 실제 단위가 테스트 빌드로
## 새어 나가지 못하게 막는 잠금장치.
##
## 이 파일이 존재하는 이유는 정리정돈이 아니라 사고 방지다. 자기 앱의 실제
## 광고를 자기가(또는 지인이) 클릭하면 Google 은 무효 트래픽으로 보고, 반복되면
## AdMob 계정을 정지시킨다. 정지되면 이 게임만이 아니라 같은 계정으로 낼 앞으로의
## 모든 앱이 같이 막힌다. 의도는 참작되지 않는다 — 테스트하다 잘못 누른 것도
## 포함이다.
##
## 그래서 "테스트할 때는 테스트 ID 로 바꿔 두기"를 사람의 기억에 맡기지 않는다.
## 실제 사고는 거의 전부 출시 준비하며 실제 ID 를 넣어 두고 그 빌드로 한 번 더
## 돌려 보는 데서 난다. 아래 두 겹의 잠금은 그걸 불가능하게 만든다:
##
##   1. FORCE_TEST_ADS 가 켜져 있으면 무조건 테스트 단위
##   2. 꺼져 있어도, 디버그 빌드면 무조건 테스트 단위
##
## 실제 광고가 나가려면 둘 다 통과해야 한다. 출시 직전에 1번을 끄는 것이
## 유일한 수동 조작이고, 그 한 줄은 커밋으로 남는다.
##
## 아직 이 프로젝트에 광고 SDK 는 없다. 여기 있는 것은 SDK 가 붙었을 때
## 부르는 쪽이 물어볼 창구뿐이다 — Main 의 _ad_try_interstitial 과
## ModeSelectScreen.set_banner_reserve 참고.


## Google 이 공개한 데모 단위. 어떤 계정에도 묶여 있지 않고, 항상 "Test Ad"
## 라벨이 붙은 가짜 광고를 내주며, 몇 번을 눌러도 아무 기록이 남지 않는다.
##
## 기기 등록이 필요 없다는 점이 중요하다 — 실제 단위 + 테스트 기기 등록 방식은
## 등록하지 않은 지인의 폰에서 진짜 광고를 내보내므로 배포 테스트에 쓸 수 없다.
##
## 앱 ID 만 '~' 로 나뉘고 광고 단위는 '/' 로 나뉜다. 둘을 바꿔 넣는 것이
## 흔한 실수인데, 증상이 "광고가 그냥 안 나온다" 라서 원인을 찾기 어렵다.
## check_ad_ids.gd 가 이 모양을 검사한다.
const TEST_APP_ID := "ca-app-pub-3940256099942544~3347511713"
const TEST_BANNER := "ca-app-pub-3940256099942544/6300978111"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"

## AdMob 콘솔에서 만든 실제 단위. 채우고 나서도 FORCE_TEST_ADS 가 켜져 있는 한
## 아무 데도 쓰이지 않는다 — 미리 채워 둬도 안전하다는 뜻이다.
const LIVE_APP_ID := ""
const LIVE_BANNER := ""
const LIVE_INTERSTITIAL := ""
const LIVE_REWARDED := ""

## 출시 준비가 끝나면 이 한 줄을 false 로 바꾼다. 그때까지는 릴리스 빌드로 뽑아도
## 테스트 광고만 나간다.
##
## 기본값이 true 인 쪽이 맞다. 잘못 걸렸을 때 잃는 것이 다르기 때문이다 —
## 켜져 있는데 출시하면 수익이 0 이 되고 "Test Ad" 딱지가 보이는 정도지만,
## 꺼져 있는데 테스트하면 계정을 잃는다.
const FORCE_TEST_ADS := true


## 지금 이 빌드가 테스트 광고를 써야 하는가.
static func use_test_ads() -> bool:
	return FORCE_TEST_ADS or OS.is_debug_build()


## 지금 모드에서 쓸 앱 ID. 없으면 빈 문자열.
static func app_id() -> String:
	return TEST_APP_ID if use_test_ads() else LIVE_APP_ID.strip_edges()


## 하단 배너 단위.
static func banner_id() -> String:
	return TEST_BANNER if use_test_ads() else LIVE_BANNER.strip_edges()


## 재시작 N 회마다 나가는 전면광고 단위.
static func interstitial_id() -> String:
	return TEST_INTERSTITIAL if use_test_ads() else LIVE_INTERSTITIAL.strip_edges()


## 부활 팝업의 리워드 광고 단위.
static func rewarded_id() -> String:
	return TEST_REWARDED if use_test_ads() else LIVE_REWARDED.strip_edges()


## 광고를 띄울 수 있는 상태인가 — 네 값이 모두 채워져 있어야 한다.
##
## 실제 모드인데 값이 비어 있으면 광고를 아예 띄우지 않는다. 그 자리에 테스트
## 광고를 대신 내보내는 선택지도 있지만, 그러면 실제 사용자에게 "Test Ad" 가
## 보이면서도 아무도 눈치채지 못한 채 수익만 0 이 된다. 안 나오는 편이 낫다.
static func is_configured() -> bool:
	for id in [app_id(), banner_id(), interstitial_id(), rewarded_id()]:
		if id.strip_edges().is_empty():
			return false
	return true


## 로그에 남길 한 줄. SDK 를 붙일 때 초기화 직후 찍어 두면, 어떤 빌드가 어느
## 모드로 돌았는지가 나중에 확인 가능해진다.
static func describe() -> String:
	if use_test_ads():
		var why: String = "FORCE_TEST_ADS" if FORCE_TEST_ADS else "debug build"
		return "AdIds: TEST ads (%s) — 실제 단위는 쓰이지 않는다" % why
	if not is_configured():
		return "AdIds: LIVE mode 인데 단위가 비어 있다 — 광고를 띄우지 않는다"
	return "AdIds: LIVE ads"
