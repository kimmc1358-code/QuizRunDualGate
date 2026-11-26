class_name SpaceRun
extends Node

## The space game (2.0). A ship seen from behind, steered up/down/left/right by
## dragging anywhere, fires on its own while the run goes round one cycle:
##
##   QUIZ   a wave of planets flies in with one easy question — an arrow, a
##          rock-paper-scissors hand or a sum. Ram the planet that answers it.
##          Right: the planet smashes and a roulette spins. Wrong (or no planet
##          touched): the weapon drops one step. Bullets pass through these
##          planets; only ramming answers.
##   LOOT   right after a right answer: the roulette spins at the top while an
##          asteroid field flies past, so there is something to try the new
##          weapon on. Asteroids can be shot or dodged; hitting one costs a
##          heart. Every roulette result is a gain, only the size differs.
##   BOSS   after QUIZ_PER_CYCLE questions an enemy ship arrives. A strong
##          weapon melts it; a weak one can still win by dodging long enough.
##          Its shots cost a heart.
##   FEVER  the boss down: eight seconds at speed, every planet touched or shot
##          is smashed for points, nothing costs a heart. Then the next cycle.
##
## Main owns the run — score, combo, hearts, the revive offer, popups, the
## question box. This node owns the world and the rules of contact, and
## reports outcomes through Main's `_space_*` handlers.
##
## The world is a plane at z = 0 where the ship flies; everything is judged
## there, at the ship's real 3D position, which is also what the camera shows.
##
## Synty's Sci-Fi Space pack supplies the models. It cannot be committed (see
## tools/build_space_kit.py); without the kit this falls back to plain shapes.

enum Phase { QUIZ, LOOT, BOSS, FEVER }
enum Kind { MATH, ARROW, RPS }
enum Weapon { BLASTER, SPREAD, LASER }

const KIT_PATH := "res://assets/synty_space/space_kit.glb"
const LAND_MASK_PATH := "res://assets/synty_space/land_mask.png"
const CLOUD_MASK_PATH := "res://assets/synty_space/cloud_mask.png"
const SKY_PATH := "res://assets/synty_space/sky.png"
const PLANET_SHADER_PATH := "res://assets/shaders/planet.gdshader"
const SHIP_NODE := "Ship_Fighter_05"
const BOSS_NODE := "Ship_Bomber_04"
const PLANET_NODES := ["Planet_01", "Planet_02", "Planet_05", "Planet_08", "Planet_09", "Planet_10"]
const ROCK_NODES := ["Asteroid_01", "Asteroid_02", "Asteroid_03", "Asteroid_05"]

# ---- the field (world units, on the flight plane) ----
const FIELD_HALF := Vector2(2.3, 3.0)
# left, right, up, down. Far enough apart that no point touches two planets.
const SLOTS := [Vector2(-1.85, 0.0), Vector2(1.85, 0.0), Vector2(0.0, 2.3), Vector2(0.0, -2.3)]
const PLANET_RADIUS := 1.0
const SHIP_HIT_RADIUS := 0.3
const SHIP_WIDTH := 1.7

# ---- speed ----
const SPAWN_Z := -70.0
const BASE_SPEED := 24.0           # 70 / 24 = 2.9 s from a wave appearing to its judgement
const GROW_DISTANCE := 10.0
const REMOVE_Z := 13.0

# ---- the cycle ----
const QUIZ_PER_CYCLE := 10
const QUIZ_RETRIES := 6
# The arrow sometimes comes red, meaning "the other way". Not in the first
# cycle, so the plain rule is learned before it is bent.
const ARROW_REVERSE_CHANCE := 0.3

# ---- loot: roulette + asteroids ----
const LOOT_DURATION := 3.8
const ROULETTE_SPIN := 1.3
const ASTEROID_INTERVAL := 0.42
const ASTEROID_RADIUS := Vector2(0.45, 0.8)
const ASTEROID_HP := 3.0
const ASTEROID_POINTS := 5
## [id, label, weight]. Every entry is a gain; the weights are the luck.
const ROULETTE := [
	["power1", "POWER +1", 52],
	["power2", "POWER +2", 20],
	["spread", "SPREAD!", 10],
	["laser", "LASER!", 10],
	["drone", "DRONE!", 8],
]
const MAX_LEVEL := 10
const MAX_DRONES := 2

# ---- weapons ----
const BULLET_SPEED := 70.0
const BULLET_RANGE := -90.0
const BULLET_RADIUS := 0.14

# ---- boss ----
const BOSS_Z := -15.0
const BOSS_RADIUS := 2.2
const BOSS_WIDTH := 5.0
const BOSS_HP := 60.0
const BOSS_HP_PER_CYCLE := 0.7     # +70% a cycle
const BOSS_ENTER_TIME := 1.6
const BOSS_FIRE_INTERVAL := 1.15
const ORB_SPEED := 16.0
const ORB_RADIUS := 0.32
const BOSS_POINTS := 300

# ---- fever ----
const FEVER_DURATION := 8.0
const FEVER_SPEED := 2.2
const FEVER_SPAWN_INTERVAL := 0.28
const FEVER_FOV_BOOST := 7.0

# ---- control ----
const DRAG_GAIN := 1.35
const SHIP_FOLLOW_SHARPNESS := 16.0
const SHIP_BANK_PER_SPEED := 0.10
const SHIP_BANK_MAX := 0.7
const SHIP_PITCH_PER_SPEED := 0.06
const SHIP_PITCH_MAX := 0.35

# ---- camera ----
# Horizontal field of view: the game is 480 wide on every phone, so a taller
# phone sees more above and below rather than losing the side planets.
# Raised well above the plane: from nearly level, a flat fighter is a thin
# line; from ~15 degrees its back shows.
const CAMERA_POS := Vector3(0.0, 3.0, 10.0)
const CAMERA_LOOK := Vector3(0.0, -1.1, -6.0)
const CAMERA_FOV := 40.0
const MAX_RENDER_SCALE := 2.0
const BG_COLOR := Color(0.03, 0.02, 0.07)

# ---- smash ----
const DEBRIS_COUNT := 12
const DEBRIS_LIFE := 0.9
const DEBRIS_SPEED := 7.0
const FLASH_LIFE := 0.45
const RING_LIFE := 0.55

const PALETTES := [
	[Color(0.10, 0.35, 0.85), Color(0.25, 0.70, 0.30)],
	[Color(0.80, 0.30, 0.10), Color(0.95, 0.65, 0.30)],
	[Color(0.45, 0.20, 0.80), Color(0.85, 0.55, 0.95)],
	[Color(0.15, 0.65, 0.70), Color(0.85, 0.95, 0.95)],
	[Color(0.70, 0.15, 0.20), Color(1.00, 0.60, 0.50)],
	[Color(0.10, 0.50, 0.40), Color(0.60, 0.90, 0.40)],
	[Color(0.80, 0.60, 0.10), Color(1.00, 0.90, 0.50)],
	[Color(0.20, 0.20, 0.60), Color(0.60, 0.70, 1.00)],
]
const ROCK_PALETTE := [Color(0.32, 0.29, 0.30), Color(0.55, 0.50, 0.46)]

const PLATE_FILL := Color(0.97, 0.93, 0.84)
const PLATE_EDGE := Color(0.22, 0.14, 0.10)
const PLATE_TEXT := Color(0.18, 0.11, 0.08)
# Rock, scissors, paper. Drawn with the system's colour emoji font.
const HANDS := ["✊", "✌", "✋"]
const EMOJI_FONTS := ["Noto Color Emoji", "Segoe UI Emoji", "Apple Color Emoji"]
const ARROW_NORMAL := Color(0.18, 0.55, 1.0)
const ARROW_REVERSE := Color(0.95, 0.2, 0.2)

var main: Node
var viewport: SubViewport
var camera: Camera3D
var root3d: Node3D
var ship_pivot: Node3D
var ship_model: Node3D
var view_size := Vector2(480, 854)
var emoji_font: Font

var ship_pos := Vector2.ZERO
var ship_target := Vector2.ZERO
var ship_vel := Vector2.ZERO

var phase: int = Phase.QUIZ
var phase_time := 0.0
var cycle := 0                   # bosses beaten this run
var quiz_index := 0              # questions asked this cycle

## Quiz waves: {"planets", "z", "resolved", "kind", "question", "answer", "reverse", "hand", "dir"}
var waves: Array = []
## Free-flying things: fever planets (loose) and asteroids (rocks).
var loose: Array = []
var rocks: Array = []
var asteroid_timer := 0.0
var fever_spawn_timer := 0.0
var palette_cursor := 0

# weapon
var weapon: int = Weapon.BLASTER
var level := 1
var drones := 0
var fire_timer := 0.0
var bullets: Array = []
var drone_nodes: Array = []

# roulette
var roulette_result: Array = []  # the ROULETTE entry it lands on
var roulette_applied := false

# boss
var boss: Node3D
var boss_hp := 0.0
var boss_max_hp := 1.0
var boss_fire_timer := 0.0
var orbs: Array = []

var debris: Array = []
var flashes: Array = []

var planet_meshes: Array = []
var rock_meshes: Array = []
var boss_mesh: Mesh
var planet_shader: Shader
var land_tex: Texture2D
var cloud_tex: Texture2D
var flash_material: StandardMaterial3D
var ring_material: StandardMaterial3D
var bullet_mesh: Mesh
var bullet_material: StandardMaterial3D
var laser_material: StandardMaterial3D
var orb_mesh: Mesh
var orb_material: StandardMaterial3D
var streaks: MultiMeshInstance3D
var streak_pos: PackedVector3Array = PackedVector3Array()
var sky_material: StandardMaterial3D
var kit_loaded := false


# ================================================================ setup

func setup(main_node: Node, size: Vector2) -> void:
	main = main_node
	view_size = size
	viewport = SubViewport.new()
	viewport.name = "SpaceWorld"
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	root3d = Node3D.new()
	viewport.add_child(root3d)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAMERA_FOV
	camera.near = 0.1
	camera.far = 600.0
	root3d.add_child(camera)
	camera.position = CAMERA_POS
	camera.look_at(CAMERA_LOOK, Vector3.UP)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.75)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	camera.environment = env

	_add_sun(Vector3(0.6, 0.8, 0.5), 1.6, Color(1.0, 0.95, 0.88))
	_add_sun(Vector3(-0.7, -0.2, -0.6), 0.6, Color(0.55, 0.45, 1.0))
	_add_sun(Vector3(0.0, 0.6, 1.0), 0.9, Color(0.9, 0.95, 1.0))

	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(EMOJI_FONTS)
	emoji_font = sf

	planet_shader = load(PLANET_SHADER_PATH)
	if ResourceLoader.exists(LAND_MASK_PATH):
		land_tex = load(LAND_MASK_PATH)
	if ResourceLoader.exists(CLOUD_MASK_PATH):
		cloud_tex = load(CLOUD_MASK_PATH)
	_load_kit()
	_build_ship()
	_build_fx_materials()
	_build_sky()
	_build_streaks()
	fit(size)
	reset_run()


func _add_sun(from: Vector3, energy: float, color: Color) -> void:
	var sun := DirectionalLight3D.new()
	sun.light_energy = energy
	sun.light_color = color
	root3d.add_child(sun)
	var d := from.normalized()
	sun.look_at_from_position(d, Vector3.ZERO, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)


func _load_kit() -> void:
	planet_meshes.clear()
	rock_meshes.clear()
	var kit: Node = null
	if ResourceLoader.exists(KIT_PATH):
		var scene: PackedScene = load(KIT_PATH)
		if scene != null:
			kit = scene.instantiate()
	if kit != null:
		for n in PLANET_NODES:
			var mi := kit.find_child(n, true, false) as MeshInstance3D
			if mi != null and mi.mesh != null:
				planet_meshes.append({"mesh": mi.mesh, "scale": 2.0 / maxf(mi.mesh.get_aabb().size.x, 0.001)})
		for n in ROCK_NODES:
			var mi := kit.find_child(n, true, false) as MeshInstance3D
			if mi != null and mi.mesh != null:
				rock_meshes.append({"mesh": mi.mesh, "scale": 2.0 / maxf(mi.mesh.get_aabb().size.x, 0.001)})
		var ship_mi := kit.find_child(SHIP_NODE, true, false) as MeshInstance3D
		if ship_mi != null:
			ship_model = _centred_model(ship_mi.mesh, SHIP_WIDTH, true)
		var boss_mi := kit.find_child(BOSS_NODE, true, false) as MeshInstance3D
		if boss_mi != null:
			boss_mesh = boss_mi.mesh
		kit.free()
		kit_loaded = not planet_meshes.is_empty()
	if planet_meshes.is_empty():
		planet_meshes.append({"mesh": SphereMesh.new(), "scale": 1.0})
	if rock_meshes.is_empty():
		var rock := SphereMesh.new()
		rock.radial_segments = 6
		rock.rings = 3
		rock_meshes.append({"mesh": rock, "scale": 1.0})


## A mesh scaled to `width` and centred on its own bounds, so the node's origin
## is the hit centre. `turn` faces it down -Z (the models' noses point +Z).
func _centred_model(mesh: Mesh, width: float, turn: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var aabb := mesh.get_aabb()
	var s: float = width / maxf(aabb.size.x, 0.001)
	mi.scale = Vector3.ONE * s
	var c: Vector3 = aabb.get_center() * s
	if turn:
		mi.rotation.y = PI
		mi.position = Vector3(c.x, -c.y, c.z)
	else:
		mi.position = -c
	return mi


func _build_ship() -> void:
	ship_pivot = Node3D.new()
	root3d.add_child(ship_pivot)
	if ship_model == null:
		var wedge := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(SHIP_WIDTH, 1.2, 0.35)
		wedge.mesh = prism
		wedge.rotation.x = -PI * 0.5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.6, 0.85)
		wedge.material_override = m
		ship_model = wedge
	ship_pivot.add_child(ship_model)
	for dx in [-0.25, 0.0, 0.25]:
		var glow := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.28, 0.28)
		glow.mesh = q
		glow.material_override = _glow_material(Color(0.35, 0.85, 1.0), 2.0)
		glow.position = Vector3(dx, 0.0, 0.62)
		ship_pivot.add_child(glow)


func _radial_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _radial_texture()
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _add_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	return m


func _build_fx_materials() -> void:
	flash_material = _glow_material(Color(1.0, 0.75, 0.4), 2.5)
	ring_material = _add_material(Color(1.0, 0.88, 0.65, 1.0))
	var cap := CapsuleMesh.new()
	cap.radius = 0.11
	cap.height = 1.3
	bullet_mesh = cap
	bullet_material = _add_material(Color(0.5, 1.6, 2.0, 1.0))
	laser_material = _add_material(Color(2.0, 0.6, 1.8, 1.0))
	var orb := SphereMesh.new()
	orb.radius = ORB_RADIUS
	orb.height = ORB_RADIUS * 2.0
	orb.radial_segments = 12
	orb.rings = 6
	orb_mesh = orb
	orb_material = _add_material(Color(2.2, 0.35, 0.5, 1.0))


func _build_sky() -> void:
	if not ResourceLoader.exists(SKY_PATH):
		return
	var sky := MeshInstance3D.new()
	var q := QuadMesh.new()
	var dist := 420.0
	var h: float = 2.0 * (dist + CAMERA_POS.z) * 1.4
	q.size = Vector2(h, h)
	sky.mesh = q
	sky_material = StandardMaterial3D.new()
	sky_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_material.albedo_texture = load(SKY_PATH)
	sky_material.albedo_color = Color(1.25, 1.25, 1.25)
	sky_material.texture_repeat = true
	sky_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	sky.material_override = sky_material
	root3d.add_child(sky)
	# Square to the camera's line of sight, so it fills the view however the
	# camera is tilted.
	var fwd: Vector3 = (CAMERA_LOOK - CAMERA_POS).normalized()
	sky.position = CAMERA_POS + fwd * dist
	sky.look_at(CAMERA_POS, Vector3.UP)


func _build_streaks() -> void:
	var count := 90
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 0.035, 1.0)
	mm.mesh = box
	mm.instance_count = count
	streaks = MultiMeshInstance3D.new()
	streaks.multimesh = mm
	streaks.material_override = _add_material(Color(0.55, 0.75, 1.0, 0.7))
	root3d.add_child(streaks)
	streak_pos.resize(count)
	for i in count:
		var a := randf() * TAU
		var r := randf_range(5.5, 22.0)
		streak_pos[i] = Vector3(cos(a) * r * 0.75, sin(a) * r, randf_range(-160.0, REMOVE_Z))


func fit(size: Vector2) -> void:
	view_size = size
	var scale := 1.0
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	if win.y > 0.0 and size.y > 0.0:
		scale = clampf(minf(win.x / size.x, win.y / size.y), 1.0, MAX_RENDER_SCALE)
	viewport.size = Vector2i(maxi(1, int(size.x * scale)), maxi(1, int(size.y * scale)))


func texture() -> Texture2D:
	return viewport.get_texture() if viewport != null else null


func fever_active() -> bool:
	return phase == Phase.FEVER


func speed() -> float:
	return BASE_SPEED * (1.0 + 0.08 * cycle) * (FEVER_SPEED if phase == Phase.FEVER else 1.0)


## Two planets a wave in the first cycle, three in the second, then four.
func planets_for_cycle(c: int) -> int:
	return clampi(2 + c, 2, 4)


# ================================================================ run state

func reset_run() -> void:
	_clear_world()
	_remove_boss()
	fire_timer = 0.0
	cycle = 0
	quiz_index = 0
	weapon = Weapon.BLASTER
	level = 1
	drones = 0
	_sync_drones()
	ship_pos = Vector2.ZERO
	ship_target = Vector2.ZERO
	ship_vel = Vector2.ZERO
	if camera != null:
		camera.fov = CAMERA_FOV
	_enter(Phase.QUIZ)


## After a revive: what was in flight is gone; a boss fight goes on with the
## boss's health as it was, anything else restarts on a fresh question.
func revive() -> void:
	_clear_world()
	ship_target = Vector2.ZERO
	if phase == Phase.BOSS:
		phase_time = BOSS_ENTER_TIME
		boss_fire_timer = BOSS_FIRE_INTERVAL * 1.5
	else:
		_enter(Phase.QUIZ)


func _clear_world() -> void:
	for w in waves:
		for p in w.planets:
			_free(p.node)
	for list in [loose, rocks, bullets, orbs, debris, flashes]:
		for e in list:
			_free(e.node)
	waves.clear()
	loose.clear()
	rocks.clear()
	bullets.clear()
	orbs.clear()
	debris.clear()
	flashes.clear()


func _free(node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


func _enter(p: int) -> void:
	phase = p
	phase_time = 0.0
	match p:
		Phase.QUIZ:
			if main != null:
				spawn_wave()
		Phase.LOOT:
			asteroid_timer = 0.5
			_spin_roulette()
		Phase.BOSS:
			_spawn_boss()
		Phase.FEVER:
			fever_spawn_timer = 0.4
			if main != null:
				main._space_fever_started()


## What the question box shows.
func question() -> String:
	match phase:
		Phase.FEVER:
			return "FEVER!"
		Phase.BOSS:
			return "BOSS!"
		Phase.LOOT:
			return roulette_text()
	var w := upcoming_wave()
	if w.is_empty():
		return ""
	return str(w.question) if w.kind == Kind.MATH else " "


func upcoming_wave() -> Dictionary:
	for w in waves:
		if not w.resolved:
			return w
	return {}


# ================================================================ quiz

func _next_kind() -> int:
	return [Kind.MATH, Kind.ARROW, Kind.RPS][randi() % 3]


## A wave of planets_for_cycle planets with one question of `kind` (random if
## -1). Planet i sits in slot slots[i]; exactly one is marked correct.
func spawn_wave(kind: int = -1) -> void:
	if kind < 0:
		kind = _next_kind()
	var n: int = planets_for_cycle(cycle)
	var w := {"planets": [], "z": SPAWN_Z, "resolved": false, "kind": kind,
		"question": "", "answer": "", "reverse": false, "hand": -1, "dir": -1}
	var slots: Array = [0, 1, 2, 3]
	slots.shuffle()
	slots = slots.slice(0, n)
	var correct_slot: int = slots[0]
	var wrong_labels: Array = []
	match kind:
		Kind.MATH:
			var pr := _easy_problem()
			w.question = pr.text
			w.answer = str(pr.answer)
			for v in _decoys(int(pr.answer), n - 1):
				wrong_labels.append(str(v))
		Kind.ARROW:
			# The arrow points at a slot; red means the slot opposite it, so
			# that one has to be in the wave as well.
			var reverse: bool = cycle > 0 and randf() < ARROW_REVERSE_CHANCE
			var shown: int = _opposite(correct_slot) if reverse else correct_slot
			if reverse and not slots.has(shown):
				slots[slots.size() - 1] = shown
			w.reverse = reverse
			w.dir = shown
			w.answer = str(correct_slot)
		Kind.RPS:
			var hand: int = randi() % 3
			var win: int = (hand + 2) % 3     # paper beats rock, rock beats scissors, scissors beat paper
			w.hand = hand
			w.answer = HANDS[win]
			for h in [hand, (hand + 1) % 3]:
				wrong_labels.append(HANDS[h])
			wrong_labels.shuffle()
	var k := 0
	for s in slots:
		var correct: bool = s == correct_slot
		var label := ""
		if kind != Kind.ARROW:
			if correct:
				label = str(w.answer)
			else:
				label = str(wrong_labels[k % wrong_labels.size()])
				k += 1
		var p := _make_planet(SLOTS[s], SPAWN_Z, label, correct)
		p["slot"] = s
		p["emoji"] = kind == Kind.RPS
		w.planets.append(p)
	waves.append(w)


static func _opposite(slot: int) -> int:
	return [1, 0, 3, 2][slot]


## Single-digit sums and differences: the quiz is a gate, not a test.
func _easy_problem() -> Dictionary:
	var pr: Dictionary = {}
	for attempt in QUIZ_RETRIES:
		if randi() % 2 == 0:
			var a := randi_range(1, 9)
			var b := randi_range(1, 9)
			pr = {"text": "%d + %d = ?" % [a, b], "answer": a + b}
		else:
			var x := randi_range(2, 9 + mini(cycle, 3) * 3)
			var y := randi_range(1, mini(9, x - 1))
			pr = {"text": "%d - %d = ?" % [x, y], "answer": x - y}
		if main == null or pr.text != main.last_quiz_key:
			break
	if main != null:
		main.last_quiz_key = pr.text
	return pr


func _decoys(answer: int, count: int) -> Array:
	var out: Array = []
	for c in [answer + 1, answer - 1, answer + 2, answer - 2, answer + 10, answer + 3, answer - 3]:
		if out.size() >= count:
			break
		if c != answer and c >= 0 and not out.has(c):
			out.append(c)
	var k := 4
	while out.size() < count:
		if not out.has(answer + k):
			out.append(answer + k)
		k += 1
	return out


func _make_planet(pos: Vector2, z: float, label: String, correct: bool) -> Dictionary:
	var pal: Array = PALETTES[palette_cursor % PALETTES.size()]
	palette_cursor += 1
	var entry: Dictionary = planet_meshes[randi() % planet_meshes.size()]
	var node := MeshInstance3D.new()
	node.mesh = entry.mesh
	var mat := _planet_material(pal[0], pal[1])
	node.material_override = mat
	node.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	root3d.add_child(node)
	var p := {
		"node": node, "mat": mat, "pos": pos, "z": z, "label": label,
		"correct": correct, "alive": true, "judged": false, "palette": pal,
		"base_scale": float(entry.scale) * PLANET_RADIUS, "radius": PLANET_RADIUS,
		"spin": Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.6), 0.0),
		"flash": 0.0,
	}
	_place(p)
	return p


func _planet_material(sea: Color, ground: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = planet_shader
	m.set_shader_parameter("sea", sea)
	m.set_shader_parameter("ground", ground)
	m.set_shader_parameter("rim_color", sea.lightened(0.4))
	if land_tex != null:
		m.set_shader_parameter("land_mask", land_tex)
	if cloud_tex != null:
		m.set_shader_parameter("cloud_mask", cloud_tex)
	return m


func _place(p: Dictionary) -> void:
	var grow: float = clampf((p.z - SPAWN_Z) / GROW_DISTANCE, 0.0, 1.0)
	grow = grow * grow * (3.0 - 2.0 * grow)
	var node: MeshInstance3D = p.node
	node.position = Vector3(p.pos.x, p.pos.y, p.z)
	node.scale = Vector3.ONE * maxf(p.base_scale * grow, 0.0001)


func _touching(p: Dictionary) -> bool:
	return ship_pos.distance_to(p.pos) <= p.radius + SHIP_HIT_RADIUS


func _resolve_wave(w: Dictionary) -> void:
	w.resolved = true
	quiz_index += 1
	var hit: Dictionary = {}
	for p in w.planets:
		if _touching(p):
			hit = p
			break
	if not hit.is_empty() and hit.correct:
		_smash(hit, false)
		main._space_correct()
		if main.space_run_live():
			_enter(Phase.LOOT)
		return
	if not hit.is_empty():
		hit.flash = 1.0
		_smash(hit, true)
	_weapon_down()
	main._space_wrong()
	if main.space_run_live():
		_after_question()


## After a question: the boss once the cycle's questions are done, otherwise
## the next question.
func _after_question() -> void:
	if quiz_index >= QUIZ_PER_CYCLE:
		_enter(Phase.BOSS)
	else:
		_enter(Phase.QUIZ)


# ================================================================ loot

func _spin_roulette() -> void:
	var total := 0
	for e in ROULETTE:
		total += int(e[2])
	var r := randi() % total
	roulette_result = ROULETTE[0]
	for e in ROULETTE:
		r -= int(e[2])
		if r < 0:
			roulette_result = e
			break
	roulette_applied = false


## The box spins through the labels, slowing down, then lands.
func roulette_text() -> String:
	if phase_time >= ROULETTE_SPIN:
		return str(roulette_result[1])
	var t: float = phase_time / ROULETTE_SPIN
	var step := int(pow(t, 0.55) * 18.0)
	return str(ROULETTE[step % ROULETTE.size()][1])


func _apply_roulette() -> void:
	roulette_applied = true
	match str(roulette_result[0]):
		"power1":
			level = mini(MAX_LEVEL, level + 1)
		"power2":
			level = mini(MAX_LEVEL, level + 2)
		"spread", "laser":
			var to: int = Weapon.SPREAD if str(roulette_result[0]) == "spread" else Weapon.LASER
			# The same weapon again is still a gain: two levels instead.
			level = mini(MAX_LEVEL, level + (2 if weapon == to else 1))
			weapon = to
		"drone":
			if drones >= MAX_DRONES:
				level = mini(MAX_LEVEL, level + 2)
			drones = mini(MAX_DRONES, drones + 1)
			_sync_drones()
	main._space_powered_up(str(roulette_result[1]))


## A wrong answer knocks the weapon down one step: a drone goes first, then a
## level, and at level 1 back to the blaster.
func _weapon_down() -> void:
	if drones > 0:
		drones -= 1
		_sync_drones()
	elif level > 1:
		level -= 1
	elif weapon != Weapon.BLASTER:
		weapon = Weapon.BLASTER


func _sync_drones() -> void:
	while drone_nodes.size() > drones:
		_free(drone_nodes.pop_back())
	while drone_nodes.size() < drones and root3d != null:
		var d := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.11
		s.height = 0.22
		d.mesh = s
		d.material_override = _add_material(Color(0.6, 1.4, 2.0, 1.0))
		d.position = Vector3(ship_pos.x, ship_pos.y, 0.3)
		root3d.add_child(d)
		drone_nodes.append(d)


func _spawn_asteroid() -> void:
	var entry: Dictionary = rock_meshes[randi() % rock_meshes.size()]
	var node := MeshInstance3D.new()
	node.mesh = entry.mesh
	node.material_override = _planet_material(ROCK_PALETTE[0], ROCK_PALETTE[1])
	root3d.add_child(node)
	var radius: float = randf_range(ASTEROID_RADIUS.x, ASTEROID_RADIUS.y)
	# Half aimed near the ship, so there is always something to shoot or dodge.
	var pos: Vector2
	if randf() < 0.5:
		pos = (ship_pos + Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))).clamp(-FIELD_HALF, FIELD_HALF)
	else:
		pos = Vector2(randf_range(-FIELD_HALF.x, FIELD_HALF.x), randf_range(-FIELD_HALF.y, FIELD_HALF.y))
	var r := {"node": node, "pos": pos, "z": SPAWN_Z * 0.8, "radius": radius,
		"base_scale": float(entry.scale) * radius, "hp": ASTEROID_HP * (1.0 + 0.3 * cycle),
		"spin": Vector3(randf(), randf(), randf()) * 2.0, "judged": false, "alive": true,
		"palette": ROCK_PALETTE, "flash": 0.0}
	node.position = Vector3(pos.x, pos.y, r.z)
	node.scale = Vector3.ONE * r.base_scale
	rocks.append(r)


# ================================================================ boss

func _spawn_boss() -> void:
	_remove_boss()
	boss_max_hp = BOSS_HP * (1.0 + BOSS_HP_PER_CYCLE * cycle)
	boss_hp = boss_max_hp
	boss_fire_timer = BOSS_FIRE_INTERVAL * 1.5
	boss = Node3D.new()
	root3d.add_child(boss)
	var model: MeshInstance3D
	if boss_mesh != null:
		model = _centred_model(boss_mesh, BOSS_WIDTH, false)
	else:
		model = MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(BOSS_WIDTH, 0.8, 2.5)
		model.mesh = b
	boss.add_child(model)
	boss.position = Vector3(0.0, 1.0, SPAWN_Z)


func _remove_boss() -> void:
	_free(boss)
	boss = null


func _update_boss(delta: float) -> void:
	if boss == null:
		return
	var enter: float = clampf(phase_time / BOSS_ENTER_TIME, 0.0, 1.0)
	enter = 1.0 - pow(1.0 - enter, 3.0)
	var x: float = sin(phase_time * 0.9) * 1.8
	var y: float = 1.0 + sin(phase_time * 1.7) * 0.6
	boss.position = Vector3(x, y, lerpf(SPAWN_Z, BOSS_Z, enter))
	boss.rotation = Vector3(0.0, 0.0, -cos(phase_time * 0.9) * 0.25)
	if phase_time < BOSS_ENTER_TIME:
		return
	boss_fire_timer -= delta
	if boss_fire_timer <= 0.0:
		boss_fire_timer = BOSS_FIRE_INTERVAL / (1.0 + 0.2 * cycle)
		var shots: int = 1 + mini(cycle, 2)
		for i in shots:
			_fire_orb(ship_pos + Vector2((i - (shots - 1) * 0.5) * 1.1, 0.0))


func _fire_orb(aim: Vector2) -> void:
	var from: Vector3 = boss.position + Vector3(0, -0.3, 1.0)
	var to := Vector3(aim.x, aim.y, 0.0)
	var node := MeshInstance3D.new()
	node.mesh = orb_mesh
	node.material_override = orb_material
	node.position = from
	root3d.add_child(node)
	orbs.append({"node": node, "vel": (to - from).normalized() * ORB_SPEED, "judged": false})


func _boss_hit(dmg: float) -> void:
	boss_hp -= dmg
	if boss_hp > 0.0 or phase != Phase.BOSS:
		return
	var center: Vector3 = boss.position
	for i in 3:
		_burst(center + Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 0.6), 0.0), PALETTES[4], false, 2.0)
	_remove_boss()
	for o in orbs:
		_free(o.node)
	orbs.clear()
	cycle += 1
	quiz_index = 0
	main._space_boss_down(BOSS_POINTS * cycle)
	_enter(Phase.FEVER)


# ================================================================ weapons

func _fire(delta: float) -> void:
	fire_timer -= delta
	if fire_timer > 0.0:
		return
	var origin := Vector3(ship_pos.x, ship_pos.y, -0.8)
	match weapon:
		Weapon.BLASTER:
			fire_timer = maxf(0.11, 0.30 - 0.018 * level)
			var n: int = 1 + int((level - 1) / 3)
			for i in n:
				var off: float = (i - (n - 1) * 0.5) * 0.28
				_bullet(origin + Vector3(off, 0, 0), Vector3(0, 0, -1), 1.0 + 0.15 * level, false)
		Weapon.SPREAD:
			fire_timer = maxf(0.16, 0.36 - 0.016 * level)
			var n: int = 3 + int((level - 1) / 3) * 2
			for i in n:
				var a: float = (i - (n - 1) * 0.5) * 0.07
				_bullet(origin, Vector3(sin(a), 0, -cos(a)), 0.8 + 0.12 * level, false)
		Weapon.LASER:
			fire_timer = maxf(0.18, 0.42 - 0.02 * level)
			_bullet(origin, Vector3(0, 0, -1), 3.0 + 0.5 * level, true)
	for d in drone_nodes:
		var dp: Vector3 = (d as Node3D).position
		_bullet(Vector3(dp.x, dp.y, -0.6), Vector3(0, 0, -1), 0.8 + 0.1 * level, false)


func _bullet(from: Vector3, dir: Vector3, dmg: float, laser: bool) -> void:
	var node := MeshInstance3D.new()
	node.mesh = bullet_mesh
	node.material_override = laser_material if laser else bullet_material
	node.position = from
	node.rotation.x = -PI * 0.5
	if laser:
		node.scale = Vector3(1.8, 2.2, 1.8)
	root3d.add_child(node)
	bullets.append({"node": node, "vel": dir * BULLET_SPEED, "dmg": dmg, "pierce": laser, "dead": false})


## Bullets are swept from last frame's position to this one's, so a fast
## bullet cannot step over a thin target.
func _update_bullets(delta: float) -> void:
	for b in bullets:
		var node: MeshInstance3D = b.node
		var p0: Vector3 = node.position
		var p1: Vector3 = p0 + b.vel * delta
		node.position = p1
		var at := Vector2(p1.x, p1.y)
		for r in rocks:
			if b.dead:
				break
			if r.alive and r.z <= p0.z + r.radius and r.z >= p1.z - r.radius \
					and at.distance_to(r.pos) <= r.radius + BULLET_RADIUS:
				r.hp -= b.dmg
				r.flash = 1.0
				if r.hp <= 0.0:
					r.judged = true
					_smash(r, false, 0.6)
					main._space_points(ASTEROID_POINTS)
				if not b.pierce:
					b.dead = true
		for p in loose:
			if b.dead:
				break
			if p.alive and p.z <= p0.z + p.radius and p.z >= p1.z - p.radius \
					and at.distance_to(p.pos) <= p.radius + BULLET_RADIUS:
				p.judged = true
				_smash(p, false)
				main._space_fever_smash()
				if not b.pierce:
					b.dead = true
		if not b.dead and boss != null and phase == Phase.BOSS and phase_time >= BOSS_ENTER_TIME * 0.6:
			var bp: Vector3 = boss.position
			if bp.z <= p0.z + 1.0 and bp.z >= p1.z - 1.0 and at.distance_to(Vector2(bp.x, bp.y)) <= BOSS_RADIUS:
				_spark(Vector3(p1.x, p1.y, bp.z + 1.0))
				b.dead = true
				_boss_hit(b.dmg)
		if p1.z < BULLET_RANGE:
			b.dead = true
	for b in bullets:
		if b.dead:
			_free(b.node)
	bullets = bullets.filter(func(b): return not b.dead)


# ================================================================ per frame

## Called every frame by Main. `running`: the run is live (PLAYING, not
## paused). `steerable`: the ship answers the finger (also in the countdown).
func tick(delta: float, running: bool, steerable: bool) -> void:
	if steerable or running:
		_update_ship(delta)
	if running:
		_update_run(delta)
	_update_fx(delta, running)


func _update_ship(delta: float) -> void:
	var prev := ship_pos
	ship_pos = ship_pos.lerp(ship_target, 1.0 - exp(-SHIP_FOLLOW_SHARPNESS * delta))
	ship_vel = (ship_pos - prev) / maxf(delta, 0.0001)


func _update_run(delta: float) -> void:
	phase_time += delta
	var v := speed() * delta
	_fire(delta)
	_update_bullets(delta)
	if not main.space_run_live():
		return
	# Quiz waves.
	for w in waves:
		w.z += v
		for p in w.planets:
			p.z = w.z
		if not w.resolved and w.z >= 0.0:
			_resolve_wave(w)
			if not main.space_run_live():
				return
	# Fever planets: each judged on its own.
	for p in loose:
		p.z += v
		if not p.judged and p.z >= 0.0:
			p.judged = true
			if p.alive and _touching(p):
				_smash(p, false)
				main._space_fever_smash()
	# Asteroids: a hit costs a heart.
	for r in rocks:
		r.z += v * 1.1
		if not r.judged and r.z >= 0.0:
			r.judged = true
			if r.alive and _touching(r) and not main._space_invulnerable():
				_smash(r, true, 0.6)
				main._space_hurt()
				if not main.space_run_live():
					return
	# Boss shots.
	for o in orbs:
		var node: MeshInstance3D = o.node
		node.position += o.vel * delta
		if not o.judged and node.position.z >= 0.0:
			o.judged = true
			var at := Vector2(node.position.x, node.position.y)
			if at.distance_to(ship_pos) <= ORB_RADIUS + SHIP_HIT_RADIUS and not main._space_invulnerable():
				o["dead"] = true
				_spark(node.position)
				main._space_hurt()
				if not main.space_run_live():
					return
		if node.position.z > REMOVE_Z:
			o["dead"] = true
	for o in orbs:
		if o.get("dead", false):
			_free(o.node)
	orbs = orbs.filter(func(o): return not o.get("dead", false))
	_drop_passed()

	match phase:
		Phase.LOOT:
			if phase_time >= ROULETTE_SPIN and not roulette_applied:
				_apply_roulette()
			asteroid_timer -= delta
			if asteroid_timer <= 0.0 and phase_time < LOOT_DURATION - 1.2:
				asteroid_timer = ASTEROID_INTERVAL
				_spawn_asteroid()
			if phase_time >= LOOT_DURATION:
				_after_question()
		Phase.BOSS:
			_update_boss(delta)
		Phase.FEVER:
			fever_spawn_timer -= delta
			if fever_spawn_timer <= 0.0 and phase_time < FEVER_DURATION - 1.0:
				fever_spawn_timer = FEVER_SPAWN_INTERVAL
				_spawn_fever_planets()
			if phase_time >= FEVER_DURATION:
				main._space_fever_ended()
				_enter(Phase.QUIZ)
		Phase.QUIZ:
			if upcoming_wave().is_empty():
				spawn_wave()


func _drop_passed() -> void:
	for w in waves:
		if w.resolved and w.z > REMOVE_Z:
			for p in w.planets:
				_free(p.node)
	waves = waves.filter(func(w): return w.z <= REMOVE_Z or not w.resolved)
	var gone := func(e): return e.z > REMOVE_Z or (not e.alive and e.judged)
	for e in loose:
		if gone.call(e):
			_free(e.node)
	loose = loose.filter(func(e): return not gone.call(e))
	for e in rocks:
		if gone.call(e):
			_free(e.node)
	rocks = rocks.filter(func(e): return not gone.call(e))


func _spawn_fever_planets() -> void:
	for i in 1 + randi() % 2:
		var pos := Vector2(randf_range(-FIELD_HALF.x, FIELD_HALF.x) * 0.9, randf_range(-FIELD_HALF.y, FIELD_HALF.y) * 0.9)
		var p := _make_planet(pos, SPAWN_Z - randf() * 6.0, "", true)
		var k := randf_range(0.7, 1.0)
		p.base_scale *= k
		p.radius *= k
		loose.append(p)


# ================================================================ effects

func _smash(p: Dictionary, wrong: bool, size: float = 1.0) -> void:
	p.alive = false
	var node: MeshInstance3D = p.node
	node.visible = false
	_burst(node.position, p.palette, wrong, size)


func _burst(center: Vector3, pal: Array, wrong: bool, size: float) -> void:
	var rock_mat := _planet_material(pal[1], pal[0])
	if wrong:
		rock_mat.set_shader_parameter("hit_flash", 0.6)
	for i in int(DEBRIS_COUNT * clampf(size, 0.5, 1.5)):
		var entry: Dictionary = rock_meshes[randi() % rock_meshes.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = entry.mesh
		mi.material_override = rock_mat
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.3, 0.8)).normalized()
		mi.position = center + dir * PLANET_RADIUS * 0.5 * size
		var s0: float = float(entry.scale) * randf_range(0.12, 0.26) * size
		mi.scale = Vector3.ONE * s0
		root3d.add_child(mi)
		debris.append({"node": mi, "vel": dir * DEBRIS_SPEED * randf_range(0.6, 1.2) * sqrt(size),
			"spin": Vector3(randf(), randf(), randf()) * 6.0, "t": 0.0,
			"life": DEBRIS_LIFE * randf_range(0.7, 1.1), "s0": s0})
	var flash := MeshInstance3D.new()
	flash.mesh = QuadMesh.new()
	flash.material_override = flash_material.duplicate()
	if wrong:
		(flash.material_override as StandardMaterial3D).albedo_color = Color(2.5, 0.5, 0.4)
	# Behind the centre, so a ship ramming it stays in front of the light.
	flash.position = center + Vector3(0, 0, -0.6)
	root3d.add_child(flash)
	flashes.append({"node": flash, "t": 0.0, "life": FLASH_LIFE, "kind": "flash", "size": size})
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	ring.mesh = torus
	ring.material_override = ring_material.duplicate()
	ring.rotation.x = PI * 0.5
	ring.position = center + Vector3(0, 0, -0.3)
	root3d.add_child(ring)
	flashes.append({"node": ring, "t": 0.0, "life": RING_LIFE, "kind": "ring", "size": size})


func _spark(at: Vector3) -> void:
	var flash := MeshInstance3D.new()
	flash.mesh = QuadMesh.new()
	flash.material_override = flash_material.duplicate()
	flash.position = at
	root3d.add_child(flash)
	flashes.append({"node": flash, "t": 0.0, "life": 0.18, "kind": "flash", "size": 0.3})


func _update_fx(delta: float, running: bool) -> void:
	for w in waves:
		for p in w.planets:
			if p.alive:
				_animate(p, delta)
	for p in loose:
		if p.alive:
			_animate(p, delta)
	for r in rocks:
		if r.alive:
			var node: MeshInstance3D = r.node
			node.position = Vector3(r.pos.x, r.pos.y, r.z)
			node.rotation += r.spin * delta
			if r.flash > 0.0:
				r.flash = maxf(0.0, r.flash - delta * 6.0)
				(node.material_override as ShaderMaterial).set_shader_parameter("hit_flash", r.flash * 0.5)
	if ship_pivot != null:
		ship_pivot.position = Vector3(ship_pos.x, ship_pos.y, 0.0)
		var bank: float = clampf(-ship_vel.x * SHIP_BANK_PER_SPEED, -SHIP_BANK_MAX, SHIP_BANK_MAX)
		var pitch: float = clampf(ship_vel.y * SHIP_PITCH_PER_SPEED, -SHIP_PITCH_MAX, SHIP_PITCH_MAX)
		ship_pivot.rotation = Vector3(pitch, 0.0, bank)
		ship_pivot.visible = main == null or main._hurt_blink_alpha() > 0.5
	for i in drone_nodes.size():
		var side: float = -1.0 if i == 0 else 1.0
		var want := Vector3(ship_pos.x + side * 1.15, ship_pos.y + 0.35, 0.3)
		var d: Node3D = drone_nodes[i]
		d.position = d.position.lerp(want, 1.0 - exp(-10.0 * delta))
	for d in debris:
		d.t += delta
		var node: MeshInstance3D = d.node
		node.position += d.vel * delta
		d.vel *= maxf(0.0, 1.0 - 1.2 * delta)
		node.rotation += d.spin * delta
		node.scale = Vector3.ONE * maxf(d.s0 * (1.0 - d.t / d.life), 0.0001)
	for d in debris:
		if d.t >= d.life:
			_free(d.node)
	debris = debris.filter(func(d): return d.t < d.life)
	for f in flashes:
		f.t += delta
		var u: float = clampf(f.t / f.life, 0.0, 1.0)
		var node: MeshInstance3D = f.node
		var m := node.material_override as StandardMaterial3D
		if f.kind == "flash":
			node.scale = Vector3.ONE * lerpf(1.2, 4.0, u) * f.size
			m.albedo_color.a = 1.0 - u
		else:
			node.scale = Vector3.ONE * lerpf(1.0, 2.8, u) * f.size
			m.albedo_color.a = (1.0 - u) * (1.0 - u) * 0.8
	for f in flashes:
		if f.t >= f.life:
			_free(f.node)
	flashes = flashes.filter(func(f): return f.t < f.life)
	var flow: float = speed() if running else BASE_SPEED * 0.25
	var stretch: float = 3.0 if phase == Phase.FEVER else 1.0
	if streaks != null:
		var mm := streaks.multimesh
		for i in streak_pos.size():
			var sp: Vector3 = streak_pos[i]
			sp.z += flow * 1.6 * delta
			if sp.z > REMOVE_Z:
				sp.z -= 170.0
			streak_pos[i] = sp
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 3.0 * stretch)), sp))
	if sky_material != null:
		sky_material.uv1_offset.y -= flow * 0.00015 * delta
	if camera != null:
		var want: float = CAMERA_FOV + (FEVER_FOV_BOOST if phase == Phase.FEVER else 0.0)
		camera.fov = lerpf(camera.fov, want, 1.0 - exp(-4.0 * delta))


func _animate(p: Dictionary, delta: float) -> void:
	var node: MeshInstance3D = p.node
	node.rotation += p.spin * delta
	if p.flash > 0.0:
		p.flash = maxf(0.0, p.flash - delta * 2.0)
		p.mat.set_shader_parameter("hit_flash", p.flash)
	_place(p)


# ================================================================ input

## Relative drag. Mouse events that Godot emulates from a touch are ignored,
## or a finger on a phone would move the ship twice.
func handle_input(event: InputEvent) -> bool:
	var rel := Vector2.ZERO
	if event is InputEventScreenDrag:
		rel = event.relative
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		rel = event.relative
	else:
		return false
	ship_target += Vector2(rel.x, -rel.y) * (DRAG_GAIN / px_per_unit())
	ship_target = ship_target.clamp(-FIELD_HALF, FIELD_HALF)
	return true


## Screen pixels per world unit on the flight plane, at its centre.
func px_per_unit() -> float:
	var s := project(Vector3.ZERO)
	return s.z if s.z > 0.0 else 60.0


# ================================================================ 2D overlay

## Where a world point lands on the game screen, and how many game pixels one
## world unit spans there. z <= 0 means behind the camera.
func project(p: Vector3) -> Vector3:
	if camera == null or camera.is_position_behind(p):
		return Vector3(0, 0, -1)
	var k: Vector2 = view_size / Vector2(viewport.size)
	var a: Vector2 = camera.unproject_position(p) * k
	var b: Vector2 = camera.unproject_position(p + camera.global_transform.basis.x) * k
	return Vector3(a.x, a.y, a.distance_to(b))


func draw_labels(ci: CanvasItem, font: Font) -> void:
	for w in waves:
		if w.resolved:
			continue
		for p in w.planets:
			if not p.alive or p.label == "":
				continue
			var node: MeshInstance3D = p.node
			var s := project(node.position)
			if s.z <= 0.0:
				continue
			var r: float = s.z * node.scale.x / maxf(p.base_scale, 0.0001) * PLANET_RADIUS
			if r < 4.0:
				continue
			var emoji: bool = p.get("emoji", false)
			var f: Font = emoji_font if emoji else font
			var font_size := int(clampf(r * (0.8 if emoji else 0.62), 8.0, 80.0))
			var text_w: float = f.get_string_size(p.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var size := Vector2(maxf(text_w + font_size * 0.7, r * 0.95), font_size * 1.3)
			var sb := StyleBoxFlat.new()
			sb.bg_color = PLATE_FILL
			sb.border_color = PLATE_EDGE
			sb.set_border_width_all(maxi(1, int(font_size * 0.09)))
			sb.set_corner_radius_all(int(font_size * 0.3))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, Rect2(Vector2(s.x, s.y) - size * 0.5, size))
			ci.draw_string(f, Vector2(s.x - text_w * 0.5, s.y + font_size * 0.36), p.label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PLATE_TEXT)


## Inside the question box, the arrow or the hand; under it, the cycle's
## progress, the boss's health or fever's time; and the weapon, bottom left.
func draw_hud(ci: CanvasItem, box: Rect2) -> void:
	var font: Font = main.combo_font if main.combo_font != null else ThemeDB.fallback_font
	var w := upcoming_wave()
	var c := box.get_center()
	if phase == Phase.QUIZ and not w.is_empty():
		if w.kind == Kind.ARROW:
			_draw_arrow(ci, c, box.size.y * 0.34, int(w.dir), ARROW_REVERSE if w.reverse else ARROW_NORMAL)
		elif w.kind == Kind.RPS:
			var fs := int(box.size.y * 0.5)
			var hand: String = HANDS[int(w.hand)]
			var tw: float = emoji_font.get_string_size(hand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(emoji_font, Vector2(c.x - tw - 6.0, c.y + fs * 0.36), hand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			ci.draw_string(font, Vector2(c.x + 8.0, c.y + fs * 0.3), "WIN!", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.7), Color(0.85, 0.15, 0.1))
	var gw: float = box.size.x * 0.62
	var gh := 10.0
	var rect := Rect2(Vector2(c.x - gw * 0.5, box.end.y + 8.0), Vector2(gw, gh))
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.04, 0.12, 0.7)
	back.border_color = Color(1, 1, 1, 0.85)
	back.set_border_width_all(2)
	back.set_corner_radius_all(int(gh * 0.5))
	back.anti_aliasing = true
	ci.draw_style_box(back, rect)
	var frac := 0.0
	var col := Color(0.35, 0.85, 1.0)
	match phase:
		Phase.FEVER:
			frac = 1.0 - clampf(phase_time / FEVER_DURATION, 0.0, 1.0)
			col = Color(1.0, 0.45, 0.2).lerp(Color(1.0, 0.85, 0.3), 0.5 + 0.5 * sin(phase_time * 12.0))
		Phase.BOSS:
			frac = clampf(boss_hp / boss_max_hp, 0.0, 1.0)
			col = Color(0.95, 0.2, 0.3)
		_:
			frac = float(quiz_index) / float(QUIZ_PER_CYCLE)
	if frac > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(int((gh - 4.0) * 0.5))
		fill.anti_aliasing = true
		ci.draw_style_box(fill, Rect2(rect.position + Vector2(2, 2), Vector2((rect.size.x - 4.0) * frac, gh - 4.0)))
	var wname: String = ["BLASTER", "SPREAD", "LASER"][weapon]
	var txt := "%s  Lv%d%s" % [wname, level, ("  +%d DRONE" % drones) if drones > 0 else ""]
	var pos := Vector2(14.0, view_size.y - 18.0)
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		ci.draw_string(font, pos + o, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.05, 0.04, 0.12))
	ci.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.86, 0.3))


func _draw_arrow(ci: CanvasItem, c: Vector2, size: float, dir: int, color: Color) -> void:
	# Drawn pointing right, then turned: slots are left, right, up, down.
	var pts := PackedVector2Array([
		Vector2(-0.9, -0.28), Vector2(0.15, -0.28), Vector2(0.15, -0.62),
		Vector2(0.95, 0.0), Vector2(0.15, 0.62), Vector2(0.15, 0.28), Vector2(-0.9, 0.28)])
	var ang: float = [PI, 0.0, -PI * 0.5, PI * 0.5][dir]
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + p.rotated(ang) * size)
	ci.draw_colored_polygon(out, color)
	var ring := out.duplicate()
	ring.append(out[0])
	ci.draw_polyline(ring, Color(0.05, 0.04, 0.12), 2.5, true)
