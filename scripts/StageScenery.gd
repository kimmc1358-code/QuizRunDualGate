extends RefCounted

## The stage backgrounds (2026-11-28, owner): places the run can be in besides
## open space, built from the stage kit (tools/build_stage_kit.gd, gitignored)
## around the gate field and scrolled past it with the world. They are the
## candidates the owner kept for warping between in QUIZ RUN and for BATTLE's
## stages; for now only the debug switch (Main.debug_stage, and B in a debug
## build) picks one. Nothing here touches the run's rules.
##
## Each stage is built as segments along z (seg_len metres each), under one
## root. They move with the world (scroll) and the one that has passed the
## camera goes back to the far end, so a few hundred metres of scenery loop.
## A stage that needs the kit falls back to plain space without it.

const KIT := "res://assets/stage_kit/"

enum Stage { SPACE, SKY_02, SKY_03, SKY_04, HALL, TRENCH, CITY }
const NAMES := ["SPACE", "SKY 02", "SKY 03", "SKY 04", "SHIP HALL", "TRENCH", "CYBER STREET"]

const SEG := 40.0              # m along z a city segment covers
const LOOP := 360.0            # m of scenery: past the far fog, short of the camera's far plane
const FRONT_Z := 40.0          # the first segment's near edge
const BEHIND_Z := 14.0         # a segment wholly behind this (the camera sits at 10) goes round

# Space stages: the other skyboxes' front faces, each with its own tint.
const SKIES := {
	Stage.SKY_02: ["space/sky_02.png", Color(1.35, 1.25, 1.45)],
	Stage.SKY_03: ["space/sky_03.png", Color(1.15, 1.3, 1.25)],
	Stage.SKY_04: ["space/sky_04.png", Color(1.25, 1.25, 1.25)],
}

# The ship's hall and the trench: 5 m interior pieces at 3.4x, floor at -7.
const HALL_SCALE := 3.4
const HALL_FLOOR := -7.0
const HALL_TILE := 5.0 * HALL_SCALE

# The city: metres as they come, the street's floor well below the field.
const CITY_STREET_Y := -20.0
const CITY_HALF := 12.8        # street axis to the towers' faces
const FRONT_TALL_CHANCE := 0.3   # of a front-row tower being a tall one

var sp                          # the SpaceRun
var root: Node3D
var world: Node3D                 # the scenery that moves with the run (root also holds the sky)
var segs: Array[Node3D] = []
var seg_len := SEG             # the hall's are two of its tiles, so the tiles meet
var stage: int = Stage.SPACE
var rng := RandomNumberGenerator.new()
var _mesh_cache := {}
var _mats := {}
# The city's sky (_city_sky): things that move on their own, not with the world.
var _beams: Array = []          # [node, base tilt, phase, roof position]
var _stars: MultiMesh
var _star_phase := PackedFloat32Array()
var _t := 0.0
var _fever_targets: Array = []  # fever_targets(), built once


func _init(space_run) -> void:
	sp = space_run


static func kit_ready() -> bool:
	return ResourceLoader.exists(KIT + "space/SM_Bld_Floor_01.res") and ResourceLoader.exists(KIT + "city/atlas.png")


## Builds `id` (clamped), replacing whatever was there. Returns the stage
## actually built: SPACE when the kit is missing.
func apply(id: int) -> int:
	clear()
	stage = clampi(id, 0, NAMES.size() - 1)
	if stage != Stage.SPACE and not kit_ready():
		push_warning("StageScenery: no stage kit (tools/build_stage_kit.gd); playing SPACE")
		stage = Stage.SPACE
	_environment()
	if stage == Stage.SPACE or SKIES.has(stage):
		return stage
	seg_len = HALL_TILE * 2.0 if stage == Stage.HALL or stage == Stage.TRENCH else SEG
	root = Node3D.new()
	sp.root3d.add_child(root)
	world = Node3D.new()
	root.add_child(world)
	if stage == Stage.CITY:
		_city_sky()
	for i in int(ceil(LOOP / seg_len)):
		var seg := Node3D.new()
		seg.position.z = FRONT_Z - i * seg_len
		world.add_child(seg)
		segs.append(seg)
		rng.seed = 1000 * stage + i
		match stage:
			Stage.HALL:
				_hall_segment(seg, 2, true)
			Stage.TRENCH:
				_hall_segment(seg, 3, false)
			Stage.CITY:
				_city_segment(seg)
	return stage


func clear() -> void:
	_beams.clear()
	_stars = null
	if root != null:
		root.queue_free()
	root = null
	world = null
	segs.clear()
	turn_state = Turn.NONE
	_turn_extra.clear()
	_leftovers.clear()
	_cross = null


## Moves the scenery `dz` metres toward the camera, with the world. Held
## while the city turns a corner: the turn itself carries the ship on.
func scroll(dz: float) -> void:
	if turn_state == Turn.TURNING:
		return
	for seg in segs:
		seg.position.z += dz
		# While a turn is coming the street ends at the junction, so nothing
		# goes round to the far end.
		if turn_state == Turn.NONE and seg.position.z - seg_len > BEHIND_Z:
			seg.position.z -= segs.size() * seg_len
			if seg.has_meta("partial"):
				_rebuild_city(seg, {})
	for n in _turn_extra:
		n.position.z += dz
	for n in _leftovers.duplicate():
		n.position.z += dz
		if n.position.z > LEFTOVER_FREE_Z:
			n.queue_free()
			_leftovers.erase(n)
	if turn_state == Turn.APPROACH and _cross.position.z >= -TURN_RADIUS:
		_start_turning()


## The sky's own motion, every frame: the searchlights sway, the stars
## twinkle.
func animate(delta: float) -> void:
	_t += delta
	if turn_state == Turn.TURNING:
		_update_turn(delta)
	for b in _beams:
		var sway: float = sin(_t * BEAM_SWAY_HZ * TAU + float(b[2])) * BEAM_SWAY
		(b[0] as Node3D).basis = Basis(Vector3.FORWARD, sway) * (b[1] as Basis)
		(b[0] as Node3D).position = (b[3] as Vector3) + (b[0] as Node3D).basis * Vector3(0, BEAM_LENGTH * 0.5, 0)
	if _stars != null:
		for i in _stars.instance_count:
			var a: float = 0.55 + 0.45 * sin(_t * 2.2 + _star_phase[i])
			var c: Color = _stars.get_instance_color(i)
			_stars.set_instance_color(i, Color(c, a))


# ---------------------------------------------------------------- look

func _environment() -> void:
	var env: Environment = sp.world_env
	var sky_on := true
	var streaks_on := true
	env.fog_enabled = false
	env.ambient_light_color = Color(0.55, 0.5, 0.75)
	env.ambient_light_energy = 0.6
	sp.env_glow = sp.ENV_GLOW
	if ResourceLoader.exists(sp.SKY_PATH):
		sp.sky_material.set_shader_parameter("sky", load(sp.SKY_PATH))
	sp.sky_tint = sp.SKY_TINT
	match stage:
		Stage.SKY_02, Stage.SKY_03, Stage.SKY_04:
			sp.sky_material.set_shader_parameter("sky", load(KIT + SKIES[stage][0]))
			sp.sky_tint = SKIES[stage][1]
		Stage.HALL, Stage.TRENCH:
			sky_on = stage == Stage.TRENCH
			streaks_on = false
			env.ambient_light_energy = 0.25 if stage == Stage.HALL else 0.4
			env.fog_enabled = stage == Stage.HALL
			env.fog_light_color = Color(0.05, 0.08, 0.18)
			env.fog_density = 0.012
			sp.env_glow = 1.0
		Stage.CITY:
			# A dark purple night with the neon carrying the light (2026-11-28,
			# owner). Between, after the pack's promotional shot, it was a bright
			# purple-pink night under light haze, and too bright; at first it was
			# near-black under dense magenta fog with the towers black too.
			streaks_on = false
			# Purple against teal (2026-11-28, owner): with purple light, fog, sky and
			# pink windows the street was one colour. The windows went teal
			# (two of three) and the fog bluer; navy, and teal with orange, were
			# compared. Teal light washed up the facades did not show: the mobile
			# renderer lights a mesh from only a few lights.
			env.ambient_light_color = Color(0.5, 0.42, 0.95)
			env.ambient_light_energy = 0.4
			env.fog_enabled = true
			env.fog_light_color = Color(0.12, 0.08, 0.28)
			env.fog_density = 0.008
			sp.sky_tint = Color(1.1, 0.55, 1.35)
			sp.env_glow = 1.3
	if sp.sky_node != null:
		sp.sky_node.visible = sky_on
	if sp.streaks != null:
		sp.streaks.visible = streaks_on


func _mesh(rel: String) -> Mesh:
	if not _mesh_cache.has(rel):
		_mesh_cache[rel] = load(KIT + rel + ".res") if ResourceLoader.exists(KIT + rel + ".res") else null
	return _mesh_cache[rel]


func _tex(rel: String) -> Texture2D:
	return load(KIT + rel)


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"hall":
			m.albedo_texture = _tex("space/atlas.png")
			m.albedo_color = Color(0.42, 0.45, 0.55)
			m.emission_enabled = true
			m.emission_texture = _tex("space/emissive.png")
			m.emission_energy_multiplier = 3.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"atlas", "walk":
			m.albedo_texture = _tex("city/atlas.png")
			# Dark walls, so their own lit strips and the signs carry the light.
			m.albedo_color = Color(0.45, 0.45, 0.56)
			m.emission_enabled = true
			m.emission_texture = _tex("city/emissive.png")
			m.emission_energy_multiplier = 3.0
			if key == "walk":
				m.roughness = 0.2
		"road":
			m.albedo_texture = _tex("city/road.png")
			m.albedo_color = Color(0.28, 0.28, 0.36)
			m.roughness = 0.12
			m.metallic = 0.35
		"win0", "win1", "win2":
			m.albedo_color = Color(0.03, 0.02, 0.05)
			m.emission_enabled = true
			m.emission = [Color(1.0, 0.45, 0.85), Color(0.45, 0.95, 1.0), Color(0.45, 0.95, 1.0)][int(key.right(1))]
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission_texture = _tex("city/windows.png")
			m.emission_energy_multiplier = 2.2
		"neon", "signs", "billboards":
			var t := _tex("city/%s.png" % key)
			m.albedo_texture = t
			m.emission_enabled = true
			m.emission_texture = t
			m.emission_energy_multiplier = {"neon": 5.0, "signs": 2.8, "billboards": 2.4}[key]
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _put(parent: Node3D, mesh: Mesh, xf: Transform3D, m: Material) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.transform = xf
	parent.add_child(mi)


func _light(parent: Node3D, at: Vector3, c: Color, energy: float, rng_range: float) -> void:
	var o := OmniLight3D.new()
	o.light_color = c
	o.light_energy = energy
	o.omni_range = rng_range
	o.position = at
	parent.add_child(o)


# ---------------------------------------------------------------- hall, trench

## One segment of the ship's hall (`roof`) or the open trench: tiles of floor,
## walls stacked `storeys` high with a pillar on every seam, and a light per
## tile, blue and orange by turns. The corridor arches are a storey tall and
## read as a low beam under a raised ceiling, so there are none.
func _hall_segment(seg: Node3D, storeys: int, roof: bool) -> void:
	var hall := Node3D.new()
	hall.scale = Vector3.ONE * HALL_SCALE
	hall.position.y = HALL_FLOOR
	seg.add_child(hall)
	var m := _mat("hall")
	var walls := ["space/SM_Bld_Wall_01", "space/SM_Bld_Wall_04", "space/SM_Bld_Wall_Mechanical_01", "space/SM_Bld_Wall_02", "space/SM_Bld_Wall_05"]
	for i in 2:
		var z: float = -i * 5.0      # in the hall's own units, from the segment's front
		_put(hall, _mesh("space/SM_Bld_Floor_01"), Transform3D(Basis(), Vector3(-2.5, 0, z - 5.0)), m)
		for k in storeys:
			var y: float = 5.0 * k
			var w := _mesh(walls[rng.randi() % walls.size()])
			_put(hall, w, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-2.5, y, z)), m)
			_put(hall, w, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(2.5, y, z - 5.0)), m)
			_put(hall, _mesh("space/SM_Bld_Wall_Pillar_03"), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-2.4, y, z)), m)
			_put(hall, _mesh("space/SM_Bld_Wall_Pillar_03"), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(2.4, y, z)), m)
		if roof:
			_put(hall, _mesh("space/SM_Bld_Ceiling_01"), Transform3D(Basis(), Vector3(-2.5, 5.0 * storeys - 5.0, z - 5.0)), m)
			_put(hall, _mesh("space/SM_Prop_Light_Panel_01"), Transform3D(Basis(), Vector3(0, 5.0 * storeys - 1.1, z - 2.5)), m)
		_light(seg, Vector3(0, 3.0, (z - 2.5) * HALL_SCALE), Color(0.45, 0.75, 1.0) if i % 2 == 0 else Color(1.0, 0.55, 0.25), 2.4, 10.0 * HALL_SCALE * 0.3)


# ---------------------------------------------------------------- city

## One segment of the cyberpunk street: two rows of towers with neon and
## billboards on the faces toward the street, and below, a wet road under
## magenta and cyan light with streetlights along both kerbs. Its first
## version had hover cars on the road and in lanes high above, and two other
## city places were tried and dropped (2026-11-28, owner): one with no street,
## the towers falling into haze over rivers of traffic light with holograms
## in the gap, and a night market of stalls and lantern strings.
##
## `opt` shapes the pieces of a corner (begin_turn): "sides" the sides that get
## towers and signs (both), "length" how far it runs (SEG), "road" whether it
## has the street (true), "from" per side the segment-local z a side's towers
## and signs start at (0), to leave a corner or a junction open.
func _city_segment(seg: Node3D, opt: Dictionary = {}) -> void:
	var city := Node3D.new()
	city.position.y = CITY_STREET_Y
	seg.add_child(city)
	_towers(city, opt)
	_signs(city, 4.0, 34.0, opt)
	if opt.get("road", true):
		_street(city, float(opt.get("length", SEG)))


## Builds a city segment again from its own seed: one left partial at a
## corner, once it comes round as an ordinary piece of street.
func _rebuild_city(seg: Node3D, opt: Dictionary) -> void:
	seg.remove_meta("partial")
	for c in seg.get_children():
		c.queue_free()
	rng.seed = int(seg.get_meta("seed", 0))
	_city_segment(seg, opt)


func _towers(city: Node3D, opt: Dictionary) -> void:
	var length: float = float(opt.get("length", SEG))
	var from: Dictionary = opt.get("from", {})
	# The colourful towers in front, at full colour; the dark window-lit ones
	# only behind, larger, as the skyline. (Both were mixed in front at first,
	# and the street read as a black canyon.)
	var front := ["SM_Bld_Large_01", "SM_Bld_Large_02", "SM_Bld_Large_03", "SM_Bld_Large_04", "SM_Bld_Large_06"]
	var back := ["SM_Bld_Background_Lrg_01", "SM_Bld_Background_Lrg_02", "SM_Bld_Background_Lrg_03", "SM_Bld_Background_Med_09"]
	# Now and then a tall one breaks into the front row (2026-11-28, owner):
	# low towers all along it read as the same few repeated. Never two running.
	var tall := [["SM_Bld_Background_Lrg_02", 1.25], ["SM_Bld_Background_Lrg_03", 1.25], ["SM_Bld_Large_06", 1.7], ["SM_Bld_Large_01", 1.7]]
	for side: float in opt.get("sides", [-1.0, 1.0]):
		for row in 2:
			var names: Array = front if row == 0 else back
			var z: float = minf(0.0, float(from.get(side, 0.0)))
			var last_tall := false
			while z > -length:
				var n: String = names[rng.randi() % names.size()]
				var up: float = 1.0 if row == 0 else 2.0
				if row == 0 and not last_tall and rng.randf() < FRONT_TALL_CHANCE:
					var t: Array = tall[rng.randi() % tall.size()]
					n = t[0]
					up = t[1]
					last_tall = true
				else:
					last_tall = false
				var mesh := _mesh("city/" + n)
				var b: AABB = mesh.get_aabb()
				var turn: bool = b.size.x > b.size.z
				var depth: float = (b.size.x if turn else b.size.z) * up
				var across: float = (b.size.z if turn else b.size.x) * up
				var basis := Basis(Vector3.UP, PI * 0.5 * side) if turn else Basis(Vector3.UP, PI if side > 0 else 0.0)
				var c := b.get_center()
				var lc: Vector3 = (basis * Vector3(c.x, 0, c.z)) * up
				var at := Vector3(side * (CITY_HALF + row * 16.0 + across * 0.5), 0, z - depth * 0.5)
				if z - depth < -length:
					break   # it would run into the next segment: leave an alley
				var m: Material = _mat("atlas") if n.begins_with("SM_Bld_Large") else _mat("win%d" % (rng.randi() % 3))
				_put(city, mesh, Transform3D(basis.scaled(Vector3.ONE * up), at - lc), m)
				z -= depth + rng.randf_range(0.5, 2.0)


func _signs(city: Node3D, lo: float, hi: float, opt: Dictionary) -> void:
	var length: float = float(opt.get("length", SEG))
	var from: Dictionary = opt.get("from", {})
	for side: float in opt.get("sides", [-1.0, 1.0]):
		var z: float = minf(0.0, float(from.get(side, 0.0))) - rng.randf_range(0.0, 3.0)
		while z > -length:
			var r := rng.randi() % 34
			var mesh: Mesh
			var m: Material
			var s: float
			if r < 9:
				mesh = _mesh("city/SM_Sign_Neon_%02d" % (r + 1))
				m = _mat("neon")
				s = 3.5
			elif r < 31:
				mesh = _mesh("city/SM_Sign_Ad_%02d" % (r - 8))
				m = _mat("signs")
				s = 5.0
			else:
				mesh = _mesh("city/SM_Sign_Billboard_Large_%02d" % (r - 30))
				m = _mat("billboards")
				s = 2.2
			var face := Basis(Vector3.UP, -PI * 0.5 * side).scaled(Vector3.ONE * s * rng.randf_range(0.8, 1.3))
			_put(city, mesh, Transform3D(face, Vector3(side * (CITY_HALF - 0.4), rng.randf_range(lo, hi), z)), m)
			z -= rng.randf_range(3.0, 7.0)


func _street(city: Node3D, length: float) -> void:
	for i in int(length / 5.0):
		var z: float = -i * 5.0
		for k in range(-1, 2):
			_put(city, _mesh("city/SM_Env_Road_Lines_01_SF"), Transform3D(Basis(), Vector3(-2.5 + k * 5.0, 0, z)), _mat("road"))
		_put(city, _mesh("city/SM_Env_Sidewalk_Straight_01_SF"), Transform3D(Basis(), Vector3(-12.5, 0, z)), _mat("walk"))
		_put(city, _mesh("city/SM_Env_Sidewalk_Straight_01_SF"), Transform3D(Basis(), Vector3(7.5, 0, z)), _mat("walk"))
		if i % 3 == 0:
			for side in [-1.0, 1.0]:
				_put(city, _mesh("city/SM_Prop_Streetlight_01"), Transform3D(Basis(Vector3.UP, PI * 0.5 * side).scaled(Vector3.ONE * 1.6), Vector3(side * 8.0, 0, z)), _mat("atlas"))
			_light(city, Vector3(-6.0 if i % 2 == 0 else 6.0, 4.0, z), Color(1.0, 0.2, 0.8) if i % 2 == 0 else Color(0.2, 0.9, 1.0), 3.0, 16.0)



# ---------------------------------------------------------------- city sky

# The sky shows only in the gap between the towers, low down and mostly under
# the HUD, so a different picture there hardly told (2026-11-28); what reads
# are things placed in the gap. The owner chose, from four tried in the game:
# a ringed giant planet in the middle of it and searchlights crossing it;
# and asked for a few small stars. (A brighter nebula hardly showed; clouds
# read as pink lumps; cruisers drifting across in front flew through the
# towers and were taken out.)
const PLANET_AT := Vector3(6.0, 72.0, -430.0)
const PLANET_RADIUS := 45.0
const RING_SPAN := 2.6          # of the planet's radius, edge to edge / 2
const BEAM_LENGTH := 160.0
const BEAM_SWAY := 0.12         # radians either way
const BEAM_SWAY_HZ := 0.07
const STAR_COUNT := 90

func _city_sky() -> void:
	var sky := Node3D.new()
	root.add_child(sky)
	# The planet, in the game's own planet shader, with the pack's ring.
	var pm: Dictionary = sp.planet_meshes[0]
	var pmat: Material = sp._planet_material(Color(0.55, 0.2, 0.75), Color(0.95, 0.45, 0.7))
	_put(sky, pm.mesh, Transform3D(Basis().scaled(Vector3.ONE * pm.scale * PLANET_RADIUS), PLANET_AT), pmat)
	var ring := _mesh("space/SM_Env_PlanetRings_01")
	if ring != null:
		var rs: float = PLANET_RADIUS * RING_SPAN / maxf(ring.get_aabb().size.x, 0.01)
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		rm.albedo_color = Color(1.0, 0.7, 1.0, 0.55)
		rm.disable_fog = true
		_put(sky, ring, Transform3D(Basis(Vector3.RIGHT, 0.35).rotated(Vector3.FORWARD, 0.25).scaled(Vector3.ONE * rs), PLANET_AT), rm)
	# Searchlights from roofs far ahead, crossing the gap, swaying slowly.
	var cone := CylinderMesh.new()
	cone.top_radius = 7.0
	cone.bottom_radius = 0.6
	cone.height = BEAM_LENGTH
	cone.cap_top = false
	cone.cap_bottom = false
	for i in 6:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true
		m.albedo_color = Color(0.4, 0.85, 1.0, 0.09) if i % 3 != 2 else Color(1.0, 0.45, 0.9, 0.09)
		var tilt := Basis(Vector3.FORWARD, -side * (0.25 + 0.12 * (i % 3))) * Basis(Vector3.RIGHT, -0.25)
		var base := Vector3(side * 26.0, 20.0, -60.0 - i * 45.0)
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = m
		sky.add_child(mi)
		_beams.append([mi, tilt, i * 1.7, base])
	# Small stars in the gap, behind the planet, twinkling.
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	# Round and soft: as plain quads they read as square flecks, like snow.
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.6))
	dot.gradient = g
	sm.albedo_texture = dot
	sm.disable_fog = true
	_stars = MultiMesh.new()
	_stars.transform_format = MultiMesh.TRANSFORM_3D
	_stars.use_colors = true
	_stars.mesh = q
	_stars.instance_count = STAR_COUNT
	_star_phase.resize(STAR_COUNT)
	for i in STAR_COUNT:
		# In front of the backdrop (a quad 420 m out along the camera's line,
		# so about 430 m deep here) and kept off the planet's disc.
		var at := Vector3(rng.randf_range(-80.0, 80.0), rng.randf_range(30.0, 150.0), rng.randf_range(-400.0, -370.0))
		while Vector2(at.x - PLANET_AT.x, at.y - PLANET_AT.y).length() < PLANET_RADIUS * 1.15:
			at.x = rng.randf_range(-80.0, 80.0)
		_stars.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(1.2, 2.4)), at))
		# Sized for 400 m off, where a metre is about a pixel; the soft edge
		# leaves a smaller dot. Over 1 so they glow a little.
		_stars.set_instance_color(i, Color(1.6, 1.35, 1.6) if rng.randf() < 0.7 else Color(1.1, 1.4, 1.7))
		_star_phase[i] = rng.randf() * TAU
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = _stars
	smi.material_override = sm
	sky.add_child(smi)
	animate(0.0)


# ---------------------------------------------------------------- fever

## What FEVER smashes on this stage, in place of planets: in the city, the
## holographic food signs, noodles, burgers, pizza and bottles, each with its
## glowing outline, in pink or teal, turning like a shop display (2026-11-28,
## owner). Hover cars came first, and read as wreckage hanging at odd angles,
## and smashing taxis sat oddly; security drones next, and the owner chose
## the holograms over them. Each entry is {mesh, scale, palette, spin}: the
## sign centred on its middle, so it scales and turns about it as a planet
## does; `scale` brings its longest side to 2 (a planet's mesh is scaled to a
## diameter of 2); `palette` colours its burst; `seeded` gives each its own
## flicker beat; `burst` "neon" breaks it into light (SpaceRun._neon_burst)
## rather than rock. Empty on every other stage.
const FEVER_HOLOGRAMS := [
	["SM_Prop_Hologram_Noodles_01", "SM_Prop_LargeSign_Noodles_01_Outline"],
	["SM_Prop_Hologram_Burger_03", "SM_Prop_LargeSign_Burger_03_Outline"],
	["SM_Prop_Hologram_Pizza_01", "SM_Prop_LargeSign_Pizza_01_Outline"],
	["SM_Prop_Hologram_Bottle_01", ""], ["SM_Prop_Hologram_Bottle_02", ""], ["SM_Prop_Hologram_Bottle_03", ""],
]
const HOLO_TINTS := [   # [the sign's tint, its outline, its burst's two colours]
	[Color(1.0, 0.4, 0.95, 0.8), Color(1.0, 0.4, 0.9, 0.7), [Color(0.55, 0.1, 0.5), Color(1.0, 0.45, 0.9)]],
	[Color(0.35, 0.95, 1.0, 0.8), Color(0.35, 0.95, 1.0, 0.7), [Color(0.05, 0.4, 0.6), Color(0.45, 0.95, 1.0)]],
]
const HOLO_SPIN := 0.9          # rad/s about its upright, like a shop display
const HOLO_SHADER := "res://assets/shaders/hologram.gdshader"

func fever_targets() -> Array:
	if stage != Stage.CITY:
		return []
	if not _fever_targets.is_empty():
		return _fever_targets
	for tint: Array in HOLO_TINTS:
		# Scanlines, an edge glow, flicker and glitch (assets/shaders/
		# hologram.gdshader); its own colours half greyed and pushed toward the
		# tint, so a brown bottle reads as light rather than as a bottle.
		var sign_m := ShaderMaterial.new()
		sign_m.shader = load(HOLO_SHADER)
		sign_m.set_shader_parameter("albedo_tex", _tex("city/atlas.png"))
		sign_m.set_shader_parameter("tint", tint[0])
		var rim_m := StandardMaterial3D.new()
		rim_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rim_m.albedo_color = tint[1]
		rim_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rim_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rim_m.cull_mode = BaseMaterial3D.CULL_DISABLED
		for h: Array in FEVER_HOLOGRAMS:
			var src := _mesh("city/" + h[0])
			if src == null:
				continue
			var box := src.get_aabb()
			var at := Transform3D(Basis(), -box.get_center())
			var mesh := ArrayMesh.new()
			_append(mesh, src, at, sign_m)
			var rim := _mesh("city/" + h[1]) if h[1] != "" else null
			if rim != null:
				_append(mesh, rim, at, rim_m)
			var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
			_fever_targets.append({"mesh": mesh, "scale": 2.0 / maxf(longest, 0.01), "palette": tint[2],
				"spin": HOLO_SPIN, "seeded": true, "burst": "neon"})
	return _fever_targets


## Every surface of `src`, moved by `xf`, added to `into` in material `m`.
func _append(into: ArrayMesh, src: Mesh, xf: Transform3D, m: Material) -> void:
	for s in src.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(src, s, xf)
		st.commit(into)
		into.surface_set_material(into.get_surface_count() - 1, m)


# ---------------------------------------------------------------- the turn

# In the city, after a pattern's fever and before the next pattern, the run
# turns a corner (2026-11-28, owner: to show flying between the towers and
# swinging 90 degrees round a corner, then straight on to the next quiz).
# begin_turn ends the street at a junction a little ahead: past it a cross
# street opens on the turn side and a wall of towers closes it ahead, a short
# run of towers closes the other side, and the street's own turn-side rows
# stop one segment short so the cross street's row lines that corner. When the
# junction reaches the ship the scenery stops scrolling and swings about a
# point TURN_RADIUS to the turn side, so the ship is carried round a quarter
# circle onto the cross street, the camera banking into it. Then the cross
# street's segments become the loop, and what is left of the old street flies
# off behind. The sky is the stage's and does not turn.
const TURN_RADIUS := 20.0         # m, the quarter circle round the corner
const TURN_LEAD := 110.0          # m ahead the junction is set, at least
const TURN_TIME_MIN := 1.0        # s: at fever speed the arc took 0.6 s, too quick to be seen
const TURN_TIME_MAX := 1.6
const TURN_BANK := 0.3            # rad the camera rolls into the turn, at its height
const LEFTOVER_FREE_Z := 160.0    # the old street is let go once this far behind

enum Turn { NONE, APPROACH, TURNING }
var turn_state := Turn.NONE
var _turn_dir := -1.0             # -1 left, +1 right
var _turn_u := 0.0
var _turn_time := 1.0
var _turn_count := 0
var _pivot := Vector3.ZERO
var _cross: Node3D                # the cross street, its segments turned a quarter
var _turn_extra: Array[Node3D] = []   # scrolled with the street until the turn is done
var _leftovers: Array[Node3D] = []    # the old street, after the turn


## Sets a corner up ahead, turning `dir` (-1 left, +1 right). False where the
## stage has no corners (anything but the city) or one is already under way.
func begin_turn(dir: float) -> bool:
	if stage != Stage.CITY or turn_state != Turn.NONE or world == null:
		return false
	_turn_dir = signf(dir) if dir != 0.0 else -1.0
	_turn_count += 1
	# The junction's near edge goes on a segment's back edge, far enough ahead
	# to be seen coming.
	var keep: Node3D = null
	for seg in segs:
		if seg.position.z - seg_len <= -TURN_LEAD and (keep == null or seg.position.z > keep.position.z):
			keep = seg
	if keep == null:
		return false
	var edge: float = keep.position.z - seg_len
	for seg in segs.duplicate():
		if seg.position.z <= edge + 0.01:
			seg.queue_free()
			segs.erase(seg)
	# The last piece before it keeps only the far side: the cross street's row
	# lines the corner on the turn side.
	keep.set_meta("partial", true)
	keep.set_meta("seed", 3000 + _turn_count)
	_rebuild_city(keep, {"from": {_turn_dir: -SEG - 1.0}})
	keep.set_meta("partial", true)
	# The far side runs on across the junction, closing the T.
	var close := Node3D.new()
	close.position.z = edge
	world.add_child(close)
	rng.seed = 3500 + _turn_count
	_city_segment(close, {"sides": [-_turn_dir], "length": CITY_HALF * 2.0, "road": false})
	_turn_extra.append(close)
	# The cross street, from the junction's far side out on the turn side.
	# Its near-side row starts past the junction, which is the ship's way in.
	_cross = Node3D.new()
	_cross.position = Vector3(0.0, 0.0, edge - CITY_HALF)
	_cross.basis = Basis(Vector3.UP, -_turn_dir * PI * 0.5)
	world.add_child(_cross)
	_turn_extra.append(_cross)
	for i in int(ceil(LOOP / SEG)):
		var seg := Node3D.new()
		seg.position.z = CITY_HALF - i * SEG
		_cross.add_child(seg)
		var sd := 4000 + _turn_count * 50 + i
		rng.seed = sd
		seg.set_meta("seed", sd)
		if i == 0:
			_city_segment(seg, {"from": {_turn_dir: -CITY_HALF * 2.0}})
			seg.set_meta("partial", true)
		else:
			_city_segment(seg)
	turn_state = Turn.APPROACH
	return true


func turn_finished() -> bool:
	return turn_state == Turn.NONE


## How far the camera rolls now: into the turn, most at its middle.
func bank() -> float:
	if turn_state != Turn.TURNING:
		return 0.0
	return -_turn_dir * sin(PI * clampf(_turn_u, 0.0, 1.0)) * TURN_BANK


func _start_turning() -> void:
	turn_state = Turn.TURNING
	_turn_u = 0.0
	# A quarter circle at about the speed the run was flying.
	_turn_time = clampf(PI * 0.5 * TURN_RADIUS / maxf(sp.speed(), 1.0), TURN_TIME_MIN, TURN_TIME_MAX)
	_pivot = Vector3(_turn_dir * TURN_RADIUS, 0.0, _cross.position.z + TURN_RADIUS)


func _update_turn(delta: float) -> void:
	_turn_u = minf(1.0, _turn_u + delta / _turn_time)
	var e: float = _turn_u * _turn_u * (3.0 - 2.0 * _turn_u)
	var b := Basis(Vector3.UP, _turn_dir * PI * 0.5 * e)
	world.transform = Transform3D(b, _pivot - b * _pivot)
	if _turn_u >= 1.0:
		_finish_turn()


## The turn is done: the swing is baked into the pieces, the cross street's
## segments become the loop, and the old street is let go behind.
func _finish_turn() -> void:
	var t := world.transform
	world.transform = Transform3D.IDENTITY
	for c in world.get_children():
		(c as Node3D).transform = t * (c as Node3D).transform
	var old := segs.duplicate()
	segs.clear()
	var ct: Transform3D = _cross.transform
	for seg in _cross.get_children():
		var g: Transform3D = ct * (seg as Node3D).transform
		_cross.remove_child(seg)
		world.add_child(seg)
		(seg as Node3D).transform = Transform3D(Basis(), g.origin)
		segs.append(seg)
	for n in old:
		_leftovers.append(n)
	for n in _turn_extra:
		if n != _cross:
			_leftovers.append(n)
	_turn_extra.clear()
	_cross.queue_free()
	_cross = null
	seg_len = SEG
	turn_state = Turn.NONE
