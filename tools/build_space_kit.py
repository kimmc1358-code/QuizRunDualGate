"""Build the space scenery kit from Synty's POLYGON Sci-Fi Space pack.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b \
        --python tools/build_space_kit.py -- <repo> <synty_source_dir>

<synty_source_dir> is the unzipped POLYGON_Scifi_Space_SourceFiles_v2 folder
that holds FBX/ and Textures/ (the zip's SourceFiles/). Only the files named
below are read, so it is enough to unzip those.

**Nothing this writes may go into git.** The repository is public, and Synty's
licence allows shipping their models inside a built game but not handing out
the source files. The kit goes to assets/synty_space/, which .gitignore
excludes, and a fresh clone has to run this script once with its own licensed
copy of the pack. Without the kit the game still runs: SpaceRun.gd falls back
to plain spheres and a simple ship.

Output, all in assets/synty_space/:
    space_kit.glb     one root node per model below, named as in KIT
    land_mask.png     planet continents, white = land (the planet shader mixes two colours by it)
    cloud_mask.png    planet clouds
    sky.png           the skybox's front face, the backdrop behind everything

Synty paints its planets with a custom shader that glTF cannot carry, so the
planets go out with only their UVs; the game gives them its own shader
(assets/shaders/planet.gdshader). The ship keeps the pack's colour atlas and
its emissive map.
"""
import bpy
import os
import sys

args = sys.argv[sys.argv.index("--") + 1:]
REPO, SRC = args[0], args[1]
OUT_DIR = os.path.join(REPO, "assets", "synty_space")
MAX_TEX = 1024           # every texture is scaled down to this; the APK carries them

KIT = [
	"SM_Ship_Fighter_05",     # the player
	"SM_Ship_Bomber_04",      # the boss
	"SM_Env_Planet_01",
	"SM_Env_Planet_02",
	"SM_Env_Planet_05",
	"SM_Env_Planet_08",
	"SM_Env_Planet_09",
	"SM_Env_Planet_10",
	"SM_Env_Asteroid_01",
	"SM_Env_Asteroid_02",
	"SM_Env_Asteroid_03",
	"SM_Env_Asteroid_05",
	# The quiz gates. Only the inner ring and its glow band: the outer ring's
	# three spurs reach 1.8x the hole, and the four slots are too close for that.
	"SM_Veh_WarpGate_Inner_01",
	"SM_Veh_WarpGate_Glow_01",
]
SHIP_TEXTURE = "PolygonSciFiSpace_Texture_01_A.png"
SHIP_EMISSIVE = "PolygonSciFiSpace_Emissive_01.png"
COPIES = {
	"land_mask.png": "Planet_Land_Mask_01.png",
	"cloud_mask.png": "Planet_Cloud_Mask_01.png",
	"sky.png": "FX_Textures/PolygonSciFiSpace_Skybox_01_Front.png",
}


def tex_path(name):
	return os.path.join(SRC, "Textures", name)


def load_scaled(name):
	img = bpy.data.images.load(tex_path(name))
	if max(img.size) > MAX_TEX:
		f = MAX_TEX / max(img.size)
		img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
	return img


def ship_material():
	mat = bpy.data.materials.new("ship")
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = nt.nodes["Principled BSDF"]
	bsdf.inputs["Roughness"].default_value = 0.5
	bsdf.inputs["Metallic"].default_value = 0.2
	base = nt.nodes.new("ShaderNodeTexImage")
	base.image = load_scaled(SHIP_TEXTURE)
	base.image.pack()
	nt.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
	em = nt.nodes.new("ShaderNodeTexImage")
	em.image = load_scaled(SHIP_EMISSIVE)
	em.image.pack()
	nt.links.new(em.outputs["Color"], bsdf.inputs["Emission Color"])
	bsdf.inputs["Emission Strength"].default_value = 1.0
	return mat


def plain_material(name):
	# A name only: Main replaces it with the planet shader.
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	return mat


def build(prefab, mats):
	before = set(bpy.data.objects)
	bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, "FBX", prefab + ".fbx"))
	new = [o for o in bpy.data.objects if o not in before]
	keep = next(o for o in new if o.type == 'MESH')
	# Keep the world matrix when detaching: the FBX root carries the
	# centimetre scale and the Y-up turn (the forest kit came out 100x too big
	# and lying down without this).
	world = keep.matrix_world.copy()
	keep.parent = None
	keep.matrix_world = world
	for o in new:
		if o is not keep:
			bpy.data.objects.remove(o, do_unlink=True)
	bpy.ops.object.select_all(action='DESELECT')
	keep.select_set(True)
	bpy.context.view_layer.objects.active = keep
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	me = keep.data
	me.materials.clear()
	if "Glow" in prefab:
		me.materials.append(mats["glow"])
	elif prefab.startswith("SM_Ship") or "WarpGate" in prefab:
		# The gate is painted from the same atlas, emissive lights included.
		me.materials.append(mats["ship"])
	elif "Planet" in prefab:
		me.materials.append(mats["planet"])
	else:
		me.materials.append(mats["rock"])
	keep.name = prefab.replace("SM_Env_", "").replace("SM_", "")
	me.name = keep.name
	d = keep.dimensions
	print("  %-22s %6d verts  %.1f x %.1f x %.1f" % (keep.name, len(me.vertices), d.x, d.y, d.z))


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	mats = {"ship": ship_material(), "planet": plain_material("planet"), "rock": plain_material("rock"),
		"glow": plain_material("glow")}
	for prefab in KIT:
		build(prefab, mats)
	out = os.path.join(OUT_DIR, "space_kit.glb")
	bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_apply=True,
		export_yup=True, export_materials='EXPORT', export_image_format='AUTO')
	for dst, src in COPIES.items():
		img = load_scaled(src)
		img.filepath_raw = os.path.join(OUT_DIR, dst)
		img.file_format = 'PNG'
		img.save()
	print("wrote", OUT_DIR)


main()
