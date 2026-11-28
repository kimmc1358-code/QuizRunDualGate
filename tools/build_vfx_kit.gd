extends SceneTree

# Copies what the game uses out of BinbunVFX's packs:
#
# - Portal VFX (paid): the portal shader, for the gates' inner face
#   (SpaceRun._make_portal), into assets/binbun_vfx/.
# - Stylized Explosion FX (CC0; 2026-11-28, owner): the explosions a planet
#   smashed in FEVER bursts with (SpaceRun._smash_fx), into
#   assets/BinbunVFX_Vol2/, the path the pack's scenes name, so they load
#   as they are.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_vfx_kit.gd -- <pack dir> [<pack dir> ...]
#
# then `--import`. Each <pack dir> is the folder a zip unzips to:
# PortalVFXFull/ (holding assets/BinbunVFX/) or ExplosionFXFull/ (holding
# assets/BinbunVFX_Vol2/). The owner keeps the zips under
# `D:\Godot\Godot VFX collection\`.
#
# **Nothing this writes goes into git.** The portal pack is paid and this
# repository is public; the explosions are CC0 and could be, but they travel
# the same way so a fresh clone builds every kit alike. Both folders are
# gitignored. Without them the gates keep an empty hole and a fever smash
# keeps only its own shards.
#
# Of the portal pack only the shader is taken. Its scenes carry particles, a
# light and an AnimationPlayer per portal, which four gates a step on a phone
# do not need; its noise and shape textures are plain Godot resources,
# rebuilt in code from the same settings (SpaceRun._portal_textures).
#
# Of the explosion pack the effects, their shaders and scripts are taken,
# with the two shared scripts they use; not its showcase scene, which pulls
# in an HDR sky. The shared controller prints "AA" every time an effect
# restarts, a leftover from its author's debugging, and the line is dropped.

const OUT := "res://assets/binbun_vfx/"
const FILES := [
	"src/shader/portal.gdshader",
	"src/shader/util/dithering.gdshaderinc",
]
const VOL2_OUT := "res://assets/BinbunVFX_Vol2/"
const EXPLOSION_SKIP := ["explosion_fx_scene_full.tscn", "all.png", "all.png.import"]
const SHARED_SCRIPTS := ["VFXControllerBB.gd", "VFXOmniLightBB.gd"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <unzipped pack dir> [...]")
		quit(1)
		return
	var did := false
	for dir: String in args:
		if DirAccess.dir_exists_absolute(dir.path_join("assets/BinbunVFX/portal_vfx")):
			if not _portal(dir.path_join("assets/BinbunVFX/portal_vfx")):
				quit(1)
				return
			did = true
		if DirAccess.dir_exists_absolute(dir.path_join("assets/BinbunVFX_Vol2/ExplosionFX")):
			if not _explosions(dir.path_join("assets/BinbunVFX_Vol2")):
				quit(1)
				return
			did = true
	if not did:
		push_error("no pack found in %s" % [args])
		quit(1)
		return
	quit()


func _portal(src: String) -> bool:
	for f: String in FILES:
		var to: String = ProjectSettings.globalize_path(OUT + f.trim_prefix("src/shader/"))
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		if DirAccess.copy_absolute(src.path_join(f), to) != OK:
			push_error("missing %s" % src.path_join(f))
			return false
		print("  %s" % f.get_file())
	print("wrote ", OUT)
	return true


func _explosions(src: String) -> bool:
	var n := _copy_tree(src.path_join("ExplosionFX"), ProjectSettings.globalize_path(VOL2_OUT + "ExplosionFX"))
	if n <= 0:
		push_error("nothing copied from %s" % src.path_join("ExplosionFX"))
		return false
	var to_dir: String = ProjectSettings.globalize_path(VOL2_OUT + "shared/script")
	DirAccess.make_dir_recursive_absolute(to_dir)
	for f: String in SHARED_SCRIPTS:
		var text := FileAccess.get_file_as_string(src.path_join("shared/script").path_join(f))
		if text.is_empty():
			push_error("missing shared/script/%s" % f)
			return false
		text = text.replace("\tprint(\"AA\")\n", "")
		var out := FileAccess.open(to_dir.path_join(f), FileAccess.WRITE)
		out.store_string(text)
		out.close()
	print("  ExplosionFX: %d files, and %d shared scripts" % [n, SHARED_SCRIPTS.size()])
	print("wrote ", VOL2_OUT)
	return true


func _copy_tree(from: String, to: String) -> int:
	var d := DirAccess.open(from)
	if d == null:
		return 0
	DirAccess.make_dir_recursive_absolute(to)
	var n := 0
	for f in d.get_files():
		if EXPLOSION_SKIP.has(f):
			continue
		if DirAccess.copy_absolute(from.path_join(f), to.path_join(f)) == OK:
			n += 1
	for sub in d.get_directories():
		n += _copy_tree(from.path_join(sub), to.path_join(sub))
	return n
