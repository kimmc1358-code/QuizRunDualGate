extends SceneTree

# Copies the portal shader out of BinbunVFX's Portal VFX pack for the gates'
# inner face (SpaceRun._make_portal).
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_vfx_kit.gd -- <unzipped PortalVFXFull dir>
#
# then `--import`. <dir> is the folder PortalVFXFull.zip unzips to (the one
# holding assets/BinbunVFX/).
#
# **Nothing this writes may go into git**, for the same reason as the Synty
# kits: the pack is paid and this repository is public. The output goes to
# assets/binbun_vfx/, which .gitignore excludes. Without it the gates keep an
# empty hole and the game is otherwise the same.
#
# Only the shader is taken. The pack's scenes carry particles, a light and an
# AnimationPlayer per portal, which four gates a step on a phone do not need;
# its noise and shape textures are plain Godot resources, rebuilt in code
# from the same settings (SpaceRun._portal_textures).

const OUT := "res://assets/binbun_vfx/"
const FILES := [
	"src/shader/portal.gdshader",
	"src/shader/util/dithering.gdshaderinc",
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <unzipped PortalVFXFull dir>")
		quit(1)
		return
	var src: String = args[0].path_join("assets/BinbunVFX/portal_vfx")
	for f: String in FILES:
		var to: String = ProjectSettings.globalize_path(OUT + f.trim_prefix("src/shader/"))
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		if DirAccess.copy_absolute(src.path_join(f), to) != OK:
			push_error("missing %s" % src.path_join(f))
			quit(1)
			return
		print("  %s" % f.get_file())
	print("wrote ", OUT)
	quit()
