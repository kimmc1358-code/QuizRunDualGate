class_name PlayGames
extends Node

## Google Play 게임즈 로그인. 플러그인(addons/GodotPlayGameServices)을 감싸는
## 한 겹이고, 게임의 나머지는 이 노드만 안다.
##
## 감싸는 이유는 PC 다. 플러그인의 함수는 안드로이드 싱글턴이 없으면 아무 일도
## 안 하고 조용히 돌아오는데, 결과 신호도 영영 오지 않는다. 그대로 쓰면 에디터와
## 헤드리스 체커에서 로그인을 누른 채로 멈춘다. 그래서 "쓸 수 없음" 을 따로 들고
## 있다가, 누르면 곧바로 실패로 답한다.
##
## 로그아웃은 없다. Play 게임즈 v2 에서 Google 이 없앴고, 플러그인에도 그 아래
## 코틀린 쪽에도 그런 함수가 없다. 로그인은 기기의 Play 게임즈 계정을 따라가며,
## 계정을 끊는 것은 Play 게임즈 앱에서 한다.
##
## 플러그인의 클래스(PlayGamesSignInClient 등)를 이름으로 가리키지 않는다. 그렇게
## 쓰면 애드온 폴더가 없을 때 이 파일부터 열리지 않아 게임 전체가 멈춘다 —
## 스크립트를 경로로 불러오고, 넘어온 객체는 필드만 읽는다.

signal state_changed
signal sign_in_finished(ok: bool)

const PLUGIN_AUTOLOAD := "/root/GodotPlayGameServices"
const SIGN_IN_CLIENT_SCRIPT := "res://addons/GodotPlayGameServices/scripts/sign_in/sign_in_client.gd"
const PLAYERS_CLIENT_SCRIPT := "res://addons/GodotPlayGameServices/scripts/players/players_client.gd"
const LEADERBOARDS_CLIENT_SCRIPT := "res://addons/GodotPlayGameServices/scripts/leaderboards/leaderboards_client.gd"
# 로그인 창을 띄운 뒤 이만큼 답이 없으면 포기한다. 창을 닫았는데 결과 신호가
# 안 오는 경우를 대비한 안전장치다 — 그대로 두면 busy 가 풀리지 않아, 앱을
# 다시 켤 때까지 로그인 버튼이 먹지 않는다.
const SIGN_IN_TIMEOUT := 60.0

var available := false
var signed_in := false
var busy := false
var display_name := ""
var avatar: Texture2D = null

var _sign_in_client: Node = null
var _players_client: Node = null
var _leaderboards_client: Node = null
var _avatar_path := ""
var _attempt := 0
# 순위표 제출이 실패했을 때의 한 번짜리 재시도(_on_score_submitted).
var _last_scores := {}                   # 순위표 ID -> 마지막으로 보낸 점수
var _retried := {}                       # 이미 재시도를 쓴 순위표 ID
var _reconnect_pending: Array[String] = []   # 다시 로그인한 뒤 다시 보낼 순위표 ID


## 부팅 때 한 번. 플러그인을 켜고, 기기에서 이미 Play 게임즈에 들어가 있는지
## 조용히 확인한다 — 들어가 있으면 버튼을 누르지 않아도 로그인된 채로 시작한다.
func start() -> void:
	# 안드로이드가 아니면 부르지도 않는다. 플러그인의 initialize() 는 싱글턴이
	# 없으면 printerr 를 남기는데, 그러면 PC 에서 켤 때마다 오류가 한 줄씩 쌓인다.
	if OS.get_name() != "Android":
		return
	var plugin: Node = get_node_or_null(PLUGIN_AUTOLOAD)
	if plugin == null:
		push_warning("PlayGames: GodotPlayGameServices 가 없다 — 플러그인이 켜져 있는지 볼 것")
		return
	if int(plugin.call("initialize")) != 0:   # PlayGamesPluginError.OK
		return
	_sign_in_client = _make_client(SIGN_IN_CLIENT_SCRIPT)
	_players_client = _make_client(PLAYERS_CLIENT_SCRIPT)
	_leaderboards_client = _make_client(LEADERBOARDS_CLIENT_SCRIPT)
	if _sign_in_client == null or _players_client == null or _leaderboards_client == null:
		return
	available = true
	_sign_in_client.connect("user_authenticated", _on_authenticated)
	_players_client.connect("current_player_loaded", _on_player_loaded)
	_leaderboards_client.connect("score_submitted", _on_score_submitted)
	plugin.connect("image_stored", _on_image_stored)
	_sign_in_client.call("is_authenticated")


## 로그인 버튼. 결과는 sign_in_finished 로 돌아온다 — 쓸 수 없는 곳에서는
## 곧바로 false 로.
func sign_in() -> void:
	if busy:
		return   # 창이 떠 있는 동안의 연타
	if not available or _sign_in_client == null:
		sign_in_finished.emit(false)
		return
	busy = true
	_attempt += 1
	_sign_in_client.call("sign_in")
	get_tree().create_timer(SIGN_IN_TIMEOUT).timeout.connect(_on_sign_in_timeout.bind(_attempt))


## 순위표에 점수를 올린다. 로그인 전이면 아무 일도 안 한다 — 올릴 자리가 없다.
## Play 게임즈는 더 높은 점수만 남기므로 같은 기록을 여러 번 보내도 된다.
func submit_score(leaderboard_id: String, score: int) -> void:
	if not signed_in or _leaderboards_client == null or leaderboard_id == "" or score <= 0:
		return
	# 새로 보내는 점수는 실패했을 때 재시도를 한 번 더 얻는다.
	_retried.erase(leaderboard_id)
	_send(leaderboard_id, score)


func _send(leaderboard_id: String, score: int) -> void:
	_last_scores[leaderboard_id] = score
	_leaderboards_client.call("submit_score", leaderboard_id, score)


## Play 게임즈의 순위표 화면을 띄운다.
func show_leaderboard(leaderboard_id: String) -> void:
	if not signed_in or _leaderboards_client == null or leaderboard_id == "":
		return
	_leaderboards_client.call("show_leaderboard", leaderboard_id)


# 실패하면 한 번만 다시 로그인해 연결을 새로 한 뒤 같은 점수를 다시 보낸다.
#
# 폰에서 디버그 서명 빌드를 쓰다가 Play 가 서명한 빌드로 바뀌었을 때, 로그인과
# 순위표 보기는 되는데 모든 제출이 26502 CLIENT_RECONNECT_REQUIRED 로 실패했다.
# 이름 그대로 연결을 다시 하라는 답이라, 로그인(signIn)을 다시 불러 연결을
# 새로 하고 보낸다. 플러그인은 성공 여부만 bool 로 주므로 실패의 종류는 가리지
# 않는다.
#
# 재시도는 순위표마다 한 번뿐이다. 다시 보낸 것도 실패하면 거기서 멈추고, 다음
# 판이 끝날 때 쌓아 둔 최고 기록을 다시 보낼 때(Main._submit_leaderboard) 새
# 기회를 얻는다 — 끝없이 로그인을 되풀이하지 않는다.
func _on_score_submitted(ok: bool, leaderboard_id: String) -> void:
	if ok:
		_retried.erase(leaderboard_id)
		return
	if _retried.has(leaderboard_id) or not _last_scores.has(leaderboard_id):
		push_warning("PlayGames: %s 순위표에 올리지 못했다 — 다음 판이 끝날 때 다시 보낸다" % leaderboard_id)
		return
	push_warning("PlayGames: %s 순위표에 올리지 못했다 — 다시 로그인해 한 번 더 보낸다" % leaderboard_id)
	_retried[leaderboard_id] = true
	if not _reconnect_pending.has(leaderboard_id):
		_reconnect_pending.append(leaderboard_id)
	# 여러 순위표가 한꺼번에 실패해도 다시 로그인은 한 번.
	if _reconnect_pending.size() == 1:
		_reconnect()


func _reconnect() -> void:
	# 결과를 한 번만 받는다. 로그인이 이미 떠 있으면 sign_in() 은 그냥 돌아오고,
	# 떠 있던 로그인의 결과가 이리로도 온다. 쓸 수 없는 곳이면 그 자리에서 false 가
	# 오므로 연결을 먼저 걸어 둔다.
	if not sign_in_finished.is_connected(_on_reconnected):
		sign_in_finished.connect(_on_reconnected, CONNECT_ONE_SHOT)
	sign_in()


func _on_reconnected(ok: bool) -> void:
	var ids := _reconnect_pending.duplicate()
	_reconnect_pending.clear()
	if not ok or _leaderboards_client == null:
		push_warning("PlayGames: 다시 로그인하지 못해 순위표에 다시 보내지 않았다")
		return
	for id in ids:
		if _last_scores.has(id):
			_send(id, int(_last_scores[id]))


## 에디터에서 로그인한 화면을 보는 길. PC 에서는 진짜 로그인이 안 되므로 이것
## 말고는 볼 방법이 없다. Main 의 debug_fake_sign_in 이 켠다.
func fake_sign_in(player_name: String) -> void:
	_on_authenticated(true)
	_apply_player(player_name, "")


func _on_authenticated(ok: bool) -> void:
	busy = false
	var was := signed_in
	signed_in = ok
	if not ok:
		display_name = ""
		avatar = null
		_avatar_path = ""
	elif not was and _players_client != null:
		_players_client.call("load_current_player", false)
	if was != signed_in:
		state_changed.emit()
	sign_in_finished.emit(ok)


# 오래된 시도의 타이머가 새 시도를 끊지 않도록 몇 번째 시도였는지를 함께 받는다.
func _on_sign_in_timeout(attempt: int) -> void:
	if not busy or attempt != _attempt:
		return
	busy = false
	sign_in_finished.emit(false)


func _on_player_loaded(player: Object) -> void:
	if player == null:
		return   # 불러오기 실패 — 로그인은 된 채로 이름만 비어 있다
	var image := str(player.get("icon_image_uri"))
	# 계정 줄의 동그라미는 폰에서 100px 을 넘으므로, 있으면 큰 사진을 쓴다.
	if player.get("has_hi_res_image") == true:
		image = str(player.get("hi_res_image_uri"))
	_apply_player(str(player.get("display_name")), image)


# 이름과 사진 경로. 사진은 플러그인이 user:// 에 내려받는데 선수 정보보다 늦게
# 도착하기도 한다 — 그때는 비워 두고 image_stored 가 올 때까지 기다린다.
func _apply_player(player_name: String, image_path: String) -> void:
	display_name = player_name
	_avatar_path = image_path
	avatar = _load_avatar(image_path)
	state_changed.emit()


func _on_image_stored(file_path: String) -> void:
	if file_path == "" or file_path != _avatar_path:
		return
	avatar = _load_avatar(file_path)
	if avatar != null:
		state_changed.emit()


func _load_avatar(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _make_client(script_path: String) -> Node:
	if not ResourceLoader.exists(script_path):
		push_warning("PlayGames: %s 가 없다" % script_path)
		return null
	var node: Node = load(script_path).new()
	add_child(node)
	return node
