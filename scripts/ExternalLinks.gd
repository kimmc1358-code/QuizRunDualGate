class_name ExternalLinks
extends RefCounted

## 앱 밖으로 나가는 주소를 모아 둔 한 곳.
##
## 문서가 준비되면 아래 세 값만 채우면 된다 — 부르는 쪽(Main 의
## _on_privacy_pressed / _on_terms_pressed / _on_contact_pressed)은 손댈 것이
## 없다. 주소를 그 함수들 안에 직접 적으면 세 군데에 흩어지고, 그중 하나를
## 빠뜨렸는지는 눌러 보기 전까지 알 수 없다.
##
## 아직 비어 있다. 빈 값은 "준비 안 됨"이라는 뜻이고, 그 상태에서는 설정
## 화면의 해당 줄이 흐리게 나오고 눌러도 아무 일도 일어나지 않는다
## (SettingsPopup._link_enabled). 죽은 링크를 멀쩡한 얼굴로 보여 주는 것보다
## 낫다 — 지인 테스트에서 눌러 볼 것이 뻔한 자리다.

## 개인정보 처리방침. Play 스토어 등록에도 호스팅된 주소가 따로 필요하므로,
## 그때 쓰는 것과 같은 주소를 여기에도 넣으면 된다.
const PRIVACY_POLICY_URL := ""

## 이용약관.
const TERMS_OF_SERVICE_URL := ""

## 문의/피드백을 받을 주소. 여기에 메일 주소를 넣으면 mailto 로 열린다.
## 스튜디오 공용 주소를 쓸지 개인 주소를 쓸지는 정해지지 않았다.
const CONTACT_EMAIL := ""

## 메일 앱이 미리 채워 줄 제목. 여러 앱에서 온 문의가 섞이지 않게 앱 이름을
## 넣어 둔다.
const CONTACT_SUBJECT := "QuizRun: Dual Gate - Feedback"


## 채워져 있는가. 공백만 있는 값도 비어 있는 것으로 본다 — 주소를 지우다 만
## 상태로 커밋되면 눌렀을 때 브라우저가 빈 탭을 여는 쪽이 더 헷갈린다.
static func is_set(value: String) -> bool:
	return not value.strip_edges().is_empty()


## 문의 메일 주소를 mailto URL 로. 주소가 없으면 빈 문자열.
static func contact_url() -> String:
	if not is_set(CONTACT_EMAIL):
		return ""
	return "mailto:%s?subject=%s" % [
		CONTACT_EMAIL.strip_edges(), CONTACT_SUBJECT.uri_encode()]


## 주소를 기기의 기본 앱으로 연다. 열었으면 true.
##
## 비어 있으면 아무것도 하지 않는다. OS.shell_open("") 은 플랫폼마다 다르게
## 굴고, 안드로이드에서는 빈 인텐트로 앱 선택창이 뜨기도 한다.
static func open(url: String) -> bool:
	if not is_set(url):
		push_warning("ExternalLinks: 주소가 비어 있어 열지 않았다 — scripts/ExternalLinks.gd 를 채울 것")
		return false
	var err := OS.shell_open(url.strip_edges())
	if err != OK:
		push_warning("ExternalLinks: %s 를 열지 못했다 (error %d)" % [url, err])
		return false
	return true
