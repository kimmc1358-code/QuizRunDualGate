class_name ShareSheet
extends RefCounted

## 안드로이드의 공유 창을 연다 — 이미지 한 장과 문구 한 줄.
##
## 플러그인 없이 JavaClassWrapper 와 AndroidRuntime 싱글턴으로 부른다(Godot
## 4.4 부터 되는 길). 자바 생성자는 클래스 이름을 메서드처럼 부르면 된다
## (Intent.Intent(), File.File(path)).
##
## 이미지를 다른 앱에 넘기는 권한은 Godot 의 안드로이드 라이브러리가 이미
## 선언해 둔 FileProvider 를 빌린다. authority 는 "<패키지명>.fileprovider"
## 이고 허용 경로에 앱 내부 저장소 전체(files-path "/")가 들어 있어, user://
## 에 둔 파일을 그대로 넘길 수 있다. 둘 다 godot-lib AAR 의 매니페스트와
## res/xml/godot_provider_paths.xml 에서 읽은 값이다 — 우리 매니페스트에는
## 아무것도 더하지 않는다.
##
## 이 파일에 번역할 글자는 없다. 인텐트 이름들이 글자 상수처럼 생겨서
## check_translations.gd 의 검사 목록(UI_SCRIPTS)에서 뺐다.

const ACTION_SEND := "android.intent.action.SEND"
const ACTION_CHOOSER := "android.intent.action.CHOOSER"
const EXTRA_STREAM := "android.intent.extra.STREAM"
const EXTRA_TEXT := "android.intent.extra.TEXT"
const EXTRA_INTENT := "android.intent.extra.INTENT"
const EXTRA_TITLE := "android.intent.extra.TITLE"
const FLAG_GRANT_READ_URI_PERMISSION := 1
const MIME_PNG := "image/png"
const PROVIDER_SUFFIX := ".fileprovider"


## 이 기기에서 공유 창을 열 수 있는가. PC 와 헤드리스에서는 false.
static func available() -> bool:
	return Engine.has_singleton("AndroidRuntime")


## 공유 창을 띄웠으면 true. 안드로이드가 아니거나 자바 쪽이 도중에 실패하면
## 경고를 남기고 false.
##
## Intent.createChooser 대신 ACTION_CHOOSER 인텐트를 직접 만든다. createChooser
## 의 제목 인자는 CharSequence 라, GDScript 문자열이 그 자리에 맞춰 불리는지
## 장담할 수 없다. putExtra(String, String) 은 확실히 있다. 받는 앱이 이미지를
## 읽을 권한은 안드로이드가 startActivity 때 EXTRA_STREAM 을 ClipData 로 옮기며
## 넘겨 준다(Intent.migrateExtraStreamToClipData — 선택창 안의 인텐트까지 본다).
static func share_image(absolute_path: String, text: String, title: String) -> bool:
	if not available():
		return false
	var runtime = Engine.get_singleton("AndroidRuntime")
	var activity = runtime.getActivity()
	var context = runtime.getApplicationContext()
	if activity == null or context == null:
		return _fail("no activity or context")

	var file_class: JavaClass = JavaClassWrapper.wrap("java.io.File")
	var provider_class: JavaClass = JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var intent_class: JavaClass = JavaClassWrapper.wrap("android.content.Intent")
	if file_class == null or provider_class == null or intent_class == null:
		return _fail("could not wrap File, FileProvider or Intent")

	var file = file_class.File(absolute_path)
	var authority: String = str(context.getPackageName()) + PROVIDER_SUFFIX
	var uri = provider_class.getUriForFile(context, authority, file)
	if uri == null:
		return _fail("FileProvider %s gave no uri for %s" % [authority, absolute_path])

	var send = intent_class.Intent(ACTION_SEND)
	send.setType(MIME_PNG)
	send.putExtra(EXTRA_STREAM, uri)
	send.putExtra(EXTRA_TEXT, text)
	send.addFlags(FLAG_GRANT_READ_URI_PERMISSION)
	var chooser = intent_class.Intent(ACTION_CHOOSER)
	chooser.putExtra(EXTRA_INTENT, send)
	chooser.putExtra(EXTRA_TITLE, title)
	chooser.addFlags(FLAG_GRANT_READ_URI_PERMISSION)
	if JavaClassWrapper.get_exception() != null:
		return _fail("building the intent")

	# 액티비티를 여는 일은 안드로이드 UI 스레드에서 한다.
	var open_sheet := func() -> void:
		activity.startActivity(chooser)
	activity.runOnUiThread(runtime.createRunnableFromGodotCallable(open_sheet))
	if JavaClassWrapper.get_exception() != null:
		return _fail("starting the share sheet")
	return true


static func _fail(what: String) -> bool:
	var exception = JavaClassWrapper.get_exception()
	push_warning("share: %s%s" % [what, "" if exception == null else " — %s" % str(exception)])
	return false
