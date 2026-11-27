class_name SpaceRun
extends Node

## The space game (2.0). A ship seen from behind, steered up/down/left/right by
## dragging anywhere, fires on its own while the run goes round one cycle:
##
##   PATTERN  one pattern of PATTERN_LEN gate steps in a row, one rule for the
##            whole pattern, shown in the question box: fly through the gate
##            of the box's colour (Kind.COLOR), the gate the box's arrow
##            points at (Kind.ARROW), or the gates of the box's row of
##            symbols in order (Kind.SEQUENCE). Each step is a row of gates; the ship is
##            drawn into the gate of the quarter it is in. A right gate pays
##            stardust and adds to the streak, which speeds the world up and
##            pays more; a wrong one only breaks the streak — no heart, no
##            weapon. Asteroids fly between the steps and cost a heart.
##   FEVER    after a pattern with every step right: eight seconds at speed,
##            every planet touched or shot is smashed for points and stardust,
##            nothing costs a heart.
##   BOSS     after PATTERNS_PER_CYCLE patterns an enemy ship arrives. A strong
##            weapon melts it; a weak one can still win by dodging long
##            enough. Its shots cost a heart. Then the next, harder cycle.
##
## The weapon grows only with the streak (POWER_EVERY), and never drops.
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

enum Phase { PATTERN, BOSS, FEVER }
enum Kind { COLOR, ARROW, SEQUENCE }
enum Weapon { BLASTER, SPREAD, LASER }

const KIT_PATH := "res://assets/synty_space/space_kit.glb"
const LAND_MASK_PATH := "res://assets/synty_space/land_mask.png"
const CLOUD_MASK_PATH := "res://assets/synty_space/cloud_mask.png"
const SKY_PATH := "res://assets/synty_space/sky.png"
## Hides the sky picture's top/bottom seam while it scrolls — see its header.
const SKY_SHADER_PATH := "res://assets/shaders/space_sky.gdshader"
const PLANET_SHADER_PATH := "res://assets/shaders/planet.gdshader"
const SHIP_NODE := "Ship_Fighter_05"
const BOSS_NODE := "Ship_Bomber_04"
const PLANET_NODES := ["Planet_01", "Planet_02", "Planet_05", "Planet_08", "Planet_09", "Planet_10"]
const ROCK_NODES := ["Asteroid_01", "Asteroid_02", "Asteroid_03", "Asteroid_05"]
const GATE_RING_NODE := "Veh_WarpGate_Inner_01"
const GATE_GLOW_NODE := "Veh_WarpGate_Glow_01"

# ---- the field (world units, on the flight plane) ----
const FIELD_HALF := Vector2(2.3, 3.0)
# left, right, up, down. Far enough apart that no point touches two planets.
const SLOTS := [Vector2(-1.85, 0.0), Vector2(1.85, 0.0), Vector2(0.0, 2.3), Vector2(0.0, -2.3)]
const PLANET_RADIUS := 1.0
# The quiz targets are gates, flown through rather than rammed. GATE_RADIUS
# is the open hole, judged like a planet was: the ship's centre within
# GATE_RADIUS + SHIP_HIT_RADIUS, so clipping the inside of the ring still
# counts. The ring's outer edge is GATE_OUTER_OF_HOLE times the hole —
# Synty's inner warp ring measures 175.5 inside and 235.9 outside — which
# keeps two neighbouring slots' rings (2.95 apart) from touching.
#
# Since 2026-11-27 the hole no longer decides anything — the ship's quarter
# does (region_of) — so GATE_RADIUS is only how big the gate is drawn. 1.08
# is as big as it goes: the diagonal neighbours are 2.95 apart and two outer
# rings meet at 2.95 / (2 * GATE_OUTER_OF_HOLE) = 1.10.
const GATE_RADIUS := 1.08
const GATE_OUTER_OF_HOLE := 235.9 / 175.5
const GATE_ROLL_SPEED := 0.35      # rad/s, each gate one way or the other
const GATE_GLOW := Color(0.35, 0.85, 1.0, 0.55)
const GATE_GLOW_RIGHT := Color(1.0, 0.85, 0.35, 1.0)
const GATE_GLOW_WRONG := Color(1.0, 0.25, 0.2, 1.0)
# The gate in the ship's quarter glows brighter, so the player can see which
# gate they are about to be drawn into. Same lift for right and wrong — it
# says "this one", never "this is right". A colour gate brightens its own
# colour by GATE_AIM_LIFT; a plain one goes to GATE_GLOW_AIM.
const GATE_GLOW_AIM := Color(0.75, 0.97, 1.0, 1.0)
const GATE_AIM_LIFT := 0.45
# Kind.COLOR's colours. Four, one per slot at most, and far apart in hue so a
# gate small near the vanishing point still reads. Red and green alone would
# be the colour-blind pair; blue and yellow keep at least two of any four
# telling apart for everyone, and a symbol per colour is the next step.
const GATE_COLORS := [
	Color(1.0, 0.22, 0.22, 1.0),   # red
	Color(0.25, 0.55, 1.0, 1.0),   # blue
	Color(0.25, 1.0, 0.35, 1.0),   # green
	Color(1.0, 0.85, 0.15, 1.0),   # yellow
]
const SHIP_HIT_RADIUS := 0.3
const SHIP_WIDTH := 1.7

# ---- speed ----
const SPAWN_Z := -70.0
const BASE_SPEED := 24.0           # 70 / 24 = 2.9 s from a wave appearing to its judgement
const GROW_DISTANCE := 10.0
const REMOVE_Z := 13.0
const PASS_SHRINK_DISTANCE := 4.0  # past the plane (z = 0); the camera is at 10
# Pacing a pattern (2026-11-27). The steps come one after another, STEP_GAP
# apart, so the next one is in sight and can be read while the current one
# is being flown. 22 at first, about three in sight; the owner found the
# gates too close together and it went to 34 the same day, two in sight.
# A pattern starts slow — at PACE_START a step takes 34 / (24 * 0.6) = 2.4 s
# — and every right gate in a row adds PACE_PER_STREAK, up to PACE_MAX
# (1.1 s a step at a streak of ten). A wrong gate breaks the streak, and the world eases back to
# PACE_START: whoever just missed gets the easy speed back. Each cycle is also
# 8% faster overall (speed()).
#
# Before patterns, one question wave slowed only near the gate; with steps
# this close that pulsed the world every step.
const STEP_GAP := 34.0
const PACE_START := 0.6
const PACE_PER_STREAK := 0.06
const PACE_MAX := 1.25
const PACE_EASE := 3.0             # 1/s, how fast the speed follows its target
# The aim glow lights up once the step is this close: the front step only.
const AIM_Z := -18.0
const WARP_BOOST := 0.5            # extra speed right after a pass, decaying
const WARP_BOOST_DECAY := 3.0      # 1/s
const WARP_FOV_KICK := 6.0         # degrees at the top of the boost
# The draw (2026-11-27). Steering a 0.3-wide ship into a 1-wide hole was
# where most wrong answers came from — testers on the right side of the
# screen slid past the right gate. Now the field is cut into four quarters
# along its diagonals, one per slot (region_of), and when the wave reaches
# CAPTURE_Z the ship is pulled into the gate of the quarter it is in, right
# or wrong. A quarter with no gate pulls nothing and costs like a wrong gate.
# CAPTURE_Z is 0.42 s of pull at PACE_START and 0.2 s at PACE_MAX.
const CAPTURE_Z := -6.0
const CAPTURE_SHIP_SCALE := 0.55   # the ship shrinks into the hole as it goes in
const SQUEEZE_RECOVER := 5.0       # 1/s, back to full size after the pass

# ---- the cycle ----
# Ten steps a pattern, as the owner first guessed; to be settled by playing.
const PATTERN_LEN := 10
const PATTERNS_PER_CYCLE := 2
# The arrow sometimes comes red, meaning "the other way". Not in the first
# cycle, so the plain rule is learned before it is bent.
const ARROW_REVERSE_CHANCE := 0.3
# Kind.SEQUENCE: the box shows a row of symbols and the steps go through it
# in order, round again until the pattern ends. Three in the first cycle,
# four after: long enough that the order has to be read, short enough to
# keep in mind while flying. The marks are the UI kit's (build_ui_kit.gd
# SYMBOLS); without the kit each falls back to its number.
const SEQ_LEN := [3, 4]
const SYMBOL_COUNT := 10
const SYMBOL_PATH := "res://assets/synty_ui/symbol_%02d.png"

# ---- the streak: stardust and power ----
# A right gate pays STARDUST_PER_GATE times the streak it makes (1, 2, 3 ...),
# so a whole pattern in a row pays 55 against 10 for one broken every step.
const STARDUST_PER_GATE := 1
const STARDUST_FEVER_SMASH := 2
const STARDUST_BOSS := 20
# Every POWER_EVERY gates in a row the weapon goes up a step (_power_up);
# a whole pattern right also brings the next weapon or a drone.
const POWER_EVERY := 3

# ---- asteroids between the steps ----
# HUD art from the Synty UI kit (see Main.HUD_SCORE_BAR_PATH): the gauge's
# track, and the backing under the weapon readout. The stardust slot wears
# the same frame as the health slot, Main.HUD_SIDE_SLOT_PATH.
const HUD_GAUGE_PATH := "res://assets/synty_ui/gauge.png"
const HUD_GAUGE_CAP := 18.0            # baked px: the pill's round end
const HUD_GAUGE_INSET := Vector2(9.0, 5.0)   # track -> fill, on screen
const HUD_WEAPON_BACK_PATH := "res://assets/synty_ui/weapon_back.png"
const HUD_STARDUST_ICON_PATH := "res://assets/synty_ui/icon_stardust.png"
# The gauge goes gold while every step of the pattern so far was right, the
# fever it is heading for.
const GAUGE_PERFECT_COLOR := Color(1.0, 0.8, 0.25)
# The stardust count wears the mode select's readout colour.
const STARDUST_COLOR: Color = preload("res://scripts/ModeSelectScreen.gd").STARDUST_COLOR
# Rocks in each gap between two steps: ROCKS_PER_GAP plus ROCKS_PER_CYCLE a
# cycle, the fraction a chance of one more. None before the first step.
# They keep ROCK_CLEAR off every slot's centre, where the ship comes out of
# one gate and is drawn into the next — a rock there could not be dodged.
const ROCKS_PER_GAP := 0.6
const ROCKS_PER_CYCLE := 0.4
const ROCK_CLEAR := 1.3
const ASTEROID_RADIUS := Vector2(0.45, 0.8)
const ASTEROID_HP := 3.0
const ASTEROID_POINTS := 5
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
# Testing on PC (2026-11-27): the arrow keys, or WASD, steer the ship in a
# debug build, KEY_STEER_SPEED world units a second — the field is 4.6 wide,
# so about 0.8 s edge to edge. A release build ignores the keyboard: the
# game is a touch game, and a phone with a keyboard should not steer twice.
const KEY_STEER_SPEED := 6.0
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
# The answers ride on their gates (draw_labels). Until 2026-11-27 they were
# shown at full size on the flight plane from the moment a wave appeared, in
# dashed rings the gates flew in to fill; that put a plate over every quarter
# of the screen for the whole approach, and testers said it covered the play
# field. Now each answer sits in its own gate's hole and grows with it. It
# fades in over LABEL_FADE (approach() fractions) — z = -28 to -22, where the
# slowdown starts — because further out the gates are bunched near the
# vanishing point and their plates would overlap.
const LABEL_FADE := Vector2(0.6, 0.68)
const LABEL_TEXT_SCALE := 0.6      # of the gate's hole on screen
const LABEL_MIN_FONT := 15.0       # px: the gate is still small when its answer appears
const LABEL_PLATE_ALPHA := 0.8
const LABEL_PLATE_UNDER_SHIP := 0.3   # the ship is being drawn through it
# Kind.SEQUENCE's marks sit in their gates' holes, on every step in sight
# and not only the front one, so the next symbols can be read ahead as the
# colours can. They fade in over SYMBOL_FADE (approach() fractions) and are
# SYMBOL_IN_HOLE of the hole across, never under SYMBOL_MIN_PX. A mark is
# drawn inside its own ring, so unlike a text plate it cannot spill onto a
# neighbour however small the gates are.
const SYMBOL_FADE := Vector2(0.2, 0.32)
const SYMBOL_IN_HOLE := 0.78
const SYMBOL_MIN_PX := 12.0
const SYMBOL_BACK := Color(0.03, 0.04, 0.10, 0.55)
# The box's row: the symbol to fly through next at full strength in a gold
# ring, the rest dimmed.
const SEQ_DIM := 0.38
const SEQ_NOW_RING := Color(1.0, 0.8, 0.25)
const ARROW_NORMAL := Color(0.18, 0.55, 1.0)
const ARROW_REVERSE := Color(0.95, 0.2, 0.2)

var main: Node
var viewport: SubViewport
var camera: Camera3D
var root3d: Node3D
var ship_pivot: Node3D
var ship_model: Node3D
var view_size := Vector2(480, 854)

var ship_pos := Vector2.ZERO
var ship_target := Vector2.ZERO
var ship_vel := Vector2.ZERO
var pace := 1.0                  # follows _pace_target(): the streak's speed
var boost := 0.0                 # 0..1, the lunge after a pass
var squeeze := 0.0               # 0..1, the ship shrinking into a gate

var phase: int = Phase.PATTERN
var phase_time := 0.0
var cycle := 0                   # bosses beaten this run
var patterns_done := 0           # patterns finished this cycle

# the pattern under way
var pattern_kind: int = Kind.COLOR
var pattern_color := 0           # Kind.COLOR: index into GATE_COLORS
var pattern_seq: Array = []       # Kind.SEQUENCE: symbol indices, in order
var steps_spawned := 0
var steps_done := 0              # steps judged
var steps_right := 0
var streak := 0                  # right gates in a row

## Step waves: {"planets", "z", "resolved", "kind", "dir", "reverse"}
var waves: Array = []
## Free-flying things: fever planets (loose) and asteroids (rocks).
var loose: Array = []
var rocks: Array = []
var fever_spawn_timer := 0.0
var palette_cursor := 0

# weapon
var weapon: int = Weapon.BLASTER
var level := 1
var drones := 0
var fire_timer := 0.0
var bullets: Array = []
var drone_nodes: Array = []

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
## The gate's ring and glow band, and the transform that stands them up to
## face down Z, scaled and centred on the ring. null without the kit.
var gate_ring_mesh: Mesh
var gate_glow_mesh: Mesh
var gate_part_xform := Transform3D.IDENTITY
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
var sky_material: ShaderMaterial
## How far the sky has slid, in picture heights.
var sky_scroll := 0.0
var kit_loaded := false
var symbol_textures: Array = []   # Kind.SEQUENCE's marks, with mipmaps; null where missing


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
		_load_gate(kit)
		kit.free()
		kit_loaded = not planet_meshes.is_empty()
	if planet_meshes.is_empty():
		planet_meshes.append({"mesh": SphereMesh.new(), "scale": 1.0})
	if rock_meshes.is_empty():
		var rock := SphereMesh.new()
		rock.radial_segments = 6
		rock.rings = 3
		rock_meshes.append({"mesh": rock, "scale": 1.0})


## The ring lies in the model's XZ plane (glTF is Y-up); it is stood up to
## face down Z and scaled so its outer edge is GATE_RADIUS * GATE_OUTER_OF_HOLE.
## The glow band is the same prefab's other half and keeps its place in it.
func _load_gate(kit: Node) -> void:
	var ring_mi := kit.find_child(GATE_RING_NODE, true, false) as MeshInstance3D
	var glow_mi := kit.find_child(GATE_GLOW_NODE, true, false) as MeshInstance3D
	if ring_mi == null or ring_mi.mesh == null:
		return
	var aabb := ring_mi.mesh.get_aabb()
	var s: float = GATE_RADIUS * GATE_OUTER_OF_HOLE / (maxf(aabb.size.x, aabb.size.z) * 0.5)
	var basis := Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * s)
	gate_part_xform = Transform3D(basis, basis * -aabb.get_center())
	gate_ring_mesh = ring_mi.mesh
	if glow_mi != null:
		gate_glow_mesh = glow_mi.mesh


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
	sky_material = ShaderMaterial.new()
	sky_material.shader = load(SKY_SHADER_PATH)
	sky_material.set_shader_parameter("sky", load(SKY_PATH))
	sky_material.set_shader_parameter("tint", Color(1.25, 1.25, 1.25))
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
func speed() -> float:
	return BASE_SPEED * (1.0 + 0.08 * cycle) * (FEVER_SPEED if phase == Phase.FEVER else 1.0) * pace * (1.0 + WARP_BOOST * boost)


## The speed `pace` eases toward: the streak's in a pattern, full elsewhere.
func _pace_target() -> float:
	if phase != Phase.PATTERN:
		return 1.0
	return minf(PACE_MAX, PACE_START + PACE_PER_STREAK * streak)


## Two gates a step in the first cycle, three in the second, then four.
func planets_for_cycle(c: int) -> int:
	return clampi(2 + c, 2, 4)


# ================================================================ run state

func reset_run() -> void:
	_clear_world()
	_remove_boss()
	fire_timer = 0.0
	cycle = 0
	patterns_done = 0
	weapon = Weapon.BLASTER
	level = 1
	drones = 0
	_sync_drones()
	ship_pos = Vector2.ZERO
	ship_target = Vector2.ZERO
	ship_vel = Vector2.ZERO
	pace = PACE_START
	boost = 0.0
	squeeze = 0.0
	if camera != null:
		camera.fov = CAMERA_FOV
	_enter(Phase.PATTERN)


## After a revive: what was in flight is gone; a boss fight goes on with the
## boss's health as it was, anything else starts the pattern over.
func revive() -> void:
	_clear_world()
	ship_target = Vector2.ZERO
	boost = 0.0
	squeeze = 0.0
	if phase == Phase.BOSS:
		phase_time = BOSS_ENTER_TIME
		boss_fire_timer = BOSS_FIRE_INTERVAL * 1.5
	else:
		_enter(Phase.PATTERN)


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
		Phase.PATTERN:
			_begin_pattern()
		Phase.BOSS:
			_spawn_boss()
		Phase.FEVER:
			fever_spawn_timer = 0.4
			if main != null:
				main._space_fever_started()


## What the question box shows as text. The pattern's rule is drawn, not
## written (draw_hud), so the box stays up, empty, under it.
func question() -> String:
	match phase:
		Phase.FEVER:
			return "FEVER!"
		Phase.BOSS:
			return "BOSS!"
	return " "


## The front step: the first one not yet judged.
func upcoming_wave() -> Dictionary:
	for w in waves:
		if not w.resolved:
			return w
	return {}


## Whether every step of the pattern so far was right.
func pattern_perfect() -> bool:
	return steps_right == steps_done


# ================================================================ patterns

## The first cycle is colour, then symbols; arrows, the closest to the old
## quiz, join from the second cycle, which draws any of the three.
func _next_kind() -> int:
	if cycle == 0 and patterns_done < 2:
		return [Kind.COLOR, Kind.SEQUENCE][patterns_done]
	return [Kind.COLOR, Kind.ARROW, Kind.SEQUENCE][randi() % 3]


func _begin_pattern(kind: int = -1) -> void:
	pattern_kind = _next_kind() if kind < 0 else kind
	pattern_color = randi() % GATE_COLORS.size()
	pattern_seq = _random_symbols(SEQ_LEN[mini(cycle, SEQ_LEN.size() - 1)])
	steps_spawned = 0
	steps_done = 0
	steps_right = 0
	streak = 0
	if main != null:
		spawn_wave()


## Spawns the next step of the pattern at SPAWN_Z, and the rocks of the gap
## between it and the step before. Returns the step.
func spawn_wave() -> Dictionary:
	var w := _make_step(pattern_kind)
	if steps_spawned > 0 and not waves.is_empty():
		# Exactly STEP_GAP behind the step before, not wherever this frame
		# happened to cross the threshold.
		var z: float = (waves.back().z as float) - STEP_GAP
		w.z = z
		for p in w.planets:
			p.z = z
			_place(p)
		_spawn_gap_rocks(z + STEP_GAP * 0.5)
	steps_spawned += 1
	waves.append(w)
	return w


## One step of `kind`: planets_for_cycle gates in distinct slots, exactly one
## marked correct.
##   COLOR  every gate a different colour, one of them the pattern's.
##   ARROW  the box points at a slot; red means the slot opposite, so that
##          one is always in the step as well.
##   SEQUENCE  the right gate carries the sequence's next symbol; the wrong
##          ones carry the sequence's other symbols first — the ones the
##          player is holding in mind — then any others.
func _make_step(kind: int) -> Dictionary:
	var n: int = planets_for_cycle(cycle)
	var w := {"planets": [], "z": SPAWN_Z, "resolved": false, "kind": kind,
		"dir": -1, "reverse": false}
	var slots: Array = [0, 1, 2, 3]
	slots.shuffle()
	slots = slots.slice(0, n)
	var correct_slot: int = slots[0]
	var colors: Array = []
	var symbols: Array = []
	if kind == Kind.SEQUENCE:
		var want: int = pattern_seq[steps_spawned % pattern_seq.size()]
		var others: Array = pattern_seq.filter(func(s): return s != want)
		others.shuffle()
		var rest: Array = range(SYMBOL_COUNT).filter(func(s): return s != want and not others.has(s))
		rest.shuffle()
		symbols = [want] + others + rest
		w["symbol"] = want
	elif kind == Kind.COLOR:
		for i in GATE_COLORS.size():
			if i != pattern_color:
				colors.append(i)
		colors.shuffle()
		colors.push_front(pattern_color)
	else:
		var reverse: bool = cycle > 0 and randf() < ARROW_REVERSE_CHANCE
		var shown: int = _opposite(correct_slot) if reverse else correct_slot
		if reverse and not slots.has(shown):
			slots[slots.size() - 1] = shown
		w.reverse = reverse
		w.dir = shown
	for i in slots.size():
		var s: int = slots[i]
		var p := _make_gate(SLOTS[s], SPAWN_Z, "", s == correct_slot)
		p["slot"] = s
		if kind == Kind.COLOR:
			# slots[0] is the correct slot, and colors[0] the pattern's colour.
			_tint_gate(p, GATE_COLORS[colors[i]])
		elif kind == Kind.SEQUENCE:
			p["symbol"] = symbols[i]
		w.planets.append(p)
	return w


## `n` different symbols in a random order.
func _random_symbols(n: int) -> Array:
	var all: Array = range(SYMBOL_COUNT)
	all.shuffle()
	return all.slice(0, n)


static func _opposite(slot: int) -> int:
	return [1, 0, 3, 2][slot]


## Rocks for the gap centred on `z`, kept ROCK_CLEAR off every slot's centre.
func _spawn_gap_rocks(z: float) -> void:
	var want: float = ROCKS_PER_GAP + ROCKS_PER_CYCLE * cycle
	var count: int = int(want) + (1 if randf() < want - floorf(want) else 0)
	for i in count:
		var pos := Vector2.ZERO
		for attempt in 12:
			pos = Vector2(randf_range(-FIELD_HALF.x, FIELD_HALF.x), randf_range(-FIELD_HALF.y, FIELD_HALF.y)) * 0.85
			var clear := true
			for s in SLOTS:
				if pos.distance_to(s) < ROCK_CLEAR:
					clear = false
			if clear:
				break
		_spawn_asteroid(pos, z + randf_range(-3.0, 3.0))


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


## A quiz gate: the same dictionary as a planet, so the wave code moves, places
## and judges it the same way; "gate" marks what differs — it is flown
## through, lights up instead of breaking, and only rolls about its own axis.
## An ARROW gate glows the plain GATE_GLOW until judged, since a colour that
## differed would give the answer away; a COLOR gate's colour is the answer's
## language, so it wears it (_tint_gate).
func _make_gate(pos: Vector2, z: float, label: String, correct: bool) -> Dictionary:
	var node := MeshInstance3D.new()
	var glow_mat := _add_material(GATE_GLOW)
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if gate_ring_mesh != null:
		var ring := MeshInstance3D.new()
		ring.mesh = gate_ring_mesh
		ring.transform = gate_part_xform
		node.add_child(ring)
		if gate_glow_mesh != null:
			var glow := MeshInstance3D.new()
			glow.mesh = gate_glow_mesh
			glow.transform = gate_part_xform
			glow.material_override = glow_mat
			node.add_child(glow)
	else:
		var torus := TorusMesh.new()
		torus.inner_radius = GATE_RADIUS
		torus.outer_radius = GATE_RADIUS * GATE_OUTER_OF_HOLE
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.rotation.x = PI * 0.5
		ring.material_override = glow_mat
		node.add_child(ring)
	node.rotation.z = randf() * TAU
	root3d.add_child(node)
	var p := {
		"node": node, "mat": null, "glow": glow_mat, "pos": pos, "z": z, "label": label,
		"correct": correct, "alive": true, "judged": false, "palette": PALETTES[0],
		"base_scale": 1.0, "radius": GATE_RADIUS, "gate": true,
		"spin": Vector3(0.0, 0.0, GATE_ROLL_SPEED * (1.0 if randf() < 0.5 else -1.0)),
		"flash": 0.0, "flash_color": GATE_GLOW_RIGHT, "base_glow": GATE_GLOW,
	}
	_place(p)
	return p


## Gives gate `p` its own colour: the glow band wears it, a touch see-through
## like the plain glow so the ring's metal still shows.
func _tint_gate(p: Dictionary, color: Color) -> void:
	p.base_glow = Color(color.r, color.g, color.b, 0.8)
	(p.glow as StandardMaterial3D).albedo_color = p.base_glow


## The ship went through `p`: it lights up gold if right, red if wrong, with
## the burst's flash and ring but no debris — nothing broke. It flies on past
## the camera like the rest of its wave.
func _pass_gate(p: Dictionary, right: bool) -> void:
	p.alive = false
	p.flash = 1.0
	p.flash_color = GATE_GLOW_RIGHT if right else GATE_GLOW_WRONG
	_burst(p.node.position, p.palette, not right, 1.0, false)


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
	# Past the plane a planet has been judged and is only on its way out, but
	# it is still heading for the camera, and the top slot's sits almost on
	# the camera's line: it swelled to cover half the screen just as the next
	# wave's markers appeared. It shrinks away over PASS_SHRINK_DISTANCE
	# instead, which still reads as flying past.
	# Gates too: they were let through at first, being mostly hole, but the
	# camera passes through the top slot's ring, which then filled the whole
	# screen for a moment, edge to edge, over the next wave's markers.
	grow *= 1.0 - smoothstep(0.0, PASS_SHRINK_DISTANCE, p.z)
	var node: MeshInstance3D = p.node
	node.position = Vector3(p.pos.x, p.pos.y, p.z)
	node.scale = Vector3.ONE * maxf(p.base_scale * grow, 0.0001)


func _touching(p: Dictionary) -> bool:
	return ship_pos.distance_to(p.pos) <= p.radius + SHIP_HIT_RADIUS


## Eases the world toward the streak's speed, and lets the lunge after a pass
## and the ship's squeeze wear off.
func _update_pace(delta: float) -> void:
	pace = lerpf(pace, _pace_target(), 1.0 - exp(-PACE_EASE * delta))
	boost = maxf(0.0, boost - WARP_BOOST_DECAY * delta)
	var w := upcoming_wave()
	if w.is_empty() or not w.has("target"):
		squeeze = maxf(0.0, squeeze - SQUEEZE_RECOVER * delta)


## The draw. Once `w` reaches CAPTURE_Z the gate of the ship's quarter is
## fixed, and from then on the ship is pulled to its centre, arriving as the
## step reaches the plane. The pull eases in (u squared) — it starts gently
## and snaps shut, which is what being sucked in looks like. Dragging still
## moves ship_target meanwhile, but it is overwritten here every frame.
func _draw_in(w: Dictionary) -> void:
	var aim := target_gate(w, ship_pos) if not w.has("target") else w.target as Dictionary
	for p in w.planets:
		p["aim"] = w.z >= AIM_Z and is_same(p, aim)
	if w.z < CAPTURE_Z:
		return
	if not w.has("target"):
		w["target"] = aim
		w["from"] = ship_pos
	if (w.target as Dictionary).is_empty():
		return
	var u: float = clampf((w.z - CAPTURE_Z) / -CAPTURE_Z, 0.0, 1.0)
	var e: float = u * u
	ship_pos = (w.from as Vector2).lerp(w.target.pos, e)
	ship_target = ship_pos
	ship_vel = Vector2.ZERO
	squeeze = e

## Which quarter of the field `pos` is in, as a slot index: the field is cut
## along its diagonals, so each quarter holds exactly one of SLOTS. Measured
## against FIELD_HALF so the cut runs corner to corner on screen.
static func region_of(pos: Vector2) -> int:
	var n := pos / FIELD_HALF
	if absf(n.x) >= absf(n.y):
		return 0 if n.x < 0.0 else 1
	return 2 if n.y > 0.0 else 3


## The gate of `w` in the quarter `pos` is in, or {} when that quarter has none.
func target_gate(w: Dictionary, pos: Vector2) -> Dictionary:
	var r := region_of(pos)
	for p in w.planets:
		if int(p.get("slot", -1)) == r:
			return p
	return {}


## A step reaches the plane. Right: the streak grows and pays stardust, and
## every POWER_EVERY in a row the weapon steps up. Wrong, or a quarter with
## no gate: the streak is gone and nothing else — the world eases back to
## PACE_START, which is the whole cost.
func _resolve_wave(w: Dictionary) -> void:
	w.resolved = true
	steps_done += 1
	# The gate the ship was drawn into; a step that somehow skipped the capture
	# (a frame long enough to jump CAPTURE_Z) is judged by the quarter now.
	var hit: Dictionary = w.target if w.has("target") else target_gate(w, ship_pos)
	if not hit.is_empty():
		ship_pos = hit.pos
		ship_target = hit.pos
		boost = 1.0
	if not hit.is_empty() and hit.correct:
		_pass_gate(hit, true)
		steps_right += 1
		streak += 1
		main._space_correct()
		main._space_stardust(STARDUST_PER_GATE * streak)
		if streak % POWER_EVERY == 0:
			_power_up(false)
	else:
		if not hit.is_empty():
			_pass_gate(hit, false)
		streak = 0
		main._space_wrong()


## The last step of the pattern has been judged and flown past: a whole
## pattern right is worth a better weapon and the fever; then the boss once
## the cycle's patterns are done, or the next pattern.
func _end_pattern() -> void:
	patterns_done += 1
	if pattern_perfect():
		_power_up(true)
		_enter(Phase.FEVER)
	else:
		_after_fever()


## Where the run goes after a pattern, and after its fever.
func _after_fever() -> void:
	if patterns_done >= PATTERNS_PER_CYCLE:
		_enter(Phase.BOSS)
	else:
		_enter(Phase.PATTERN)


# ================================================================ power

## One step up the weapon. `big` (a whole pattern right) brings the next
## weapon, then drones, then two levels; otherwise one level. Once
## everything is at its top, the step is still a gain on paper only.
func _power_up(big: bool) -> void:
	var label := ""
	if big:
		if weapon == Weapon.BLASTER:
			weapon = Weapon.SPREAD
			label = "SPREAD!"
		elif weapon == Weapon.SPREAD:
			weapon = Weapon.LASER
			label = "LASER!"
		elif drones < MAX_DRONES:
			drones += 1
			_sync_drones()
			label = "DRONE!"
		else:
			level = mini(MAX_LEVEL, level + 2)
			label = "POWER +2"
	else:
		level = mini(MAX_LEVEL, level + 1)
		label = "POWER +1"
	if main != null:
		main._space_powered_up(label)


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


## A rock at `pos` on the plane, `z` deep. It flies with the steps, so it
## stays in the gap it was put in.
func _spawn_asteroid(pos: Vector2, z: float) -> Dictionary:
	var node := MeshInstance3D.new()
	var radius: float = randf_range(ASTEROID_RADIUS.x, ASTEROID_RADIUS.y)
	var base_scale := radius
	if rock_meshes.is_empty():
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		node.mesh = s
	else:
		var entry: Dictionary = rock_meshes[randi() % rock_meshes.size()]
		node.mesh = entry.mesh
		base_scale = float(entry.scale) * radius
	node.material_override = _planet_material(ROCK_PALETTE[0], ROCK_PALETTE[1])
	if root3d != null:
		root3d.add_child(node)
	var r := {"node": node, "pos": pos, "z": z, "radius": radius,
		"base_scale": base_scale, "hp": ASTEROID_HP * (1.0 + 0.3 * cycle),
		"spin": Vector3(randf(), randf(), randf()) * 2.0, "judged": false, "alive": true,
		"palette": ROCK_PALETTE, "flash": 0.0}
	node.position = Vector3(pos.x, pos.y, z)
	node.scale = Vector3.ONE * r.base_scale
	rocks.append(r)
	return r


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
	patterns_done = 0
	main._space_boss_down(BOSS_POINTS * cycle)
	main._space_stardust(STARDUST_BOSS * cycle)
	_enter(Phase.PATTERN)


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
	if OS.is_debug_build():
		_key_steer(delta)
	var prev := ship_pos
	ship_pos = ship_pos.lerp(ship_target, 1.0 - exp(-SHIP_FOLLOW_SHARPNESS * delta))
	ship_vel = (ship_pos - prev) / maxf(delta, 0.0001)


func _update_run(delta: float) -> void:
	phase_time += delta
	_update_pace(delta)
	var v := speed() * delta
	_fire(delta)
	_update_bullets(delta)
	if not main.space_run_live():
		return
	# Pattern steps.
	for w in waves:
		w.z += v
		for p in w.planets:
			p.z = w.z
		if not w.resolved:
			_draw_in(w)
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
		r.z += v
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
		Phase.BOSS:
			_update_boss(delta)
		Phase.FEVER:
			fever_spawn_timer -= delta
			if fever_spawn_timer <= 0.0 and phase_time < FEVER_DURATION - 1.0:
				fever_spawn_timer = FEVER_SPAWN_INTERVAL
				_spawn_fever_planets()
			if phase_time >= FEVER_DURATION:
				main._space_fever_ended()
				_after_fever()
		Phase.PATTERN:
			if steps_done >= PATTERN_LEN:
				_end_pattern()
			elif steps_spawned < PATTERN_LEN and (waves.is_empty() or (waves.back().z as float) >= SPAWN_Z + STEP_GAP):
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


func _burst(center: Vector3, pal: Array, wrong: bool, size: float, pieces: bool = true) -> void:
	var rock_mat := _planet_material(pal[1], pal[0])
	if wrong:
		rock_mat.set_shader_parameter("hit_flash", 0.6)
	for i in (int(DEBRIS_COUNT * clampf(size, 0.5, 1.5)) if pieces else 0):
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
			# A passed gate is no longer alive but is still there: it flies on
			# and its flash fades. Left out, it froze on the plane around the
			# ship, still lit.
			if p.alive or p.get("gate", false):
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
		# Drawn in, the ship shrinks and rolls one full turn into the hole; the
		# turn ends where it began, so nothing jumps when it lets go.
		ship_pivot.rotation = Vector3(pitch, 0.0, bank + squeeze * TAU)
		ship_pivot.scale = Vector3.ONE * lerpf(1.0, CAPTURE_SHIP_SCALE, squeeze)
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
		sky_scroll -= flow * 0.00015 * delta
		sky_material.set_shader_parameter("scroll", sky_scroll)
	if camera != null:
		var want: float = CAMERA_FOV + (FEVER_FOV_BOOST if phase == Phase.FEVER else 0.0) + WARP_FOV_KICK * boost
		camera.fov = lerpf(camera.fov, want, 1.0 - exp(-4.0 * delta))


func _animate(p: Dictionary, delta: float) -> void:
	var node: MeshInstance3D = p.node
	node.rotation += p.spin * delta
	if p.flash > 0.0:
		p.flash = maxf(0.0, p.flash - delta * 2.0)
		if p.get("gate", false):
			var lit: Color = p.flash_color
			(p.glow as StandardMaterial3D).albedo_color = (p.base_glow as Color).lerp(Color(lit.r * 2.5, lit.g * 2.5, lit.b * 2.5, 1.0), p.flash)
		else:
			p.mat.set_shader_parameter("hit_flash", p.flash)
	elif p.get("gate", false) and p.alive:
		(p.glow as StandardMaterial3D).albedo_color = _aim_glow(p) if p.get("aim", false) else p.base_glow
	_place(p)


## The glow of the gate the ship is about to be drawn into.
func _aim_glow(p: Dictionary) -> Color:
	var base: Color = p.base_glow
	if base == GATE_GLOW:
		return GATE_GLOW_AIM
	return Color(base.lightened(GATE_AIM_LIFT), 1.0)


## Debug builds only: arrow keys or WASD move the ship like a drag does.
func _key_steer(delta: float) -> void:
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
			- float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
			- float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)))
	if dir == Vector2.ZERO:
		return
	ship_target = (ship_target + dir.normalized() * KEY_STEER_SPEED * delta).clamp(-FIELD_HALF, FIELD_HALF)


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


## How far a planet has come, 0 at SPAWN_Z and 1 on the flight plane.
static func approach(p: Dictionary) -> float:
	return clampf((p.z - SPAWN_Z) / -SPAWN_Z, 0.0, 1.0)


## Kind.SEQUENCE's marks, one in each gate's hole. Drawn over the 3D world,
## so they know nothing of depth: a farther step's mark would show through
## a nearer gate's ring. Walked near to far, a mark is dropped where a nearer
## gate already covers that spot on screen, then the rest are drawn far
## first, so a near one lands on top.
func _draw_gate_symbols(ci: CanvasItem, font: Font) -> void:
	var covers: Array = []      # [centre, radius] of nearer gates, on screen
	var marks: Array = []
	for w in waves:
		if w.resolved:
			continue
		var pulled: Dictionary = w.get("target", {})
		var these: Array = []
		for p in w.planets:
			if not p.alive:
				continue
			var node: Node3D = p.node
			var s := project(node.position)
			if s.z <= 0.0:
				continue
			var c := Vector2(s.x, s.y)
			var r: float = s.z * p.radius * node.scale.x
			these.append([c, r * GATE_OUTER_OF_HOLE])
			if w.kind != Kind.SEQUENCE or not p.has("symbol"):
				continue
			var shown := smoothstep(SYMBOL_FADE.x, SYMBOL_FADE.y, approach(p))
			if shown <= 0.01 or covers.any(func(cv): return c.distance_to(cv[0]) < cv[1]):
				continue
			var size: float = maxf(r * 2.0 * SYMBOL_IN_HOLE, SYMBOL_MIN_PX)
			var alpha: float = shown * (LABEL_PLATE_UNDER_SHIP if is_same(p, pulled) else 1.0)
			marks.append([int(p.symbol), c, size, alpha])
		covers.append_array(these)
	for i in range(marks.size() - 1, -1, -1):
		var mk: Array = marks[i]
		ci.draw_circle(mk[1], mk[2] * 0.55, Color(SYMBOL_BACK, SYMBOL_BACK.a * mk[3]))
		_draw_symbol(ci, font, mk[0], mk[1], mk[2], Color(1, 1, 1, mk[3]))


## Symbol `i` centred on `c`, `size` px square. Without the UI kit, its
## number, so the pattern still plays.
func _draw_symbol(ci: CanvasItem, font: Font, i: int, c: Vector2, size: float, mod: Color) -> void:
	var tex := _symbol_texture(i)
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size)), false, mod)
		return
	var text := str(i + 1)
	var fs := int(maxf(10.0, size * 0.7))
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mod)


## The mark for symbol `i`, loaded once. Mipmapped here rather than in its
## .import file: the kit is rebuilt per machine and its sidecars are not
## committed, and a gate shows the 144 px mark as small as 12 px.
func _symbol_texture(i: int) -> Texture2D:
	if symbol_textures.is_empty():
		for k in SYMBOL_COUNT:
			var path := SYMBOL_PATH % k
			var tex: Texture2D = null
			if ResourceLoader.exists(path):
				var img: Image = (load(path) as Texture2D).get_image()
				if img != null:
					img.decompress()
					img.generate_mipmaps()
					tex = ImageTexture.create_from_image(img)
			symbol_textures.append(tex)
	return symbol_textures[i] if i >= 0 and i < symbol_textures.size() else null


## The answers of the next wave, each in its own gate's hole, growing as the
## gate flies in. They appear over LABEL_FADE, once the gates have spread far
## enough apart for their plates not to overlap, and never earlier — showing
## them in advance on the flight plane was tried and covered the screen.
## The plate drawn over the gate the ship is being pulled into thins out so the
## ship shows through it.
func draw_labels(ci: CanvasItem, font: Font) -> void:
	_draw_gate_symbols(ci, font)
	var w := upcoming_wave()
	if w.is_empty():
		return
	var pulled: Dictionary = w.get("target", {})
	for p in w.planets:
		if not p.alive or p.label == "":
			continue
		var shown := smoothstep(LABEL_FADE.x, LABEL_FADE.y, approach(p))
		var node: Node3D = p.node
		var s := project(node.position)
		if shown <= 0.01 or s.z <= 0.0:
			continue
		var r: float = s.z * p.radius * node.scale.x
		var alpha := shown * (LABEL_PLATE_UNDER_SHIP if is_same(p, pulled) else LABEL_PLATE_ALPHA)
		_draw_plate(ci, font, p, Vector2(s.x, s.y), r * LABEL_TEXT_SCALE, alpha)


## An answer plate centred on `c`, sized for a planet `r` px across, at `alpha`.
func _draw_plate(ci: CanvasItem, font: Font, p: Dictionary, c: Vector2, r: float, alpha: float) -> void:
	var f: Font = font
	var font_size := int(clampf(r * 0.62, LABEL_MIN_FONT, 80.0))
	var text_w: float = f.get_string_size(p.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var size := Vector2(maxf(text_w + font_size * 0.7, r * 0.95), font_size * 1.3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PLATE_FILL, alpha)
	sb.border_color = Color(PLATE_EDGE, alpha)
	sb.set_border_width_all(maxi(1, int(font_size * 0.09)))
	sb.set_corner_radius_all(int(font_size * 0.3))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, Rect2(c - size * 0.5, size))
	ci.draw_string(f, Vector2(c.x - text_w * 0.5, c.y + font_size * 0.36), p.label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(PLATE_TEXT, minf(1.0, alpha * 1.6)))


## Inside the question box, the pattern's rule — a colour swatch, or the
## front step's arrow; under it, the pattern's progress, the boss's health
## or fever's time; beside it, the run's stardust; and the weapon, bottom
## right. `box` is the question box, `side` the slot to its right — both
## laid out by Main (_quiz_box_rect, _stardust_rect).
func draw_hud(ci: CanvasItem, box: Rect2, side: Rect2) -> void:
	var font: Font = main.combo_font if main.combo_font != null else ThemeDB.fallback_font
	var w := upcoming_wave()
	var c := box.get_center()
	if phase == Phase.PATTERN:
		if pattern_kind == Kind.COLOR:
			_draw_swatch(ci, c, box.size.y * 0.3, GATE_COLORS[pattern_color])
		elif pattern_kind == Kind.SEQUENCE:
			_draw_sequence(ci, font, box)
		elif not w.is_empty():
			_draw_arrow(ci, c, box.size.y * 0.34, int(w.dir), ARROW_REVERSE if w.reverse else ARROW_NORMAL)
	var rect := gauge_rect(box)
	main._draw_horizontal_slice(ArtSlot.texture(HUD_GAUGE_PATH), rect, HUD_GAUGE_CAP, ci)
	var inner := rect.grow_individual(-HUD_GAUGE_INSET.x, -HUD_GAUGE_INSET.y, -HUD_GAUGE_INSET.x, -HUD_GAUGE_INSET.y)
	var gh: float = inner.size.y
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
			frac = float(steps_done) / float(PATTERN_LEN)
			if pattern_perfect():
				col = GAUGE_PERFECT_COLOR
	if frac > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(int(gh * 0.5))
		fill.anti_aliasing = true
		ci.draw_style_box(fill, Rect2(inner.position, Vector2(inner.size.x * frac, gh)))
	# The slot beside the box holds the stardust won this run, the icon over
	# the count.
	var slot_tex := ArtSlot.texture(main.HUD_SIDE_SLOT_PATH)
	main._draw_nine_patch(slot_tex, side, main.HUD_SIDE_SLOT_MARGIN, side.size.y / slot_tex.get_height(), ci)
	_draw_stardust(ci, font, side, int(main.run_stardust))
	var wname: String = ["BLASTER", "SPREAD", "LASER"][weapon]
	var txt := "%s  Lv%d%s" % [wname, level, ("  +%d DRONE" % drones) if drones > 0 else ""]
	# Bottom right (2026-11-26; the health gauge took the top-left side).
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var pos := Vector2(view_size.x - 14.0 - tw, view_size.y - 18.0)
	var back_w: float = tw + 46.0
	ci.draw_texture_rect(ArtSlot.texture(HUD_WEAPON_BACK_PATH),
		Rect2(Vector2(view_size.x - 6.0 - back_w, view_size.y - 44.0), Vector2(back_w, 34.0)), false)
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		ci.draw_string(font, pos + o, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.05, 0.04, 0.12))
	ci.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.86, 0.3))


## The stardust slot: the kit's icon in the upper half, the count under it.
func _draw_stardust(ci: CanvasItem, font: Font, rect: Rect2, amount: int) -> void:
	var icon := ArtSlot.texture(HUD_STARDUST_ICON_PATH)
	var ih: float = rect.size.y * 0.36
	var iw: float = ih * icon.get_width() / maxf(1.0, icon.get_height())
	ci.draw_texture_rect(icon, Rect2(Vector2(rect.get_center().x - iw * 0.5, rect.position.y + rect.size.y * 0.16), Vector2(iw, ih)), false)
	var text := ScoreFormat.compact(amount)
	var fs := int(rect.size.y * 0.24)
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > rect.size.x * 0.8:
		fs = int(fs * rect.size.x * 0.8 / tw)
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(rect.get_center().x - tw * 0.5, rect.position.y + rect.size.y * 0.8)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 6), Color(0.05, 0.04, 0.12))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, STARDUST_COLOR)


## Kind.SEQUENCE's rule: the pattern's symbols in a row across the box, the
## one to fly through next at full strength in a gold ring, the rest dimmed.
## The next is the front step's, so it moves on as each step is judged and
## comes round to the first again.
func _draw_sequence(ci: CanvasItem, font: Font, box: Rect2) -> void:
	if pattern_seq.is_empty():
		return
	var n: int = pattern_seq.size()
	var size: float = box.size.y * 0.5
	var gap: float = size * 0.45
	var x0: float = box.get_center().x - (n * size + (n - 1) * gap) * 0.5 + size * 0.5
	var now: int = steps_done % n
	for i in n:
		var c := Vector2(x0 + i * (size + gap), box.get_center().y)
		if i == now:
			ci.draw_arc(c, size * 0.62, 0.0, TAU, 32, SEQ_NOW_RING, 2.5, true)
		_draw_symbol(ci, font, int(pattern_seq[i]), c, size, Color(1, 1, 1, 1.0 if i == now else SEQ_DIM))


## Kind.COLOR's rule: a round swatch of the colour to fly through, ringed so
## it holds on any background.
func _draw_swatch(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(c, r + 3.0, Color(0.05, 0.04, 0.12))
	ci.draw_circle(c, r, color)
	ci.draw_circle(c + Vector2(-r, -r) * 0.3, r * 0.28, Color(1, 1, 1, 0.35))


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


# ================================================================ tutorial rects
# Read from the same numbers the drawing uses, so the tutorial's highlights
# follow the HUD and the ship wherever they move.

## The ship on screen, a square around its projected centre.
func ship_screen_rect() -> Rect2:
	var s := project(Vector3(ship_pos.x, ship_pos.y, 0.0))
	var half: float = maxf(s.z * SHIP_WIDTH * 0.55, 20.0)
	return Rect2(Vector2(s.x, s.y) - Vector2(half, half * 0.7), Vector2(half * 2.0, half * 1.4))


## The progress gauge under the question box (draw_hud draws it here).
func gauge_rect(box: Rect2) -> Rect2:
	var gw: float = box.size.x * 0.9
	return Rect2(Vector2(box.get_center().x - gw * 0.5, box.end.y + 6.0), Vector2(gw, 16.0))


## The weapon readout, bottom right (draw_hud writes it here).
func weapon_label_rect() -> Rect2:
	return Rect2(Vector2(view_size.x - 238.0, view_size.y - 40.0), Vector2(230.0, 30.0))
