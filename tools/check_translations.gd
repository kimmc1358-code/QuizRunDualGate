extends SceneTree

# 화면에 나가는 글자 중 번역을 안 거치는 것이 없는지 본다.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/check_translations.gd
#
# 눈으로 찾는 일을 그만두려고 만들었다. 빠진 글자는 오류를 내지 않는다 —
# tr() 은 번역이 없으면 원문을 그대로 돌려주므로, 한국어 화면 한가운데에 영어
# 한 줄이 얌전히 앉아 있을 뿐이다. 지금까지 셋을 그렇게 찾았고(부활 팝업
# 아랫줄, 게임오버의 순위표 줄, 기록까지 남은 점수), 셋 다 값이 끼어드는
# "%s" 문자열이었다. 상수에는 tr() 을 걸어 두고 %-로 만드는 줄에는 잊는 것이
# 이 실수의 모양이다.
#
# 두 가지를 본다.
#
#   1. UI 스크립트의 글자 상수는 ui.csv 에 줄이 있어야 한다. 영어로 두기로
#      한 것은 ENGLISH_ON_PURPOSE 에 이유와 함께 적는다 — 목록에 없으면
#      실패하므로, 새 글자를 넣을 때 "번역할 것인가"를 반드시 한 번 정하게
#      된다.
#   2. 그 상수를 쓰는 줄은 tr() 을 거쳐야 한다. 줄이 있어도 tr() 이 없으면
#      번역은 파일 안에서 잠자기만 한다 — 이게 바로 셋 다 걸렸던 자리다.
#
# 그리고 반대쪽도 본다: ui.csv 에 있는데 아무도 안 쓰는 줄. 오타로 키가
# 어긋나면 번역은 조용히 안 나오고, 남은 줄만 파일에 쌓인다.
#
# Main.gd 는 이 검사에서 뺀다. 거기 글자 상수는 대부분 경로·저장 키·디버그
# 문구라 "화면에 나가는가"를 글로는 가릴 수 없다. 대신 2번(쓰는 줄이 tr() 을
# 거치는가)은 scripts/ 전체에 건다.

const CSV_PATH := "res://assets/i18n/ui.csv"
const UI_SCRIPTS := [
	"res://scripts/GameOverPopup.gd",
	"res://scripts/RevivePopup.gd",
	"res://scripts/PausePopup.gd",
	"res://scripts/SettingsPopup.gd",
	"res://scripts/AboutPopup.gd",
	"res://scripts/ModeSelectScreen.gd",
	"res://scripts/TutorialOverlay.gd",
]
const ALL_SCRIPTS_DIR := "res://scripts"

# 영어로 두기로 한 글자. 이유를 함께 적는다 — 목록이 길어질수록 "왜 이것만
# 영어지"를 다시 묻게 되고, 그때 답이 여기 있어야 한다.
const ENGLISH_ON_PURPOSE := {
	"START": "그려진 START 아트와 같은 자리·같은 단어다. 글자만 한글로 바꾸면 아트와 어긋난다",
	"BOOST": "가속 버튼의 이름이고, 한글 튜토리얼 설명도 BOOST 라고 부른다",
	"ENG": "언어 토글 — 어느 언어에서든 두 선택지가 읽혀야 한다",
	"KOR": "언어 토글 — 어느 언어에서든 두 선택지가 읽혀야 한다",
	"BEST": "HUD 와 모드 카드의 BEST 와 같은 단어다. 셋이 같아 보여야 한다",
	"LOCKED": "잠금판 디자인에서 정한 문구",
	"Unlock to play!": "잠금판 디자인에서 정한 문구",
	"LOGIN WITH": "구글 마크에 붙어 있는 글자라 함께 다시 그려야 바뀐다",
	"© 2026 JANIJU STUDIO": "옮길 것이 없다",
}

# 이 상수만은 번역을 거치지 않는다. 값이 우연히 번역 키와 같아졌을 뿐이거나
# (BUS_SFX 의 "SFX" 가 설정 화면의 SFX 와 같다), 같은 단어라도 이 자리에서는
# 영어로 두기로 한 것들이다.
const LEAVE_ALONE := {
	"BUS_SFX": "오디오 버스 이름 — 프로젝트 설정의 버스와 이름이 맞아야 한다",
	"BUS_MUSIC": "오디오 버스 이름",
	"BUTTON_SOUND_BUS": "오디오 버스 이름",
	"SCORE_LABEL_TEXT": "게임 화면 HUD 의 SCORE. 한글화 범위는 메뉴·팝업까지고 HUD 는 빠져 있다 — 옆의 BEST 와도 짝이 맞아야 한다",
}

# 원문 그대로 들고 다녀야 하는 것. 이 프로젝트는 퀴즈 정답 맞추기와 중복
# 방지에 영어 원문을 키로 쓰므로, 상수 자체는 번역하지 않고 그리는 자리에서만
# tr() 을 부른다(CLAUDE.md 의 Language 절). 그래서 "쓰는 줄마다 tr()" 은
# 여기에 걸 수 없고, 대신 "어딘가 한 곳에서는 tr() 을 거치는가"만 본다.
const RAW_FOR_LOGIC := {
	"OCEAN_COLOR_NAMES": "문제 생성·중복 검사·정답 매칭의 키를 겸한다",
	"OCEAN_PROMPT_INK": "같은 이유 — 정답 이름과 비교된다",
}

# 글자가 아니라 자원을 가리키는 상수. 이름으로 거른다.
const NOT_TEXT_SUFFIX := ["_FILE", "_PATH", "_DIR", "_SHEET", "_ICON", "_CHEVRON"]

var _fail := 0
var _csv_keys := {}


# 이름이 통째로 나온 자리인가. 앞뒤가 글자·숫자·밑줄이면 다른 상수의 일부다
# — BEST_TEXT 는 BEST_TEXT_MIN 안에도 들어 있다.
func _mentions(line: String, name: String) -> bool:
	var from := 0
	while true:
		var at: int = line.find(name, from)
		if at < 0:
			return false
		var before: String = line.substr(at - 1, 1) if at > 0 else " "
		var after_at: int = at + name.length()
		var after: String = line.substr(after_at, 1) if after_at < line.length() else " "
		if not _word_char(before) and not _word_char(after):
			return true
		from = at + 1
	return false


func _word_char(ch: String) -> bool:
	return ch != "" and (ch == "_" or ch.to_upper() != ch.to_lower() or ch.is_valid_int())


func _init() -> void:
	_run()


func _fail_msg(msg: String) -> void:
	_fail += 1
	print("  FAIL  %s" % msg)


func _load_csv() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		_fail_msg("%s 를 열 수 없다" % CSV_PATH)
		return
	f.get_csv_line()   # 머리줄
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() < 3 or row[0] == "":
			continue
		if _csv_keys.has(row[0]):
			_fail_msg("ui.csv 에 \"%s\" 가 두 번 있다" % row[0])
		# 한국어 칸이 영어 칸과 같으면 번역을 안 한 것이다 — 줄만 넣고
		# 내용을 안 채우면 tr() 은 통과하고 화면은 영어 그대로다.
		if row[2].strip_edges() == "":
			_fail_msg("ui.csv \"%s\" 의 ko 칸이 비어 있다" % row[0])
		_csv_keys[row[0]] = 0
	f.close()


func _script_lines(path: String) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var text: String = f.get_as_text()
	f.close()
	return text.split("\n")


func _is_resource_name(name: String) -> bool:
	for suffix in NOT_TEXT_SUFFIX:
		if name.ends_with(suffix):
			return true
	return false


# 한 줄짜리 `const NAME := "..."` 과 `const NAME := ["...", ...]` 만 본다.
# 여러 줄에 걸친 배열은 여기서 안 잡히지만, 2번 검사(tr() 을 거치는가)가
# 그 상수의 사용처를 여전히 본다.
#
# 정규식 대신 손으로 훑는다. 따옴표를 다루는 정규식은 이스케이프 범벅이 되고,
# 이 파일은 그 따옴표를 세는 것이 일이라 읽는 사람이 두 번 헷갈린다.
func _quote() -> String:
	return char(34)


func _string_consts(lines: PackedStringArray) -> Dictionary:
	var out := {}
	for line in lines:
		if not line.begins_with("const "):
			continue
		var eq: int = line.find(":=")
		if eq < 0:
			continue
		var name: String = line.substr(6, eq - 6).strip_edges()
		var colon: int = name.find(":")
		if colon >= 0:
			name = name.substr(0, colon).strip_edges()
		if name == "" or name != name.to_upper():
			continue
		if _is_resource_name(name):
			continue
		# 홀수 조각이 따옴표 안, 짝수 조각이 밖이다. 밖에서 # 을 만나면
		# 거기부터는 주석이므로 멈춘다 — 주석 안의 따옴표까지 글자로 세면
		# 있지도 않은 상수 값이 생긴다.
		var parts: PackedStringArray = line.substr(eq + 2).split(_quote())
		var values: Array[String] = []
		for i in range(parts.size()):
			if i % 2 == 0:
				if parts[i].contains("#"):
					break
				continue
			var v: String = parts[i].c_unescape()
			if v != "":
				values.append(v)
		if not values.is_empty():
			out[name] = values
	return out


func _run() -> void:
	_load_csv()
	print("check_translations: ui.csv 에 %d 줄" % _csv_keys.size())

	# ---- 1. UI 스크립트의 글자 상수는 CSV 에 있어야 한다 ----
	for path in UI_SCRIPTS:
		var lines: PackedStringArray = _script_lines(path)
		if lines.is_empty():
			_fail_msg("%s 를 읽을 수 없다" % path)
			continue
		var consts: Dictionary = _string_consts(lines)
		var file: String = path.get_file()
		for name in consts:
			if LEAVE_ALONE.has(name):
				continue
			for value in consts[name]:
				if ENGLISH_ON_PURPOSE.has(value):
					continue
				if not _csv_keys.has(value):
					_fail_msg("%s: %s = \"%s\" 가 ui.csv 에 없다 — 번역하든지, 영어로 둘 이유를 ENGLISH_ON_PURPOSE 에 적을 것" % [
						file, name, value.substr(0, 48)])

	# ---- 2. CSV 에 있는 글자를 쓰는 줄은 tr() 을 거쳐야 한다 ----
	#
	# 상수 이름이 나오는 줄마다 tr(그이름) 이 같은 줄에 있는지 본다. 이
	# 프로젝트는 tr() 을 그리는 자리에서 부르므로(원문이 키라서 그래도 된다)
	# 한 줄 안에 같이 있다.
	var dir := DirAccess.open(ALL_SCRIPTS_DIR)
	var checked := 0
	if dir != null:
		for file_name in dir.get_files():
			if not file_name.ends_with(".gd"):
				continue
			var path: String = ALL_SCRIPTS_DIR + "/" + file_name
			var lines: PackedStringArray = _script_lines(path)
			var consts: Dictionary = _string_consts(lines)
			for name in consts:
				if LEAVE_ALONE.has(name):
					continue
				var translated := false
				for value in consts[name]:
					if _csv_keys.has(value):
						translated = true
						_csv_keys[value] += 1
				if not translated:
					continue
				checked += 1
				if RAW_FOR_LOGIC.has(name):
					# 그리는 자리 한 곳에서만 지나면 된다. 한 곳도 없으면
					# 번역은 아무 데도 안 나온다.
					var seen := false
					for line in lines:
						if line.contains("tr(%s" % name):
							seen = true
							break
					if not seen:
						_fail_msg("%s 의 %s 는 원문 그대로 쓰기로 한 상수인데 tr() 을 거치는 자리가 하나도 없다" % [
							file_name, name])
					continue
				for i in range(lines.size()):
					var line: String = lines[i]
					if not _mentions(line, name):
						continue
					# 돌리기와 개수 세기는 그리는 자리가 아니다. 꺼낸 값을
					# 어떻게 쓰는지는 그 줄에서 따로 걸린다.
					if line.contains("in %s" % name):
						continue
					if line.contains("%s.size()" % name) or line.contains("%s.is_empty()" % name):
						continue
					if line.begins_with("const %s " % name) or line.strip_edges().begins_with("#"):
						continue
					if line.contains("tr(%s" % name):
						continue
					_fail_msg("%s:%d 가 %s 를 tr() 없이 쓴다 — 번역이 파일 안에서 잠잔다\n        %s" % [
						file_name, i + 1, name, line.strip_edges().substr(0, 72)])
	print("  번역을 거쳐야 하는 상수 %d 개의 사용처를 확인" % checked)

	# ---- 3. 아무도 안 쓰는 줄 ----
	#
	# 키가 어긋나면 번역은 조용히 안 나온다. 국가명은 여기 없고(countries.csv)
	# 코드가 아니라 데이터에서 오므로, ui.csv 만 본다.
	var unused: Array[String] = []
	for key in _csv_keys:
		if _csv_keys[key] == 0:
			unused.append(key)
	if not unused.is_empty():
		# 상수가 아니라 그 자리에서 tr("...") 로 부르는 것도 있으므로, 원문이
		# scripts/ 어디에도 안 보일 때만 실패로 친다.
		var all_text := ""
		if dir != null:
			for file_name in dir.get_files():
				if file_name.ends_with(".gd"):
					all_text += FileAccess.get_file_as_string(ALL_SCRIPTS_DIR + "/" + file_name)
		for key in unused:
			# 여러 줄짜리 글자는 소스에 \n 으로 적혀 있다. 원문 그대로도,
			# 이스케이프한 모양으로도 찾아본다.
			if not all_text.contains(key) and not all_text.contains(key.c_escape()):
				_fail_msg("ui.csv \"%s\" 를 쓰는 곳이 없다 — 키가 어긋났거나 남은 줄이다" % key.substr(0, 48))

	if _fail == 0:
		print("check_translations: ok")
		quit(0)
	else:
		print("check_translations: %d failure(s)" % _fail)
		quit(1)
