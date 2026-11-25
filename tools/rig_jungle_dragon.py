"""Rig the JUNGLE dragon's wings and render its sprites. Blender script.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b \
        --python tools/rig_jungle_dragon.py -- <repo root>

Source: assets/characters/dragon_green/source/emerald_emberwing_meshy.glb, a
Meshy model with no rig and no animation. It is one connected mesh, so the
wings cannot be split off as separate objects. Instead, each vertex gets a
weight from its position (wing_weight), and two bones roll the wings about
their root lines.

Writes, into assets/characters/dragon_green/:
  dragon_fly.png    2x2 sheet of 256px cells, 4-frame flap (8 fps in game)
  dragon_happy.png  wings spread, nose up  (gate passed / new record)
  dragon_sad.png    wings folded, nose down  (game over)
  source/dragon_rigged.glb  the rigged model with the flap as an animation
and prints the opaque-bbox centres that MODE_DRAW_OFFSET_* in Main.gd need.

How the weights were found (2026-11-25): x-z occupancy maps of thin y slices
showed each wing leaving the back just beside the spine, at about
(0.055, y 0.02, z -0.11) at the front and (0.07, y 0.40, z -0.04) at the back,
and rising outward from there. The first rig put the hinge at z +0.05,
halfway up the wing, so the wing visibly bent in its middle. Its head mask
also reached y -0.16, which caught the horns, and they flapped. Both are
fixed here: the hinge is the measured root line, and nothing ahead of
y -0.03 moves.
"""
import bpy, sys, math, mathutils, os

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
DIR = os.path.join(ROOT, "assets", "characters", "dragon_green")
SRC = os.path.join(DIR, "source", "emerald_emberwing_meshy.glb")

FLAP_ANGLES = [0.0, 30.0, 60.0, 30.0]   # wing roll per frame, degrees outward-and-down
HAPPY = {"wing": 45.0, "pitch": -8.0}   # pitch < 0 lifts the nose
SAD = {"wing": 0.0, "pitch": 10.0}   # wings folded: drooping them at 75 put a tip past the tail and off the cell
CELL = 256
# Ortho width the 256px cell spans. The old 2D dragon filled about
# 238x202 of its cell; at 1.06 the model's 0.96 nose-to-tail length lands at
# about 237px, so the character keeps its on-screen size, with a few pixels
# to spare for the pitched faces (12 degrees of nose-down touched the edge).
ORTHO = 1.06
CAM_DIR = mathutils.Vector((-1.0, 0.18, 0.12)).normalized()  # from the left, a little ahead and above
CAM_TARGET = mathutils.Vector((0.0, -0.006, -0.03))

ROOT_FRONT = mathutils.Vector((0.055, 0.02, -0.11))
ROOT_BACK = mathutils.Vector((0.07, 0.40, -0.04))
SPREAD = mathutils.Vector((0.26, 0.97)).normalized()   # the wing's spread direction in x-z


def smooth(e0, e1, x):
	t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
	return t * t * (3 - 2 * t)


def hinge_at(y):
	t = max(0.0, min(1.0, (y - ROOT_FRONT.y) / (ROOT_BACK.y - ROOT_FRONT.y)))
	return ROOT_FRONT.lerp(ROOT_BACK, t)


def wing_weight(co):
	ax = abs(co.x)
	h = hinge_at(co.y)
	s = (ax - h.x) * SPREAD.x + (co.z - h.z) * SPREAD.y   # distance out along the wing
	return (smooth(0.0, 0.04, s)       # above the root line: the whole wing turns at its root
		* smooth(0.025, 0.045, ax)     # off the spine: the back spikes stay
		* smooth(-0.03, 0.03, co.y))   # behind the head: the horns stay


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
scene = bpy.context.scene

arm_data = bpy.data.armatures.new("rig")
arm = bpy.data.objects.new("rig", arm_data)
scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
body = arm_data.edit_bones.new("body")
body.head = (0, 0.1, -0.2)
body.tail = (0, -0.2, -0.2)
for side, sx in (("L", -1), ("R", 1)):
	b = arm_data.edit_bones.new("wing_" + side)
	b.head = (sx * ROOT_FRONT.x, ROOT_FRONT.y, ROOT_FRONT.z)
	b.tail = (sx * ROOT_BACK.x, ROOT_BACK.y, ROOT_BACK.z)
	b.parent = body
bpy.ops.object.mode_set(mode='OBJECT')

g_body = mesh.vertex_groups.new(name="body")
g_left = mesh.vertex_groups.new(name="wing_L")
g_right = mesh.vertex_groups.new(name="wing_R")
for v in mesh.data.vertices:
	w = wing_weight(v.co)
	if w > 0.0:
		(g_left if v.co.x < 0 else g_right).add([v.index], w, 'REPLACE')
	if w < 1.0:
		g_body.add([v.index], 1.0 - w, 'REPLACE')
mesh.parent = arm
mesh.modifiers.new("arm", 'ARMATURE').object = arm


def pose(wing_deg, frame=None):
	for side, sgn in (("L", -1), ("R", 1)):   # mirrored, so both swing outward
		pb = arm.pose.bones["wing_" + side]
		pb.rotation_mode = 'XYZ'
		pb.rotation_euler = (0, math.radians(wing_deg) * sgn, 0)   # roll about the root line
		if frame is not None:
			pb.keyframe_insert("rotation_euler", frame=frame)


# ---- render setup ----
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = CELL
scene.render.resolution_y = CELL
scene.render.film_transparent = True
scene.view_settings.view_transform = 'Standard'
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(40), 0, math.radians(-60))
sun.data.energy = 2.5
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = 'ORTHO'
cam.data.ortho_scale = ORTHO
cam.location = CAM_TARGET + CAM_DIR * 3
cam.rotation_euler = (-CAM_DIR).to_track_quat('-Z', 'Y').to_euler()

tmp = bpy.app.tempdir


def render(name):
	path = os.path.join(tmp, name + ".png")
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	img = bpy.data.images.load(path)
	px = list(img.pixels)
	bpy.data.images.remove(img)
	return px


def bbox(px):
	xs, ys = [], []
	for y in range(CELL):
		row = y * CELL * 4
		for x in range(CELL):
			if px[row + x * 4 + 3] > 0.1:
				xs.append(x)
				ys.append(CELL - 1 - y)   # top-down, as the game measures
	return min(xs), min(ys), max(xs), max(ys)


def save_png(px, w, h, path):
	img = bpy.data.images.new("out", w, h, alpha=True)
	img.pixels = px
	img.filepath_raw = path
	img.file_format = 'PNG'
	img.save()
	bpy.data.images.remove(img)


def report(label, boxes):
	cx = sum((b[0] + b[2]) * 0.5 for b in boxes) / len(boxes)
	cy = sum((b[1] + b[3]) * 0.5 for b in boxes) / len(boxes)
	touches = any(b[0] == 0 or b[1] == 0 or b[2] == CELL - 1 or b[3] == CELL - 1 for b in boxes)
	print("%-6s centre (%.1f, %.1f)  offset Vector2(%.1f, %.1f)  size %dx%d%s" % (
		label, cx, cy, (128 - cx) * 100 / 256, (128 - cy) * 100 / 256,
		max(b[2] - b[0] for b in boxes), max(b[3] - b[1] for b in boxes),
		"  ** TOUCHES THE CELL EDGE **" if touches else ""))


# ---- fly sheet ----
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
scene.frame_start = 1
scene.frame_end = len(FLAP_ANGLES)
for i, a in enumerate(FLAP_ANGLES):
	pose(a, i + 1)
frames, boxes = [], []
for i in range(len(FLAP_ANGLES)):
	scene.frame_set(i + 1)
	px = render("fly_%d" % i)
	frames.append(px)
	boxes.append(bbox(px))
report("fly", boxes)
sheet = [0.0] * (CELL * 2 * CELL * 2 * 4)
for i, px in enumerate(frames):
	col, row = i % 2, i // 2              # reading order, as _slice_spritesheet cuts it
	y0 = (1 - row) * CELL                 # Blender images start at the bottom
	for y in range(CELL):
		src = y * CELL * 4
		dst = ((y0 + y) * CELL * 2 + col * CELL) * 4
		sheet[dst:dst + CELL * 4] = px[src:src + CELL * 4]
save_png(sheet, CELL * 2, CELL * 2, os.path.join(DIR, "dragon_fly.png"))

# The rigged model with its flap, for any later 3D use.
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.export_scene.gltf(filepath=os.path.join(DIR, "source", "dragon_rigged.glb"), export_animations=True)

# ---- faces: a static pose each, the whole body pitched ----
arm.animation_data_clear()
bpy.ops.object.mode_set(mode='POSE')
for name, p in (("happy", HAPPY), ("sad", SAD)):
	pose(p["wing"])
	arm.rotation_euler = (math.radians(p["pitch"]), 0, 0)
	px = render(name)
	report(name, [bbox(px)])
	save_png(px, CELL, CELL, os.path.join(DIR, "dragon_%s.png" % name))
arm.rotation_euler = (0, 0, 0)
print("DONE")
