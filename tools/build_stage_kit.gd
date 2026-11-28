extends SceneTree

# Copies what the stage backgrounds (scripts/StageScenery.gd) use out of two
# paid Synty packs, straight from their zips, into assets/stage_kit/
# (gitignored, like every kit: the packs are paid and this repo is public):
#
# - POLYGON Sci-Fi Space (the source-files zip, the same one
#   tools/build_space_kit.py reads): the other three skyboxes' front faces,
#   and the modular interior pieces the ship's hall and trench are built from.
#   The FBX pieces are read with FBXDocument and saved as plain meshes, their
#   node transforms baked in and their materials dropped (one atlas material
#   is laid over them all in the game).
# - POLYGON Sci-Fi City (the Godot 4.6 project zip): towers, road, signs,
#   streetlights, and the holographic signs FEVER smashes in the city. It ships its meshes as Godot .res files; they
#   are re-saved with their materials cleared, since those point into the
#   pack's own project.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_stage_kit.gd -- <space zip> <city zip>
#
# then `--import`. The owner's zips are
# POLYGON_Scifi_Space_SourceFiles_v2.zip and
# POLYGON_SciFi_City_Godot_4_6_2_v1_0_2.zip, in Downloads. Without the kit
# the game plays the space stage only; the debug stage switch says so.

const OUT := "res://assets/stage_kit/"

const SPACE_FILES := {
	# skyboxes: the front face of each, for the space stages
	"SourceFiles/Textures/FX_Textures/PolygonSciFiSpace_Skybox_02_Front.png": "space/sky_02.png",
	"SourceFiles/Textures/FX_Textures/PolygonSciFiSpace_Skybox_03_Front.png": "space/sky_03.png",
	"SourceFiles/Textures/FX_Textures/PolygonSciFiSpace_Skybox_04_Front.png": "space/sky_04.png",
	"SourceFiles/Textures/PolygonSciFiSpace_Texture_01_A.png": "space/atlas.png",
	"SourceFiles/Textures/PolygonSciFiSpace_Emissive_01.png": "space/emissive.png",
}
const SPACE_PIECES := [
	"SM_Bld_Floor_01", "SM_Bld_Ceiling_01", "SM_Bld_Wall_01", "SM_Bld_Wall_02",
	"SM_Bld_Wall_04", "SM_Bld_Wall_05", "SM_Bld_Wall_Mechanical_01",
	"SM_Bld_Wall_Pillar_03", "SM_Prop_Light_Panel_01",
	# the city's sky: a ringed planet
	"SM_Env_PlanetRings_01",
]

const CITY_ROOT := "polygon-sci-fi-city-01/Assets/Synty/PolygonSciFiCity/"
const CITY_TEXTURES := {
	"Textures/Alts/PolygonScifi_01_A.png": "city/atlas.png",
	"Textures/Emissive/PolygonScifi_01_Emissive.png": "city/emissive.png",
	"Textures/Misc/Background_Building_01_Emissive.png": "city/windows.png",
	"Textures/Misc/Road_01.png": "city/road.png",
	"Textures/Misc/Neon_Signs_01.png": "city/neon.png",
	"Textures/Misc/Signs_01.png": "city/signs.png",
	"Textures/Misc/Billboards_01.png": "city/billboards.png",
}
const CITY_MESHES := [
	"SM_Bld_Large_01", "SM_Bld_Large_02", "SM_Bld_Large_03", "SM_Bld_Large_04", "SM_Bld_Large_06",
	"SM_Bld_Background_Med_03", "SM_Bld_Background_Med_06", "SM_Bld_Background_Med_09",
	"SM_Bld_Background_Lrg_01", "SM_Bld_Background_Lrg_02", "SM_Bld_Background_Lrg_03",
	"SM_Env_Road_Lines_01_SF", "SM_Env_Sidewalk_Straight_01_SF", "SM_Prop_Streetlight_01",
	"SM_Sign_Neon_01", "SM_Sign_Neon_02", "SM_Sign_Neon_03", "SM_Sign_Neon_04", "SM_Sign_Neon_05",
	"SM_Sign_Neon_06", "SM_Sign_Neon_07", "SM_Sign_Neon_08", "SM_Sign_Neon_09",
	"SM_Sign_Billboard_Large_01", "SM_Sign_Billboard_Large_02", "SM_Sign_Billboard_Large_03",
	# FEVER's targets in the city: holographic food signs and their outlines
	"SM_Prop_Hologram_Noodles_01", "SM_Prop_LargeSign_Noodles_01_Outline",
	"SM_Prop_Hologram_Burger_03", "SM_Prop_LargeSign_Burger_03_Outline",
	"SM_Prop_Hologram_Pizza_01", "SM_Prop_LargeSign_Pizza_01_Outline",
	"SM_Prop_Hologram_Bottle_01", "SM_Prop_Hologram_Bottle_02", "SM_Prop_Hologram_Bottle_03",
]
const CITY_ADS := 22   # SM_Sign_Ad_01 .. _22


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <POLYGON_Scifi_Space_SourceFiles zip> <POLYGON_SciFi_City Godot zip>")
		quit(1)
		return
	var ok := _space(args[0]) and _city(args[1])
	quit(0 if ok else 1)


func _write(rel: String, bytes: PackedByteArray) -> void:
	var path := ProjectSettings.globalize_path(OUT + rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _open(zip_path: String) -> ZIPReader:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		push_error("cannot open %s" % zip_path)
		return null
	return z


func _space(zip_path: String) -> bool:
	var z := _open(zip_path)
	if z == null:
		return false
	for src in SPACE_FILES:
		var bytes := z.read_file(src)
		if bytes.is_empty():
			push_error("not in the space zip: %s" % src)
			return false
		_write(SPACE_FILES[src], bytes)
	for piece: String in SPACE_PIECES:
		var bytes := z.read_file("SourceFiles/FBX/%s.fbx" % piece)
		if bytes.is_empty():
			push_error("not in the space zip: %s.fbx" % piece)
			return false
		var doc := FBXDocument.new()
		var st := FBXState.new()
		if doc.append_from_buffer(bytes, "", st) != OK:
			push_error("could not read %s.fbx" % piece)
			return false
		var scene: Node = doc.generate_scene(st)
		var mesh := _bake(scene)
		scene.free()
		ResourceSaver.save(mesh, OUT + "space/%s.res" % piece)
	z.close()
	print("  space: %d files, %d pieces" % [SPACE_FILES.size(), SPACE_PIECES.size()])
	return true


## Every mesh under `root`, with its node transform baked in, as one mesh of
## one surface and no material.
func _bake(root: Node) -> ArrayMesh:
	var st := SurfaceTool.new()
	var parts := []
	_collect(root, Transform3D.IDENTITY, parts)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var m: Mesh = p[0]
		for s in m.get_surface_count():
			st.append_from(m, s, p[1])
	return st.commit()


func _collect(n: Node, xf: Transform3D, acc: Array) -> void:
	var here: Transform3D = xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		acc.append([(n as MeshInstance3D).mesh, here])
	for c in n.get_children():
		_collect(c, here, acc)


func _city(zip_path: String) -> bool:
	var z := _open(zip_path)
	if z == null:
		return false
	for src in CITY_TEXTURES:
		var bytes := z.read_file(CITY_ROOT + src)
		if bytes.is_empty():
			push_error("not in the city zip: %s" % src)
			return false
		_write(CITY_TEXTURES[src], bytes)
	var names: Array = CITY_MESHES.duplicate()
	for i in range(1, CITY_ADS + 1):
		names.append("SM_Sign_Ad_%02d" % i)
	var tmp := OS.get_user_data_dir().path_join("stage_kit_tmp.res")
	for n: String in names:
		var bytes := z.read_file(CITY_ROOT + "Models/extracted/%s.res" % n)
		if bytes.is_empty():
			push_error("not in the city zip: %s.res" % n)
			return false
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		var mesh := ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if mesh == null:
			push_error("could not load %s.res" % n)
			return false
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, null)
		mesh.resource_path = ""
		ResourceSaver.save(mesh, OUT + "city/%s.res" % n)
	DirAccess.remove_absolute(tmp)
	z.close()
	print("  city: %d textures, %d meshes" % [CITY_TEXTURES.size(), names.size()])
	print("wrote ", OUT)
	return true
