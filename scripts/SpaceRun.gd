class_name SpaceRun
extends Node

## The space game (2.0). A ship seen from behind, steered up/down/left/right by
## dragging anywhere, fires on its own while the run goes round one cycle:
##
##   PATTERN  one pattern of PATTERN_LEN gate steps in a row, one rule for the
##            whole pattern, shown in the question box: fly through the gate
##            of the box's colour (Kind.COLOR) or the gate the box's arrow
##            points at (Kind.ARROW). Each step is a row of gates; the ship is
##            drawn into the gate of the quarter it is in. A right gate pays
##            stardust and adds to the streak, which speeds the world up and
##            pays more; a wrong one only breaks the streak — no heart, no
##            weapon. Asteroids fly between the steps and cost a heart.
##   FEVER    after a pattern with FEVER_MIN_RIGHT or more right: at speed for
##            FEVER_PER_RIGHT a right gate (all right: 9 s), every planet
##            touched or shot smashed for points and stardust, nothing
##            costing a heart.
##   BOSS     after PATTERNS_PER_CYCLE patterns an enemy ship arrives. A strong
##            weapon melts it; a weak one can still win by dodging long
##            enough. Its shots cost a heart. Then the next, harder cycle.
##
## The weapon grows only with the streak (POWER_EVERY), and never drops.
##
## Main owns the run — score, combo, hearts, popups, the
## question box. This node owns the world and the rules of contact, and
## reports outcomes through Main's `_space_*` handlers.
##
## The world is a plane at z = 0 where the ship flies; everything is judged
## there, at the ship's real 3D position, which is also what the camera shows.
##
## Synty's Sci-Fi Space pack supplies the models. It cannot be committed (see
## tools/build_space_kit.py); without the kit this falls back to plain shapes.

enum Phase { PATTERN, BOSS, FEVER }
enum Kind { COLOR, ARROW, SPOT, MEMORY, MIX, ARROW_MIX, ARROW_SUM, ARROW_MEMORY, SHELL }
## How a step's gates are laid out (2026-11-27): the diamond, left, right,
## up and down, or the 2x2 grid of corners. A step uses one; a level of the
## bank says which, or MIXED for either, step by step.
enum Layout { DIAMOND, GRID, MIXED }
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
# Every place a gate can stand: 0-3 the diamond (left, right, up, down),
# 4-7 the grid (up-left, up-right, down-left, down-right). The grid's
# corners are 3.2 apart, past the 2.9 two outer rings take, and inside the
# diamond's reach, so they fit the screen wherever the diamond does.
const SLOTS := [Vector2(-1.85, 0.0), Vector2(1.85, 0.0), Vector2(0.0, 2.3), Vector2(0.0, -2.3),
	Vector2(-1.6, 1.6), Vector2(1.6, 1.6), Vector2(-1.6, -1.6), Vector2(1.6, -1.6)]
## The slots of each layout (Layout.DIAMOND, Layout.GRID).
const LAYOUT_SLOTS := [[0, 1, 2, 3], [4, 5, 6, 7]]
## ARROW_SUM: the two arrows that add up to each grid corner, up or down
## first, then left or right.
const CORNER_PARTS := {4: [2, 0], 5: [2, 1], 6: [3, 0], 7: [3, 1]}
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
# The gate's inner face (2026-11-27): a swirling portal across the hole, from
# BinbunVFX's Portal VFX pack (tools/build_vfx_kit.gd copies its shader into
# the gitignored assets/binbun_vfx/). Without it the hole stays empty.
# It takes the gate's own glow colour, frame by frame, so it says nothing
# the ring does not: cyan for every gate, a colour gate's own colour, the
# aim lift, gold or red when judged. It is opaque ("Opaque" mode): "Warp",
# which bends what is behind it, pulled the ring's own lit inner edge into
# the hole as a thin turning circle, and showed the next step through it.
# The shader shows a disc 0.428 of the quad wide (its shape mask cut at 0.2),
# so PORTAL_QUAD = 2 * 1.12 / 0.428 tucks its edge just under the ring.
const PORTAL_SHADER_PATH := "res://assets/binbun_vfx/portal.gdshader"
const PORTAL_QUAD := 2.62
const PORTAL_DARK := 0.15           # the deep middle: the glow times this; 0.25 under Warp
const PORTAL_EMISSION := 1.6
const PORTAL_LAYERS := 8
const PORTAL_SPIN := 0.15
const PORTAL_INWARD := 0.5
const SHIP_HIT_RADIUS := 0.3
const SHIP_WIDTH := 1.7

# ---- speed ----
const SPAWN_Z := -70.0
const BASE_SPEED := 24.0           # 70 / 24 = 2.9 s from a wave appearing to its judgement
const GROW_DISTANCE := 10.0
const REMOVE_Z := 13.0
const PASS_SHRINK_DISTANCE := 4.0  # past the plane (z = 0); the camera is at 10
# A passed gate (2026-11-27) parts outward as it flies on, each away from
# the field's middle, PASS_SPREAD out by the time it reaches the camera,
# and shrinks over the longer PASS_GATE_SHRINK. It shrank over
# PASS_SHRINK_DISTANCE in place before, which at speed took 0.13 s and
# read as the gate blinking out. Parting, the top gate rises past the
# camera rather than filling its view, which is what the shrink was for.
const PASS_SPREAD := 4.5
const PASS_GATE_SHRINK := 10.0
# Pacing a pattern (2026-11-27). The steps come one after another, STEP_GAP
# apart, so the next one is in sight and can be read while the current one
# is being flown. 22 at first, about three in sight; the owner found the
# gates too close together and it went to 34 the same day, two in sight.
# A pattern starts slow and every right gate in a row adds PACE_PER_STREAK,
# up to PACE_MAX; a wrong gate breaks the streak, and the world eases back to
# PACE_START: whoever just missed gets the easy speed back. Each cycle is also
# CYCLE_SPEED_STEP faster overall, up to CYCLE_SPEED_MAX (speed()).
#
# Recounted on 2026-11-27, when the owner found it a little too hard. A step
# asks for about 0.4 s to read the box, 0.3 s to find the gate and 0.4 s to
# steer there, and the shell game and memory ask for more. It was 34 apart,
# 8% faster a cycle with no ceiling and PACE_MAX 1.25, which made a step
# 1.1 s at full streak in the first cycle and 0.8 s by the seventh, no room
# at all. Now, seconds a step = STEP_GAP / (BASE_SPEED * cycle * pace):
#
#                       cycle 1   3      5      7 and on
#   start (PACE_START)  2.9       2.65   2.4    2.25
#   full (PACE_MAX)     1.6       1.45   1.35   1.2
#
# Full speed comes at a streak of ten. The steps still come two in sight.
#
# Before patterns, one question wave slowed only near the gate; with steps
# this close that pulsed the world every step.
const STEP_GAP := 42.0
const PACE_START := 0.6
const PACE_PER_STREAK := 0.05
const PACE_MAX := 1.1
const CYCLE_SPEED_STEP := 0.05
const CYCLE_SPEED_MAX := 1.3
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
#
# The gate used to be fixed the moment the pull began, with the drag ignored
# from then on; the owner found it took hold too soon to change an answer at
# the last moment. Now the player steers through the pull, the gate follows
# their quarter until CAPTURE_LOCK of the way in, and the pull grows as
# u^CAPTURE_PULL_POW (cubed, against squared before), so it only takes over
# near the end: at half way it is an eighth of the way to the gate.
const CAPTURE_Z := -6.0
const CAPTURE_LOCK := 0.85
const CAPTURE_PULL_POW := 3.0
const PULL_GLIDE := 14.0          # 1/s, the pull sliding over to a newly chosen gate
const CAPTURE_SHIP_SCALE := 0.55   # the ship shrinks into the hole as it goes in
const SQUEEZE_RECOVER := 5.0       # 1/s, back to full size after the pass

# ---- the cycle ----
# Twelve steps a pattern (2026-11-27). Ten was the owner's first guess and
# felt short: a rule was over just as it was learned. Twelve divides by 3, 4
# and 6, the memory patterns' round lengths.
const PATTERN_LEN := 12
const PATTERNS_PER_CYCLE := 2
# ---- the pattern bank (2026-11-27) ----
# Every pattern the game can ask for, each at its own levels, kept apart
# from where the patterns are placed in a run: the owner is filling the
# bank first and drawing up the placement after. Until then _pick_pattern
# is a stand-in that walks the levels up a cycle at a time.
# tools/capture_pattern_bank.gd shoots every pattern at every level.
#
# The patterns (Kind):
#   COLOR   fly through the box's colour.
#   MIX     the same, but a step sometimes shows the colour under a red
#           no-entry sign: any gate but that one. Without it a colour
#           pattern lets the player stop reading the box after one step.
#   SPOT    spot the difference: the box shows the step's gates as coloured
#           dots laid out as the slots are, and one dot is not its gate's
#           colour; fly through that gate.
#   MEMORY  the owner's design: a round of colours shows in the box until
#           the round's first gate is judged, then the ones to come turn to
#           "?" and the round is flown from memory. Colours already flown
#           through stay, dimmed. Each round brings new colours, never one
#           colour twice in a row; a pattern of 12 at five a round runs
#           5 + 5 + 2.
#   ARROW         fly to the gate the arrow points at.
#   ARROW_MIX     the same, a step sometimes under the no-entry sign: any
#                 gate but that way. It replaced the red arrow, which meant
#                 "the opposite one": the owner did not see that the first
#                 time, and the no-entry sign is a road sign everyone reads.
#                 It means the same in every pattern: anything but this.
#   ARROW_SUM     two arrows, up or down and left or right, add up to a
#                 corner of the grid: up + right is the top right gate.
#   ARROW_MEMORY  MEMORY with arrows: a round of directions shown until its
#                 first gate, then "?". Directions are easier to hold than
#                 colours, since they can be said over (up, left, up), so
#                 the same length is the easier pattern. A diagonal comes
#                 on a grid step, a straight one on a diamond step.
#   SHELL         the shell game (2026-11-27): the box shows a colour, the
#                 gates come in wearing theirs, then at SHELL_HIDE their
#                 colours go out and they swap places (`swaps` times) until
#                 SHELL_END; fly through the one that wore the colour. All
#                 colours come back once the step is judged. It asks the eye
#                 to follow, not to read, which is what this game is for.
# "The odd arrow out" was turned down (2026-11-27): finding it is plain,
# but that its direction is the answer has to be explained.
#
# A level is a Dictionary; every one has `gates`, the gates a step (2-4):
#   switch   COLOR: the target colour changes every this many steps (0:
#            never), with a flash on the box and a chime, so the habit of
#            the last colour has to be broken.
#   avoid    MIX, ARROW_MIX: the chance a step is an avoid step.
#   hide     SPOT, ARROW_SUM: the box goes blank once the step is this far in
#            (approach()); 1 never. A step becomes the front one at about
#            0.40 ((70 - STEP_GAP) / 70), when the one before it is judged.
#   len      MEMORY, ARROW_MEMORY: colours or arrows a round. Six at most (2026-11-27): seen once,
#            colours are held about four at a time, five or six for a good
#            player, and with only four colours a long round repeats them,
#            while the ship is being flown. L3 adds a gate, not a colour, so
#            only one thing gets harder a level.
#   layout   ARROW, ARROW_MEMORY: Layout.DIAMOND (the default), GRID, or
#            MIXED, step by step. ARROW_SUM is always on the grid. For
#            ARROW_MEMORY a mixed level draws diagonals into its rounds.
const BANK := {
	Kind.COLOR: [
		{"gates": 2, "switch": 0}, {"gates": 3, "switch": 0}, {"gates": 4, "switch": 0},
		{"gates": 4, "switch": 5}, {"gates": 4, "switch": 3}],
	Kind.MIX: [
		{"gates": 3, "avoid": 0.2}, {"gates": 3, "avoid": 0.3}, {"gates": 4, "avoid": 0.3},
		{"gates": 4, "avoid": 0.4}, {"gates": 4, "avoid": 0.5}],
	Kind.SPOT: [
		{"gates": 2, "hide": 1.0}, {"gates": 3, "hide": 1.0}, {"gates": 4, "hide": 1.0},
		{"gates": 4, "hide": 0.82}, {"gates": 4, "hide": 0.7}],
	Kind.MEMORY: [
		{"gates": 3, "len": 3}, {"gates": 3, "len": 4}, {"gates": 4, "len": 4},
		{"gates": 4, "len": 5}, {"gates": 4, "len": 6}],
	Kind.ARROW: [
		{"gates": 2, "layout": Layout.DIAMOND}, {"gates": 3, "layout": Layout.DIAMOND},
		{"gates": 4, "layout": Layout.DIAMOND}, {"gates": 4, "layout": Layout.MIXED},
		{"gates": 4, "layout": Layout.GRID}],
	Kind.ARROW_MIX: [
		{"gates": 3, "avoid": 0.2}, {"gates": 3, "avoid": 0.3}, {"gates": 4, "avoid": 0.3},
		{"gates": 4, "avoid": 0.4}, {"gates": 4, "avoid": 0.5}],
	Kind.ARROW_SUM: [
		{"gates": 2, "hide": 1.0}, {"gates": 3, "hide": 1.0}, {"gates": 4, "hide": 1.0},
		{"gates": 4, "hide": 0.82}, {"gates": 4, "hide": 0.7}],
	Kind.ARROW_MEMORY: [
		{"gates": 3, "len": 3}, {"gates": 3, "len": 4}, {"gates": 4, "len": 4},
		{"gates": 4, "len": 5, "layout": Layout.MIXED}, {"gates": 4, "len": 6, "layout": Layout.MIXED}],
	Kind.SHELL: [
		{"gates": 2, "swaps": 1}, {"gates": 3, "swaps": 1}, {"gates": 3, "swaps": 2},
		{"gates": 4, "swaps": 2}, {"gates": 4, "swaps": 3}],
}
const AVOID_CROSS := Color(1.0, 0.18, 0.18)
# SHELL's window, as approach() fractions: colours shown until SHELL_HIDE
# (the step is the front one from about 0.40), swaps until SHELL_END, then
# the ship is free to go in before the pull starts at about 0.91. At the
# starting pace that is 1 s to see the colours as the front step, 1.4 s of
# swapping and 0.6 s to steer.
const SHELL_HIDE := 0.6
const SHELL_END := 0.88
const SHELL_ARC := 0.75             # how far two swapping gates bow apart
const SPOT_EMPTY := Color(0.55, 0.6, 0.75, 0.35)
const MEMORY_DONE_ALPHA := 0.35
# MEMORY's time to learn a round: the world slows on the round's first step,
# if it has to, so the colours are up for at least this long a colour. At
# full streak speed a step is only 1.1 s away, and six colours cannot be
# learned in that.
const MEMORY_SECONDS_EACH := 0.5
const RULE_FLASH_DECAY := 2.0        # 1/s, the box's flash when its rule changes
const DEMO_AVOID_PERIOD := 1.2       # s, plain then signed, in the tutorial

# ---- the streak: stardust and power ----
# A right gate pays STARDUST_PER_GATE times the streak it makes (1, 2, 3 ...),
# so a whole pattern in a row pays 78 against 12 for one broken every step.
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
# Asteroids. They flew in the gaps between a pattern's steps until
# 2026-11-27, when the owner took them out: with the gates to read and steer
# for, dodging rocks as well made a pattern too hard. Nothing spawns them in
# a run now; the asteroid itself is kept for a shooter mode (BATTLE).
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
# Earned by the right gates of the pattern just flown (2026-11-27, the
# owner's idea): FEVER_PER_RIGHT a right gate, FEVER_PERFECT_BONUS more for
# all of them, none under FEVER_MIN_RIGHT. It used to be all or nothing,
# eight seconds for a whole pattern right and none for one miss, which was
# too tight for what is meant to be the fun part. Twelve right is 9 s.
const FEVER_PER_RIGHT := 0.6
const FEVER_PERFECT_BONUS := 1.8
const FEVER_MIN_RIGHT := 6
const FEVER_SPEED := 2.2
const FEVER_SPAWN_INTERVAL := 0.28
const FEVER_FOV_BOOST := 7.0

# ---- control ----
# Raised on 2026-11-27 at the owner's call, the ship felt slow: the drag
# from 1.35, the follow from 16 (it now closes 90% of a gap in 0.1 s), and
# the keys from 6.0.
const DRAG_GAIN := 1.8
const SHIP_FOLLOW_SHARPNESS := 24.0
# Testing on PC (2026-11-27): the arrow keys, or WASD, steer the ship in a
# debug build, KEY_STEER_SPEED world units a second — the field is 4.6 wide,
# so about 0.6 s edge to edge. A release build ignores the keyboard: the
# game is a touch game, and a phone with a keyboard should not steer twice.
const KEY_STEER_SPEED := 8.0
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
# The pass (2026-11-27). A right gate lights up gold (a wrong one red), and
# bursts: a shockwave ring, shards thrown out of the ring in its plane, speed
# lines from its centre on the screen (draw_pass_lines), and the space
# streaks stretching with the lunge (PASS_STREAK_STRETCH x boost). Main adds
# a chime pitched up with the streak.
#
# It was all one gold at first, and the owner found it flat. Three Binbun
# packs (Stylized Hit FX, Electric FX, Magic Area) replaced it that evening
# and read worse, explosions and spells rather than a gate flown through, so
# this came back with colour instead (_pass_palette): the shockwave wears the
# gate's own colour (cyan for an arrow gate), the shards and the tips of the
# speed lines are drawn from a palette that widens with the streak, and from
# ten in a row a second ring follows in the opposite hue.
const PASS_SHOCK_LIFE := 0.30
const PASS_SHOCK_GROW := 2.6           # x the gate's radius, at the end; 4.2 covered half the screen
const PASS_SHOCK_GLOW := 1.8           # the ring's colour is lifted this much, to bloom
const PASS_SHARDS := 18
const PASS_SHARD_SPEED := 9.0
const PASS_SHARD_LIFE := 0.5
const PASS_SHARD_GLOW := 2.2
const PASS_LINES := 36
const PASS_LINE_LIFE := 0.36
# Made finer on 2026-11-27, when the owner asked for the burst to look more
# polished: soft light over hard shapes. Behind the crisp ring, a wide soft
# one (PASS_HALO); a bloom of light at the gate's middle (PASS_BLOOM); a
# light that lights the gate and the ship in the burst's colour for a
# moment (PASS_LIGHT); the shards became thin streaks with a glowing head;
# a few motes linger and twinkle (PASS_MOTES); the speed lines taper to a
# point.
const PASS_HALO_LIFE := 0.32
const PASS_HALO_GROW := 2.4            # x the gate's radius, at the end
const PASS_HALO_GLOW := 0.7            # 1.4 at first, a fog of the gate's colour over the next step
const PASS_BLOOM_LIFE := 0.24
const PASS_BLOOM_SIZE := Vector2(0.6, 3.0)  # x the gate's radius, start and end
const PASS_BLOOM_GLOW := 2.6
const PASS_LIGHT_LIFE := 0.28
const PASS_LIGHT_ENERGY := 7.0
const PASS_LIGHT_RANGE := 7.0
const PASS_SPARK_HEAD := 0.1           # the glowing head of each shard, world units; 0.26 read as blobs
# The shards fly out in the gate's plane, only this much toward the camera:
# at 0.6 their heads came at the camera and swelled into blurred balls.
const PASS_SHARD_TOWARD := 0.12
const PASS_MOTES := 10
const PASS_MOTE_LIFE := 0.7
const PASS_MOTE_SIZE := Vector2(0.05, 0.1)
const PASS_STREAK_STRETCH := 3.0
# The streak at which the palette widens: the gate's colour and white, then
# its opposite hue too, then every colour.
const PASS_PALETTE_STEPS := [5, 10]
const PASS_RAINBOW := [
	Color(1.0, 0.25, 0.25), Color(1.0, 0.65, 0.15), Color(1.0, 0.9, 0.2), Color(0.3, 1.0, 0.4),
	Color(0.3, 0.9, 1.0), Color(0.35, 0.5, 1.0), Color(0.85, 0.4, 1.0),
]
# The owner's "B": the world holds still for HITSTOP_TIME as a right gate is
# passed and the camera is thrown forward CAMERA_PUNCH, then eases back. The
# hit lands on the player, not only on the screen.
const HITSTOP_TIME := 0.06
const CAMERA_PUNCH := 0.6             # world units toward the plane
const CAMERA_PUNCH_EASE := 9.0        # 1/s
# The owner's "C": the passed gate's portal flares and swirls shut over
# PORTAL_CLOSE_TIME, so the gate itself answers the ship going through it.
const PORTAL_CLOSE_TIME := 0.4
const PORTAL_CLOSE_FLARE := 3.0       # emission, times PORTAL_EMISSION, at the start
# A wrong gate (2026-11-27) answers the opposite way to a right one: short
# and dull, never a reward. The camera jolts side to side instead of being
# thrown forward (WRONG_SHAKE), the passed gate's portal sputters red and
# goes out instead of swirling shut (WRONG_FAULT_TIME), and the gate that
# was right is ringed in green for REVEAL_TIME as it flies past, every one
# of them on an avoid step, so the player sees at once what it should have
# been; in the shell game and from memory that is the whole lesson.
const WRONG_SHAKE := 0.22             # world units, side to side
const WRONG_SHAKE_TIME := 0.3
const WRONG_SHAKE_FREQ := 46.0        # rad/s
const WRONG_FAULT_TIME := 0.45
const REVEAL_TIME := 0.7
const REVEAL_COLOR := Color(0.35, 1.0, 0.5)

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
const ARROW_NORMAL := Color(0.18, 0.55, 1.0)

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
var pulling := false             # a gate is drawing the ship in this frame
var pull_pos := Vector2.ZERO     # where the pull has the ship; see ship_shown()

var phase: int = Phase.PATTERN
var phase_time := 0.0
var cycle := 0                   # bosses beaten this run
var patterns_done := 0           # patterns finished this cycle

# the pattern under way
var pattern_kind: int = Kind.COLOR
var pattern_level := 1           # 1-based, into BANK[pattern_kind]
var pattern_color := 0           # MIX: index into GATE_COLORS
var pattern_colors: Array = []    # COLOR: the colour each step asks for
var pattern_rounds: Array = []    # MEMORY: a list of colour indices per round
var memory_shown := 0.0          # MEMORY: seconds the round's colours have been up
var memory_slow := 1.0           # MEMORY: the world's slowdown while they are learned
var rule_flash := 0.0            # 0..1, the box flashing at a change of rule
var fever_time := 0.0            # this fever's length, from the pattern before it
## The tutorial's box step (Main sets it): the colour in the box shows the
## no-entry sign every other DEMO_AVOID_PERIOD, so the sign the caption names
## is seen once before it counts.
var demo_avoid := false
var steps_spawned := 0
var steps_done := 0              # steps judged
var steps_right := 0
var streak := 0                  # right gates in a row

## Step waves: {"planets", "z", "resolved", "kind", "layout", "dir", "parts",
## "avoid", "spot"}; see _make_step
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
## The last right pass's screen burst: where it went off and when, its
## lines' angles, lengths and tip colours. Empty when none is showing.
var pass_lines := {}
## The pass burst's lights, {"node", "t"}, and its two textures, made once.
var pass_lights: Array = []
var dot_tex: Texture2D
var ring_tex: Texture2D
var hitstop := 0.0               # s of hold left
var punch := 0.0                 # 0..1, the camera thrown forward
var shake := 0.0                 # s of the wrong gate's jolt left
## The gates ringed in green after a wrong one: {"p", "t"}.
var reveals: Array = []

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
## The portal shader and the two textures it reads, or null without the kit.
var portal_shader: Shader
var portal_noise: Texture2D
var portal_shape: Texture2D


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
	_load_portal()
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


## The portal shader and its textures, rebuilt from the pack's own settings
## so only the shader has to be copied in: a radial gradient for the disc,
## and the pack's noise_04.tres, a ridged, domain-warped noise that reads as
## smoke. The owner chose it on 2026-11-27 from all nine of the pack's
## patterns side by side; it was noise_01, a softer cellular cloud, before.
func _load_portal() -> void:
	if not ResourceLoader.exists(PORTAL_SHADER_PATH):
		return
	portal_shader = load(PORTAL_SHADER_PATH)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.015
	fn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	fn.fractal_octaves = 3
	fn.fractal_weighted_strength = 0.5
	fn.domain_warp_enabled = true
	fn.domain_warp_frequency = 0.01
	fn.domain_warp_fractal_octaves = 2
	fn.domain_warp_fractal_lacunarity = 3.0
	var noise := NoiseTexture2D.new()
	noise.noise = fn
	noise.seamless = true
	portal_noise = noise
	var shape := GradientTexture2D.new()
	shape.gradient = Gradient.new()
	shape.fill = GradientTexture2D.FILL_RADIAL
	shape.fill_from = Vector2(0.5, 0.5)
	shape.fill_to = Vector2(0.5, 0.0)
	portal_shape = shape


## A portal across a gate's hole, as a child of the gate so it rolls and
## shrinks with it. Faces +Z, toward the camera.
func _make_portal(gate: Node3D) -> ShaderMaterial:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * PORTAL_QUAD
	# The shader bulges the middle toward the camera, which needs vertices.
	quad.subdivide_width = 24
	quad.subdivide_depth = 24
	var m := ShaderMaterial.new()
	m.shader = portal_shader
	m.set_shader_parameter("size", quad.size)
	m.set_shader_parameter("noise_texture", portal_noise)
	m.set_shader_parameter("shape_texture", portal_shape)
	m.set_shader_parameter("emission_strength", PORTAL_EMISSION)
	m.set_shader_parameter("layers", PORTAL_LAYERS)
	m.set_shader_parameter("spin_motion", PORTAL_SPIN)
	m.set_shader_parameter("inward_motion", PORTAL_INWARD)
	m.set_shader_parameter("base_motion", 0.2)
	m.set_shader_parameter("portal_mode", 0)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	# Drawn before the glow band, so the band stays on top of it.
	mi.sorting_offset = -0.1
	gate.add_child(mi)
	_portal_color(m, GATE_GLOW)
	return m


static func _portal_color(m: ShaderMaterial, glow: Color) -> void:
	if m == null:
		return
	var bright := Color(minf(glow.r, 1.0), minf(glow.g, 1.0), minf(glow.b, 1.0), 1.0)
	m.set_shader_parameter("primary_color", bright)
	m.set_shader_parameter("secondary_color", Color(bright.r * PORTAL_DARK, bright.g * PORTAL_DARK, bright.b * PORTAL_DARK, 1.0))


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
	return BASE_SPEED * minf(1.0 + CYCLE_SPEED_STEP * cycle, CYCLE_SPEED_MAX) * (FEVER_SPEED if phase == Phase.FEVER else 1.0) * pace * (1.0 + WARP_BOOST * boost) * memory_slow


## The speed `pace` eases toward: the streak's in a pattern, full elsewhere.
func _pace_target() -> float:
	if phase != Phase.PATTERN:
		return 1.0
	return minf(PACE_MAX, PACE_START + PACE_PER_STREAK * streak)


## The pattern under way's level, from the bank.
func level_spec() -> Dictionary:
	return spec_of(pattern_kind, pattern_level)


static func spec_of(kind: int, level: int) -> Dictionary:
	var levels: Array = BANK[kind]
	return levels[clampi(level, 1, levels.size()) - 1]


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
	pulling = false
	if camera != null:
		camera.fov = CAMERA_FOV
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
	for l in pass_lights:
		_free(l.node)
	pass_lights.clear()
	reveals.clear()
	shake = 0.0
	pass_lines = {}
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

## The placement: which pattern, at which level, comes next. A stand-in
## until the owner draws up the real table. The first cycle is plain colour
## then plain arrow, so the two simplest rules are met first; after that any
## pattern in the bank, at one level higher each cycle. A rule of symbols
## flown in order was dropped on 2026-11-27: reading a symbol off a gate in
## flight was too hard.
func _pick_pattern() -> Array:
	# Main's debug_force_pattern: one pattern all run, for trying it out.
	var forced: int = int(main.get("debug_force_pattern")) if main != null and OS.is_debug_build() and main.get("debug_force_pattern") != null else 0
	if forced > 0:
		var lvl: int = int(main.get("debug_force_level"))
		if lvl <= 0:
			lvl = cycle * PATTERNS_PER_CYCLE + patterns_done + 1
		return [forced - 1, lvl]
	if cycle == 0 and patterns_done < 2:
		return [[Kind.COLOR, Kind.ARROW][patterns_done], 1]
	var kinds: Array = BANK.keys()
	return [kinds[randi() % kinds.size()], cycle + 1]


## Starts a pattern: `kind` at `level`, or the next one _pick_pattern gives.
## A kind with no level takes the one _pick_pattern would give this cycle.
func _begin_pattern(kind: int = -1, level: int = -1) -> void:
	if kind < 0:
		var pick: Array = _pick_pattern()
		kind = pick[0]
		level = pick[1]
	elif level < 0:
		level = 1 if cycle == 0 else cycle + 1
	pattern_kind = kind
	pattern_level = clampi(level, 1, (BANK[kind] as Array).size())
	_prepare_pattern()
	steps_spawned = 0
	steps_done = 0
	steps_right = 0
	streak = 0
	if main != null:
		spawn_wave()


## Draws everything a pattern decides up front: MIX's colour, COLOR's colour
## for each step, the memory patterns' rounds.
func _prepare_pattern() -> void:
	var spec := level_spec()
	pattern_color = randi() % GATE_COLORS.size()
	pattern_colors = []
	var every: int = int(spec.get("switch", 0))
	var colour := randi() % GATE_COLORS.size()
	for k in PATTERN_LEN:
		if every > 0 and k > 0 and k % every == 0:
			var next: int = randi() % (GATE_COLORS.size() - 1)
			colour = next if next < colour else next + 1
		pattern_colors.append(colour)
	# MEMORY remembers colours; ARROW_MEMORY directions, as slots, the
	# diagonals among them only on a mixed level.
	var items: Array = range(GATE_COLORS.size())
	if pattern_kind == Kind.ARROW_MEMORY:
		items = LAYOUT_SLOTS[Layout.DIAMOND].duplicate()
		if int(spec.get("layout", Layout.DIAMOND)) == Layout.MIXED:
			items.append_array(LAYOUT_SLOTS[Layout.GRID])
	pattern_rounds = _memory_rounds(int(spec.get("len", 4)), items)
	memory_shown = 0.0
	memory_slow = 1.0
	rule_flash = 0.0


## Whether `kind` is flown from memory, with rounds shown and then hidden.
static func is_memory(kind: int) -> bool:
	return kind == Kind.MEMORY or kind == Kind.ARROW_MEMORY


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
	steps_spawned += 1
	waves.append(w)
	return w


## The layout a step of `spec` stands in.
static func _layout_of(spec: Dictionary) -> int:
	var layout: int = int(spec.get("layout", Layout.DIAMOND))
	if layout == Layout.MIXED:
		return Layout.DIAMOND if randf() < 0.5 else Layout.GRID
	return layout


## One step of `kind` at the pattern's level: its `gates` gates in distinct
## slots of one layout, one marked correct (all but one on an avoid step).
##   COLOR         every gate a different colour, one of them the step's.
##   MIX           the same with the pattern's colour; on an avoid step that
##                 gate is the only wrong one.
##   MEMORY        the same with the round's colour for the step.
##   SPOT          every gate a different colour; `spot` holds the box's dot
##                 for each slot (-1 where no gate), the gates' colours except
##                 at the correct slot, which gets another colour.
##   ARROW         `dir` is the correct slot, which the box's arrow points at.
##   ARROW_MIX     the same; on an avoid step that gate is the only wrong one.
##   ARROW_SUM     on the grid; `parts` are the two arrows adding up to `dir`.
##   ARROW_MEMORY  `dir` is the round's direction for the step, on the grid
##                 if it is a diagonal.
func _make_step(kind: int) -> Dictionary:
	var spec := spec_of(kind, pattern_level)
	var n: int = int(spec.gates)
	var layout: int = _layout_of(spec)
	var want_slot := -1
	if kind == Kind.ARROW_SUM:
		layout = Layout.GRID
	elif kind == Kind.ARROW_MEMORY:
		want_slot = memory_item(steps_spawned)
		layout = Layout.GRID if want_slot >= 4 else Layout.DIAMOND
	var w := {"planets": [], "z": SPAWN_Z, "resolved": false, "kind": kind, "layout": layout,
		"dir": -1, "parts": [], "avoid": false, "spot": [-1, -1, -1, -1, -1, -1, -1, -1]}
	var slots: Array = (LAYOUT_SLOTS[layout] as Array).duplicate()
	slots.shuffle()
	if want_slot >= 0:
		slots.erase(want_slot)
		slots.push_front(want_slot)
	slots = slots.slice(0, n)
	var correct_slot: int = slots[0]
	var colors: Array = []
	match kind:
		Kind.COLOR, Kind.MIX, Kind.MEMORY, Kind.SHELL:
			var want: int = pattern_color
			if kind == Kind.COLOR:
				want = pattern_colors[steps_spawned % PATTERN_LEN]
			elif kind == Kind.MEMORY:
				want = memory_item(steps_spawned)
			for i in GATE_COLORS.size():
				if i != want:
					colors.append(i)
			colors.shuffle()
			colors.push_front(want)
			w.avoid = kind == Kind.MIX and randf() < float(spec.avoid)
		Kind.SPOT:
			colors = range(GATE_COLORS.size())
			colors.shuffle()
			for i in slots.size():
				w.spot[slots[i]] = colors[i]
			var others: Array = range(GATE_COLORS.size()).filter(func(k): return k != colors[0])
			w.spot[correct_slot] = others[randi() % others.size()]
		Kind.ARROW_SUM:
			w.dir = correct_slot
			w.parts = (CORNER_PARTS[correct_slot] as Array).duplicate()
			w.parts.shuffle()
		_:
			w.dir = correct_slot
			w.avoid = kind == Kind.ARROW_MIX and randf() < float(spec.avoid)
	for i in slots.size():
		var s: int = slots[i]
		# An avoid step turns it round: the gate it names is the one wrong gate.
		var p := _make_gate(SLOTS[s], SPAWN_Z, "", (s == correct_slot) != bool(w.avoid))
		p["slot"] = s
		if not colors.is_empty():
			# slots[0] is the correct slot, and colors[0] the colour it wants.
			_tint_gate(p, GATE_COLORS[colors[i]])
		w.planets.append(p)
	if kind == Kind.SHELL:
		w["shell"] = _shell_moves(slots, int(spec.swaps))
	return w


## SHELL: the swaps for gates standing in `slots` (gate i in slots[i]), each
## two different gates trading places. `start` is where each gate begins.
static func _shell_moves(slots: Array, count: int) -> Dictionary:
	var swaps: Array = []
	for k in count:
		var a: int = randi() % slots.size()
		var b: int = (a + 1 + randi() % (slots.size() - 1)) % slots.size()
		swaps.append([a, b])
	return {"start": slots.duplicate(), "swaps": swaps}


## SHELL, each frame before the gates are placed: the colours go out at
## SHELL_HIDE, and the gates trade places one swap after another until
## SHELL_END, the two of a swap bowing apart so they pass rather than
## collide. A gate's slot changes the moment its swap begins, so the aim
## glow and the quarter follow where it is going, never where it will end.
func _shell_place(w: Dictionary) -> void:
	var a: float = approach(w.planets[0])
	var sh: Dictionary = w.shell
	var swaps: Array = sh.swaps
	var seg: float = (SHELL_END - SHELL_HIDE) / maxf(1.0, swaps.size())
	var slot_of: Array = (sh.start as Array).duplicate()
	var moving := {}
	for k in swaps.size():
		var t0: float = SHELL_HIDE + k * seg
		if a < t0:
			break
		var ga: int = swaps[k][0]
		var gb: int = swaps[k][1]
		var sa: int = slot_of[ga]
		var sb: int = slot_of[gb]
		slot_of[ga] = sb
		slot_of[gb] = sa
		var t: float = clampf((a - t0) / seg, 0.0, 1.0)
		if t < 1.0:
			moving[ga] = [sa, sb, t, 1.0]
			moving[gb] = [sb, sa, t, -1.0]
	var hidden: bool = a >= SHELL_HIDE
	for i in w.planets.size():
		var p: Dictionary = w.planets[i]
		p.slot = slot_of[i]
		var at: Vector2 = SLOTS[slot_of[i]]
		if moving.has(i):
			var mv: Array = moving[i]
			var from: Vector2 = SLOTS[mv[0]]
			var to: Vector2 = SLOTS[mv[1]]
			var s: float = smoothstep(0.0, 1.0, mv[2])
			var side: Vector2 = (to - from).orthogonal().normalized() * float(mv[3])
			at = from.lerp(to, s) + side * sin(PI * s) * SHELL_ARC
		p.pos = at
		if not p.has("true_glow"):
			p["true_glow"] = p.base_glow
		p.base_glow = GATE_GLOW if hidden else p.true_glow
		if p.get("portal") != null:
			_portal_color(p.portal, p.base_glow)


## SHELL, once judged: every gate shows its colour again, so the player sees
## where the colour really went.
func _shell_reveal(w: Dictionary) -> void:
	for p in w.planets:
		if p.has("true_glow"):
			p.base_glow = p.true_glow
			(p.glow as StandardMaterial3D).albedo_color = p.base_glow
			_portal_color(p.get("portal"), p.base_glow)


## A memory pattern's rounds for a whole pattern, `size` of `items` each,
## never the same one twice in a row, across rounds too.
func _memory_rounds(size: int, items: Array) -> Array:
	var rounds: Array = []
	var last := -1
	for r in ceili(float(PATTERN_LEN) / size):
		var round: Array = []
		for i in size:
			var pick: int = items[randi() % items.size()]
			while pick == last:
				pick = items[randi() % items.size()]
			round.append(pick)
			last = pick
		rounds.append(round)
	return rounds


## A memory pattern's items a round at the pattern's level.
func memory_len() -> int:
	return int(level_spec().get("len", 4))


## What a memory pattern's step `k` asks for: a colour for MEMORY, a slot
## for ARROW_MEMORY.
func memory_item(k: int) -> int:
	var size := memory_len()
	return pattern_rounds[k / size][k % size]


## The colour COLOR's front step asks for, which is what the box shows.
func color_now() -> int:
	return pattern_colors[mini(steps_done, PATTERN_LEN - 1)] if not pattern_colors.is_empty() else 0


## MEMORY: the world slows on a round's first step, if it has to, so the
## round's colours are up for MEMORY_SECONDS_EACH a colour before the gate.
## Called each frame before the world moves.
func _update_memory_slow(delta: float) -> void:
	memory_slow = 1.0
	if phase != Phase.PATTERN or not is_memory(pattern_kind) or steps_done % memory_len() != 0:
		return
	var w := upcoming_wave()
	if w.is_empty():
		return
	memory_shown += delta
	var need: float = memory_len() * MEMORY_SECONDS_EACH - memory_shown
	var full: float = speed()
	if need > 0.0 and full > 0.0 and -float(w.z) / full < need:
		memory_slow = clampf(-float(w.z) / (need * full), 0.15, 1.0)


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
		# The glow band carried the gate's colour until the portal came; the
		# portal now carries it across the whole hole, and the band around it
		# only doubled it (owner's call, 2026-11-27). glow_mat stays: it is
		# where the colour is kept, and the no-kit ring still wears it.
		if gate_glow_mesh != null and portal_shader == null:
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
	var portal: ShaderMaterial = _make_portal(node) if portal_shader != null else null
	node.rotation.z = randf() * TAU
	root3d.add_child(node)
	var p := {
		"node": node, "mat": null, "glow": glow_mat, "portal": portal, "pos": pos, "z": z, "label": label,
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
	_portal_color(p.get("portal"), p.base_glow)


## The ship went through `p`: it lights up gold if right, red if wrong. A
## right one bursts (_pass_burst), holds the world a moment and throws the
## camera (B), and its portal swirls shut (C). It flies on past the camera
## like the rest of its wave.
func _pass_gate(p: Dictionary, right: bool) -> void:
	p.alive = false
	p.flash = 1.0
	p.flash_color = GATE_GLOW_RIGHT if right else GATE_GLOW_WRONG
	if right:
		_pass_burst(p.node.position, Color(p.get("true_glow", p.base_glow)), streak + 1)
		hitstop = HITSTOP_TIME
		punch = 1.0
		if p.get("portal") != null:
			p["closing"] = 0.0
	elif p.get("portal") != null:
		p["fault"] = 0.0


## The colours a right pass that makes a streak of `count` bursts in, from
## the passed gate's `glow`: that colour and white; from PASS_PALETTE_STEPS[0]
## its opposite hue too; from PASS_PALETTE_STEPS[1] every hue of
## PASS_RAINBOW besides.
static func _pass_palette(glow: Color, count: int) -> Array:
	var base := Color(glow.r, glow.g, glow.b, 1.0)
	var out: Array = [base, base, Color(1, 1, 1)]
	if count >= int(PASS_PALETTE_STEPS[0]):
		out.append(Color.from_hsv(fmod(base.h + 0.5, 1.0), clampf(base.s, 0.5, 1.0), 1.0))
	if count >= int(PASS_PALETTE_STEPS[1]):
		out.append_array(PASS_RAINBOW)
	return out


## The burst of a right pass at `center`, in the palette of the gate's `glow`
## and the streak `count`: a bloom of light at the gate's middle, a light on
## the gate and the ship, a wide soft halo behind a crisp ring (and a second
## ring in the opposite hue from a long streak), shards with glowing heads,
## motes that linger and twinkle, and the speed lines for draw_pass_lines.
func _pass_burst(center: Vector3, glow: Color, count: int) -> void:
	var palette := _pass_palette(glow, count)
	var base: Color = palette[0]
	var bloom := MeshInstance3D.new()
	bloom.mesh = QuadMesh.new()
	bloom.material_override = _soft_material(_dot_texture(), base, PASS_BLOOM_GLOW, true)
	bloom.position = center + Vector3(0.0, 0.0, 0.1)
	root3d.add_child(bloom)
	flashes.append({"node": bloom, "t": 0.0, "life": PASS_BLOOM_LIFE, "kind": "bloom", "size": GATE_RADIUS})
	var light := OmniLight3D.new()
	light.light_color = base
	light.light_energy = PASS_LIGHT_ENERGY
	light.omni_range = PASS_LIGHT_RANGE
	light.position = center + Vector3(0.0, 0.0, 1.0)
	root3d.add_child(light)
	pass_lights.append({"node": light, "t": 0.0})
	_halo(center, base, 1.0)
	_shock(center, base, 1.0)
	if count >= int(PASS_PALETTE_STEPS[1]):
		var opposite := Color.from_hsv(fmod(base.h + 0.5, 1.0), 0.8, 1.0)
		_halo(center, opposite, 1.35)
		_shock(center, opposite, 1.35)
	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3(0.03, 0.03, 0.7)
	var head_mesh := QuadMesh.new()
	head_mesh.size = Vector2.ONE * PASS_SPARK_HEAD
	for i in PASS_SHARDS:
		var a: float = TAU * (i + randf_range(-0.3, 0.3)) / PASS_SHARDS
		var out := Vector3(cos(a), sin(a), 0.0)
		var c: Color = palette[randi() % palette.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = shard_mesh
		mi.material_override = _soft_material(null, c, PASS_SHARD_GLOW, false)
		mi.position = center + out * GATE_RADIUS
		# Laid along its flight, so it reads as a streak and not a speck,
		# with a soft glow at its head: a spark trailing its own light.
		var fly := out + Vector3(0, 0, PASS_SHARD_TOWARD)
		mi.look_at_from_position(mi.position, mi.position + fly, Vector3.FORWARD)
		var head := MeshInstance3D.new()
		head.mesh = head_mesh
		head.material_override = _soft_material(_dot_texture(), c, PASS_SHARD_GLOW, true)
		head.position = Vector3(0.0, 0.0, -0.35)
		mi.add_child(head)
		root3d.add_child(mi)
		flashes.append({"node": mi, "t": 0.0, "life": PASS_SHARD_LIFE * randf_range(0.7, 1.1), "kind": "shard",
			"vel": fly * PASS_SHARD_SPEED * randf_range(0.7, 1.2), "size": 1.0})
	var mote_mesh := QuadMesh.new()
	for i in PASS_MOTES:
		var a: float = randf() * TAU
		var out := Vector3(cos(a), sin(a), 0.0)
		var c: Color = palette[randi() % palette.size()]
		var mote := MeshInstance3D.new()
		mote.mesh = mote_mesh
		mote.material_override = _soft_material(_dot_texture(), c, 2.0, true)
		mote.position = center + out * GATE_RADIUS * randf_range(0.8, 1.6)
		root3d.add_child(mote)
		flashes.append({"node": mote, "t": 0.0, "life": PASS_MOTE_LIFE * randf_range(0.7, 1.2), "kind": "mote",
			"vel": out * randf_range(0.8, 2.0), "size": randf_range(PASS_MOTE_SIZE.x, PASS_MOTE_SIZE.y),
			"phase": randf() * TAU})
	var lines := []
	for i in PASS_LINES:
		lines.append([TAU * (i + randf()) / PASS_LINES, randf_range(0.5, 1.0), palette[randi() % palette.size()]])
	pass_lines = {"t": 0.0, "at": center, "lines": lines}


## One crisp shockwave ring of `color` round `center`, `size` times the gate.
func _shock(center: Vector3, color: Color, size: float) -> void:
	var shock := MeshInstance3D.new()
	var torus := TorusMesh.new()
	# Thin, since the whole torus scales with it and its tube thickens too.
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	shock.mesh = torus
	shock.material_override = _soft_material(null, color, PASS_SHOCK_GLOW, false)
	shock.rotation.x = PI * 0.5
	shock.position = center
	root3d.add_child(shock)
	flashes.append({"node": shock, "t": 0.0, "life": PASS_SHOCK_LIFE * size, "kind": "shock", "size": GATE_RADIUS * size})


## The soft halo behind a ring: a wide band of light, brightest at its middle
## and fading both ways, on a quad in the gate's plane.
func _halo(center: Vector3, color: Color, size: float) -> void:
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0
	halo.mesh = quad
	halo.material_override = _soft_material(_ring_texture(), color, PASS_HALO_GLOW, false)
	halo.position = center + Vector3(0.0, 0.0, -0.05)
	root3d.add_child(halo)
	flashes.append({"node": halo, "t": 0.0, "life": PASS_HALO_LIFE * size, "kind": "halo", "size": GATE_RADIUS * size})


## An unshaded, additive material of `color` lifted by `glow`, with `tex`
## (null for flat), turned to face the camera if `billboard`.
func _soft_material(tex: Texture2D, color: Color, glow: float, billboard: bool) -> StandardMaterial3D:
	var m := _add_material(Color(color.r * glow, color.g * glow, color.b * glow, 1.0))
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Without this a billboard ignores its node's scale: the motes and
		# the bloom, sized by scale, came out a whole unit across, blobs.
		m.billboard_keep_scale = true
	return m


## A soft round dot of light, made once.
func _dot_texture() -> Texture2D:
	if dot_tex == null:
		dot_tex = _radial_texture()
	return dot_tex


## A soft ring of light: clear in the middle, a bright band at 0.8 of the way
## out fading both ways, clear at the edge. Made once.
func _ring_texture() -> Texture2D:
	if ring_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.68, Color(1, 1, 1, 0))
		g.add_point(0.82, Color(1, 1, 1, 0.8))
		g.add_point(0.86, Color(1, 1, 1, 1))
		g.add_point(0.93, Color(1, 1, 1, 0.2))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		ring_tex = t
	return ring_tex


## The green rings where the gates that were right stood, after a wrong one:
## on the flight plane, at full size, where the gate was judged. Drawn on the
## gate as it flew on at first, the ring left the screen with it in 0.15 s,
## before it could be read. Bright and pulsing, fading out over REVEAL_TIME.
func _draw_reveals(ci: CanvasItem) -> void:
	for r in reveals:
		var at: Vector2 = r.p.pos
		var s := project(Vector3(at.x, at.y, 0.0))
		if s.z <= 0.0:
			continue
		var u: float = clampf(r.t / REVEAL_TIME, 0.0, 1.0)
		var radius: float = s.z * GATE_RADIUS * GATE_OUTER_OF_HOLE * float(r.p.base_scale) * 0.95
		if radius < 2.0:
			continue
		var a: float = (1.0 - u * u) * (0.75 + 0.25 * sin(r.t * 30.0))
		var c := Vector2(s.x, s.y)
		var k: float = px_per_unit() / 100.0
		# A faint fill, a wide soft band and a bold line: thin, it was there
		# but easy to miss.
		ci.draw_circle(c, radius, Color(REVEAL_COLOR, a * 0.12))
		ci.draw_arc(c, radius + 5.0 * k, 0.0, TAU, 56, Color(REVEAL_COLOR, a * 0.35), 14.0 * k, true)
		ci.draw_arc(c, radius, 0.0, TAU, 56, Color(REVEAL_COLOR.lightened(0.3), a), 6.0 * k, true)


## The speed lines of the last right pass, bursting out of the gate's centre
## on the screen and gone in PASS_LINE_LIFE: each a thin wedge running out
## from inside the ring past its edge, white and widest at its root, its own
## colour at a sharp tip, fading as it goes.
func draw_pass_lines(ci: CanvasItem) -> void:
	if pass_lines.is_empty():
		return
	var u: float = clampf(pass_lines.t / PASS_LINE_LIFE, 0.0, 1.0)
	var s := project(pass_lines.at)
	if s.z <= 0.0:
		return
	var c := Vector2(s.x, s.y)
	var r: float = s.z * GATE_RADIUS
	var ease_out: float = 1.0 - (1.0 - u) * (1.0 - u)
	var k: float = px_per_unit() / 100.0
	var fade: float = (1.0 - u) * 0.85
	var half: float = maxf(0.6, 1.6 * k * (1.0 - u))
	for l in pass_lines.lines:
		var dir := Vector2.from_angle(l[0])
		var side := dir.orthogonal() * half
		var inner: float = r * lerpf(0.9, 2.6, ease_out)
		var outer: float = inner + r * lerpf(0.6, 2.4, ease_out) * l[1]
		var tip: Color = l[2]
		ci.draw_polygon(PackedVector2Array([c + dir * inner + side, c + dir * outer, c + dir * inner - side]),
			PackedColorArray([Color(1, 1, 1, fade), Color(tip, 0.0), Color(1, 1, 1, fade)]))


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
	var gate: bool = p.get("gate", false)
	grow *= 1.0 - smoothstep(0.0, PASS_GATE_SHRINK if gate else PASS_SHRINK_DISTANCE, p.z)
	var node: MeshInstance3D = p.node
	var at: Vector2 = p.pos
	if gate and p.z > 0.0:
		# Drawn only: p.pos, which judging and the pull read, stays put.
		var out: Vector2 = at.normalized() if at.length() > 0.01 else Vector2.UP
		# sqrt: out fast at first, so the top gate is past the question box
		# before it is big; squared, it hung over the box and the next step.
		var u: float = sqrt(clampf(p.z / CAMERA_POS.z, 0.0, 1.0))
		at += out * PASS_SPREAD * u
	node.position = Vector3(at.x, at.y, p.z)
	node.scale = Vector3.ONE * maxf(p.base_scale * grow, 0.0001)


func _touching(p: Dictionary) -> bool:
	return ship_shown().distance_to(p.pos) <= p.radius + SHIP_HIT_RADIUS


## Eases the world toward the streak's speed, and lets the lunge after a pass
## and the ship's squeeze wear off.
func _update_pace(delta: float) -> void:
	pace = lerpf(pace, _pace_target(), 1.0 - exp(-PACE_EASE * delta))
	boost = maxf(0.0, boost - WARP_BOOST_DECAY * delta)
	if not pulling:
		squeeze = maxf(0.0, squeeze - SQUEEZE_RECOVER * delta)


## The draw. From CAPTURE_Z the ship is pulled toward the gate of the quarter
## it is steered into, arriving as the step reaches the plane. The player
## keeps steering all the way: ship_pos is where the finger puts the ship,
## and the pull is laid over it (pull_pos, shown by ship_shown()), so moving
## to another quarter changes the gate, and the pull glides over to it
## (PULL_GLIDE). Only at CAPTURE_LOCK of the way in is the gate fixed. The
## pull grows as u^CAPTURE_PULL_POW: barely there at first, then it snaps
## shut, which is what being sucked in looks like.
func _draw_in(w: Dictionary, delta: float) -> void:
	var locked: bool = w.has("target")
	var aim: Dictionary = w.target if locked else target_gate(w, ship_pos)
	for p in w.planets:
		p["aim"] = w.z >= AIM_Z and is_same(p, aim)
	if w.z < CAPTURE_Z:
		return
	var u: float = clampf((w.z - CAPTURE_Z) / -CAPTURE_Z, 0.0, 1.0)
	if not locked and u >= CAPTURE_LOCK:
		w["target"] = aim
	if not w.has("anchor"):
		w["anchor"] = ship_pos
	var goal: Vector2 = aim.pos if not aim.is_empty() else ship_pos
	w.anchor = (w.anchor as Vector2).lerp(goal, 1.0 - exp(-PULL_GLIDE * delta))
	var e: float = pow(u, CAPTURE_PULL_POW)
	pull_pos = ship_pos.lerp(w.anchor, e)
	pulling = true
	squeeze = e if not aim.is_empty() else maxf(0.0, squeeze - SQUEEZE_RECOVER * delta)


## Where the ship is on the plane: where it is steered, or, while a gate is
## drawing it in, where the pull has it. Everything drawn at the ship and
## everything that hits it uses this.
func ship_shown() -> Vector2:
	return pull_pos if pulling else ship_pos

## Which quarter of the field `pos` is in, as a slot index of `layout`. The
## diamond's field is cut along its diagonals, measured against FIELD_HALF
## so the cut runs corner to corner on screen; the grid's along its middle
## lines. Either way each quarter holds exactly one of the layout's slots.
static func region_of(pos: Vector2, layout: int = Layout.DIAMOND) -> int:
	if layout == Layout.GRID:
		return (4 if pos.y > 0.0 else 6) + (0 if pos.x < 0.0 else 1)
	var n := pos / FIELD_HALF
	if absf(n.x) >= absf(n.y):
		return 0 if n.x < 0.0 else 1
	return 2 if n.y > 0.0 else 3


## The gate of `w` in the quarter `pos` is in, or {} when that quarter has none.
func target_gate(w: Dictionary, pos: Vector2) -> Dictionary:
	var r := region_of(pos, int(w.get("layout", Layout.DIAMOND)))
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
	if w.has("shell"):
		_shell_reveal(w)
	# The gate the ship was drawn into; a step that somehow skipped the capture
	# (a frame long enough to jump CAPTURE_Z) is judged by the quarter now.
	var hit: Dictionary = w.target if w.has("target") else target_gate(w, ship_pos)
	if not hit.is_empty():
		ship_pos = hit.pos
		ship_target = hit.pos
		pulling = false
		boost = 1.0
	_note_rule_change()
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
		shake = WRONG_SHAKE_TIME
		for p in w.planets:
			if p.correct and not is_same(p, hit):
				reveals.append({"p": p, "t": 0.0})
		streak = 0
		main._space_wrong()


## After a step is judged: a MEMORY round that starts now shows its colours
## from scratch, and COLOR's box flashing with a chime when the next step
## asks for another colour.
func _note_rule_change() -> void:
	if steps_done >= PATTERN_LEN:
		return
	if is_memory(pattern_kind) and steps_done % memory_len() == 0:
		memory_shown = 0.0
		rule_flash = 1.0
	elif pattern_kind == Kind.COLOR and pattern_colors[steps_done] != pattern_colors[steps_done - 1]:
		rule_flash = 1.0
		if main != null and main.has_method("_space_rule_changed"):
			main._space_rule_changed()


## The last step of the pattern has been judged and flown past: a whole
## pattern right is worth a better weapon and the fever; then the boss once
## the cycle's patterns are done, or the next pattern.
func _end_pattern() -> void:
	patterns_done += 1
	if pattern_perfect():
		_power_up(true)
	fever_time = fever_for(steps_right)
	if fever_time > 0.0:
		_enter(Phase.FEVER)
	else:
		_after_fever()


## The fever a pattern with `right` gates right earns, in seconds; 0 for none.
static func fever_for(right: int) -> float:
	if right < FEVER_MIN_RIGHT:
		return 0.0
	return FEVER_PER_RIGHT * right + (FEVER_PERFECT_BONUS if right >= PATTERN_LEN else 0.0)


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
			_fire_orb(ship_shown() + Vector2((i - (shots - 1) * 0.5) * 1.1, 0.0))


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
	var shown := ship_shown()
	var origin := Vector3(shown.x, shown.y, -0.8)
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
	rule_flash = maxf(0.0, rule_flash - RULE_FLASH_DECAY * delta)
	# The hold after a right pass (B): the world, the ship and the pull wait;
	# the effects, which run on their own clocks, carry on.
	var held: bool = hitstop > 0.0
	hitstop = maxf(0.0, hitstop - delta)
	if (steerable or running) and not held:
		_update_ship(delta)
	if running and not held:
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
	_update_memory_slow(delta)
	var v := speed() * delta
	_fire(delta)
	_update_bullets(delta)
	if not main.space_run_live():
		return
	# Pattern steps.
	pulling = false
	for w in waves:
		w.z += v
		for p in w.planets:
			p.z = w.z
		if not w.resolved and w.has("shell"):
			_shell_place(w)
		if not w.resolved:
			_draw_in(w, delta)
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
			if at.distance_to(ship_shown()) <= ORB_RADIUS + SHIP_HIT_RADIUS and not main._space_invulnerable():
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
			if fever_spawn_timer <= 0.0 and phase_time < fever_time - 1.0:
				fever_spawn_timer = FEVER_SPAWN_INTERVAL
				_spawn_fever_planets()
			if phase_time >= fever_time:
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
		var shown := ship_shown()
		ship_pivot.position = Vector3(shown.x, shown.y, 0.0)
		var bank: float = clampf(-ship_vel.x * SHIP_BANK_PER_SPEED, -SHIP_BANK_MAX, SHIP_BANK_MAX)
		var pitch: float = clampf(ship_vel.y * SHIP_PITCH_PER_SPEED, -SHIP_PITCH_MAX, SHIP_PITCH_MAX)
		# Drawn in, the ship shrinks and rolls one full turn into the hole; the
		# turn ends where it began, so nothing jumps when it lets go.
		ship_pivot.rotation = Vector3(pitch, 0.0, bank + squeeze * TAU)
		ship_pivot.scale = Vector3.ONE * lerpf(1.0, CAPTURE_SHIP_SCALE, squeeze)
		ship_pivot.visible = main == null or main._hurt_blink_alpha() > 0.5
	for i in drone_nodes.size():
		var side: float = -1.0 if i == 0 else 1.0
		var sp := ship_shown()
		var want := Vector3(sp.x + side * 1.15, sp.y + 0.35, 0.3)
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
		elif f.kind == "shock":
			var grow: float = 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u)
			node.scale = Vector3.ONE * lerpf(1.0, PASS_SHOCK_GROW, grow) * f.size
			m.albedo_color.a = (1.0 - u) * (1.0 - u) * (1.0 - u)
		elif f.kind == "shard":
			node.position += f.vel * delta
			f.vel *= maxf(0.0, 1.0 - 2.5 * delta)
			node.scale = Vector3.ONE * maxf(1.0 - u, 0.0001)
		elif f.kind == "bloom":
			# Out fast and gone: a breath of light, not a ball.
			var out: float = 1.0 - (1.0 - u) * (1.0 - u)
			node.scale = Vector3.ONE * lerpf(PASS_BLOOM_SIZE.x, PASS_BLOOM_SIZE.y, out) * f.size
			m.albedo_color.a = (1.0 - u) * (1.0 - u)
		elif f.kind == "halo":
			var spread: float = 1.0 - pow(1.0 - u, 3.0)
			node.scale = Vector3.ONE * lerpf(1.0, PASS_HALO_GROW, spread) * f.size
			m.albedo_color.a = (1.0 - u) * (1.0 - u)
		elif f.kind == "mote":
			node.position += f.vel * delta
			f.vel *= maxf(0.0, 1.0 - 3.0 * delta)
			# A twinkle: the size pulses, the light dies out.
			var twinkle: float = 0.6 + 0.4 * sin(f.t * 28.0 + f.phase)
			node.scale = Vector3.ONE * f.size * twinkle * (1.0 - u * 0.5)
			m.albedo_color.a = 1.0 - u * u
		else:
			node.scale = Vector3.ONE * lerpf(1.0, 2.8, u) * f.size
			m.albedo_color.a = (1.0 - u) * (1.0 - u) * 0.8
	for f in flashes:
		if f.t >= f.life:
			_free(f.node)
	flashes = flashes.filter(func(f): return f.t < f.life)
	for l in pass_lights:
		l.t += delta
		(l.node as OmniLight3D).light_energy = PASS_LIGHT_ENERGY * pow(maxf(0.0, 1.0 - l.t / PASS_LIGHT_LIFE), 2.0)
		if l.t >= PASS_LIGHT_LIFE:
			_free(l.node)
	pass_lights = pass_lights.filter(func(l): return l.t < PASS_LIGHT_LIFE)
	if not pass_lines.is_empty():
		pass_lines.t += delta
		if pass_lines.t >= PASS_LINE_LIFE:
			pass_lines = {}
	var flow: float = speed() if running else BASE_SPEED * 0.25
	var stretch: float = (3.0 if phase == Phase.FEVER else 1.0) * (1.0 + PASS_STREAK_STRETCH * boost)
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
		punch = maxf(0.0, punch - punch * (1.0 - exp(-CAMERA_PUNCH_EASE * delta)) - 0.001)
		shake = maxf(0.0, shake - delta)
		var jolt: float = sin(shake * WRONG_SHAKE_FREQ) * WRONG_SHAKE * (shake / WRONG_SHAKE_TIME)
		camera.position = CAMERA_POS + Vector3(jolt, 0.0, -CAMERA_PUNCH * punch)
		for r in reveals:
			r.t += delta
		reveals = reveals.filter(func(r): return r.t < REVEAL_TIME)


func _animate(p: Dictionary, delta: float) -> void:
	var node: MeshInstance3D = p.node
	node.rotation += p.spin * delta
	# C: the passed gate's portal flares, then swirls shut toward its middle.
	# A wrong gate's portal sputters red, in hard on-off flickers, and goes out.
	if p.has("fault") and p.get("portal") != null:
		p.fault += delta
		var ft: float = clampf(p.fault / WRONG_FAULT_TIME, 0.0, 1.0)
		var on: float = 1.0 if sin(p.fault * 70.0) > -0.2 else 0.15
		var fm: ShaderMaterial = p.portal
		_portal_color(fm, GATE_GLOW_WRONG)
		fm.set_shader_parameter("emission_strength", PORTAL_EMISSION * on * (1.0 - ft) * 1.6)
		fm.set_shader_parameter("open_amount", maxf(0.001, 1.0 - ft))
	if p.has("closing") and p.get("portal") != null:
		p.closing += delta
		var t: float = clampf(p.closing / PORTAL_CLOSE_TIME, 0.0, 1.0)
		var m: ShaderMaterial = p.portal
		m.set_shader_parameter("open_amount", maxf(0.001, 1.0 - t * t))
		m.set_shader_parameter("emission_strength", PORTAL_EMISSION * lerpf(PORTAL_CLOSE_FLARE, 1.0, t))
		m.set_shader_parameter("speed_scale", lerpf(4.0, 1.0, t))
	if p.flash > 0.0:
		p.flash = maxf(0.0, p.flash - delta * 2.0)
		if p.get("gate", false):
			var lit: Color = p.flash_color
			(p.glow as StandardMaterial3D).albedo_color = (p.base_glow as Color).lerp(Color(lit.r * 2.5, lit.g * 2.5, lit.b * 2.5, 1.0), p.flash)
			_portal_color(p.get("portal"), (p.base_glow as Color).lerp(lit, p.flash))
		else:
			p.mat.set_shader_parameter("hit_flash", p.flash)
	elif p.get("gate", false) and p.alive:
		var glow: Color = _aim_glow(p) if p.get("aim", false) else p.base_glow
		(p.glow as StandardMaterial3D).albedo_color = glow
		_portal_color(p.get("portal"), glow)
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


## The answers of the next wave, each in its own gate's hole, growing as the
## gate flies in. They appear over LABEL_FADE, once the gates have spread far
## enough apart for their plates not to overlap, and never earlier — showing
## them in advance on the flight plane was tried and covered the screen.
## The plate drawn over the gate the ship is being pulled into thins out so the
## ship shows through it.
func draw_labels(ci: CanvasItem, font: Font) -> void:
	draw_pass_lines(ci)
	_draw_reveals(ci)
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
			_draw_swatch(ci, c, box.size.y * 0.3, GATE_COLORS[color_now()])
			_draw_rule_flash(ci, c, box.size.y * 0.3)
			if demo_avoid and fmod(Time.get_ticks_msec() / 1000.0, DEMO_AVOID_PERIOD * 2.0) >= DEMO_AVOID_PERIOD:
				_draw_cross(ci, c, box.size.y * 0.3)
		elif pattern_kind == Kind.MIX or pattern_kind == Kind.SHELL:
			_draw_swatch(ci, c, box.size.y * 0.3, GATE_COLORS[pattern_color])
			if not w.is_empty() and w.get("avoid", false):
				_draw_cross(ci, c, box.size.y * 0.3)
		elif is_memory(pattern_kind):
			_draw_memory(ci, font, c, box)
		elif not w.is_empty():
			var hidden: bool = approach(w.planets[0]) > float(level_spec().get("hide", 1.0))
			match pattern_kind:
				Kind.SPOT:
					var blank := [-1, -1, -1, -1, -1, -1, -1, -1]
					_draw_spot(ci, c, box.size.y, blank if hidden else w.spot, int(w.layout))
				Kind.ARROW_SUM:
					if not hidden:
						_draw_sum(ci, font, c, box.size.y, w.parts)
				_:
					_draw_arrow(ci, c, box.size.y * 0.34, int(w.dir), ARROW_NORMAL)
					if w.get("avoid", false):
						_draw_cross(ci, c, box.size.y * 0.3)
	var rect := gauge_rect(box)
	main._draw_horizontal_slice(ArtSlot.texture(HUD_GAUGE_PATH), rect, HUD_GAUGE_CAP, ci)
	var inner := rect.grow_individual(-HUD_GAUGE_INSET.x, -HUD_GAUGE_INSET.y, -HUD_GAUGE_INSET.x, -HUD_GAUGE_INSET.y)
	var gh: float = inner.size.y
	var frac := 0.0
	var col := Color(0.35, 0.85, 1.0)
	match phase:
		Phase.FEVER:
			frac = 1.0 - clampf(phase_time / maxf(fever_time, 0.01), 0.0, 1.0)
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


## Kind.COLOR's rule: a round swatch of the colour to fly through, ringed so
## it holds on any background.
func _draw_swatch(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(c, r + 3.0, Color(0.05, 0.04, 0.12))
	ci.draw_circle(c, r, color)
	ci.draw_circle(c + Vector2(-r, -r) * 0.3, r * 0.28, Color(1, 1, 1, 0.35))


## The avoid step's sign: a red ring round the swatch with one thin slash
## across it, the no-entry sign. A bold X was tried first and covered the
## colour it was crossing out, and a red X on red hardly showed at all; the
## ring sits outside the swatch and the slash leaves most of it showing.
## `r` is the swatch's radius.
func _draw_cross(ci: CanvasItem, c: Vector2, r: float) -> void:
	var ring: float = r + 6.0
	ci.draw_arc(c, ring, 0.0, TAU, 40, Color(0.05, 0.04, 0.12), 6.5, true)
	ci.draw_arc(c, ring, 0.0, TAU, 40, AVOID_CROSS, 3.5, true)
	var d := Vector2(1, -1).normalized() * ring
	ci.draw_line(c - d, c + d, Color(0.05, 0.04, 0.12), 6.0)
	ci.draw_line(c - d, c + d, AVOID_CROSS, 3.0)


## A ring swelling out of the box's swatch as it fades, when the rule changes.
func _draw_rule_flash(ci: CanvasItem, c: Vector2, r: float) -> void:
	if rule_flash <= 0.0:
		return
	ci.draw_arc(c, r + 4.0 + (1.0 - rule_flash) * 16.0, 0.0, TAU, 40, Color(1, 1, 1, rule_flash), 3.0, true)


## Kind.MEMORY's box: the round's colours in a row. Until the round's first
## step is judged all of them show; after it, the ones flown through stay,
## dimmed, and the rest are "?".
func _draw_memory(ci: CanvasItem, font: Font, c: Vector2, box: Rect2) -> void:
	if pattern_rounds.is_empty():
		return
	var size := memory_len()
	var round: Array = pattern_rounds[mini(steps_done / size, pattern_rounds.size() - 1)]
	var at: int = steps_done % size
	# The last round of a pattern can be short (12 = 5 + 5 + 2): show only its steps.
	var n: int = mini(size, PATTERN_LEN - (steps_done / size) * size)
	# Six items have to fit between the box's end caps.
	var r: float = minf(box.size.y * 0.17, box.size.x * 0.6 / (n * 2.9))
	var gap: float = r * 2.9
	var x0: float = c.x - gap * (n - 1) * 0.5
	for i in n:
		var p := Vector2(x0 + gap * i, c.y)
		var arrows: bool = pattern_kind == Kind.ARROW_MEMORY
		if at == 0 or i >= at:
			if at == 0:
				if arrows:
					_draw_arrow(ci, p, r * 1.1, int(round[i]), ARROW_NORMAL)
				else:
					_draw_swatch(ci, p, r, GATE_COLORS[round[i]])
			else:
				ci.draw_circle(p, r + 3.0, Color(0.05, 0.04, 0.12))
				ci.draw_circle(p, r, Color(0.22, 0.25, 0.36))
				var fs := int(r * 1.5)
				var tw: float = font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				ci.draw_string(font, Vector2(p.x - tw * 0.5, p.y + fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.9, 1.0))
		elif arrows:
			_draw_arrow(ci, p, r * 0.9, int(round[i]), Color(ARROW_NORMAL, MEMORY_DONE_ALPHA))
		else:
			var k: Color = GATE_COLORS[round[i]]
			ci.draw_circle(p, r * 0.8, Color(k, MEMORY_DONE_ALPHA))


## ARROW_SUM's box: its two arrows with a plus between them.
func _draw_sum(ci: CanvasItem, font: Font, c: Vector2, h: float, parts: Array) -> void:
	if parts.size() < 2:
		return
	var off: float = h * 0.62
	_draw_arrow(ci, c - Vector2(off, 0.0), h * 0.28, int(parts[0]), ARROW_NORMAL)
	_draw_arrow(ci, c + Vector2(off, 0.0), h * 0.28, int(parts[1]), ARROW_NORMAL)
	var fs := int(h * 0.42)
	var tw: float = font.get_string_size("+", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.9, 1.0))


## Kind.SPOT's box: one dot per slot of `layout`, placed as the slots are on
## the field, coloured as `spot` says; a slot with no gate a faint ring.
func _draw_spot(ci: CanvasItem, c: Vector2, h: float, spot: Array, layout: int) -> void:
	# Kept inside the frame's dark middle, about 0.66 of the box's height:
	# at 0.27 apart and 0.15 across, the top and bottom dots sat on the frame.
	# Flattened (up and down closer than left and right) to fit.
	var dy: float = h * 0.2
	var dx: float = h * 0.52
	var r: float = h * 0.13
	# The grid's corners take the same height, closer in sideways.
	var gx: float = h * 0.3
	var at := [Vector2(-dx, 0.0), Vector2(dx, 0.0), Vector2(0.0, -dy), Vector2(0.0, dy),
		Vector2(-gx, -dy), Vector2(gx, -dy), Vector2(-gx, dy), Vector2(gx, dy)]
	for s in LAYOUT_SLOTS[layout]:
		var k: int = spot[s]
		if k < 0:
			ci.draw_arc(c + at[s], r * 0.7, 0.0, TAU, 20, SPOT_EMPTY, 1.5, true)
		else:
			_draw_swatch(ci, c + at[s], r, GATE_COLORS[k])


func _draw_arrow(ci: CanvasItem, c: Vector2, size: float, dir: int, color: Color) -> void:
	# Drawn pointing right, then turned to the slot: left, right, up, down,
	# then the grid's up-left, up-right, down-left, down-right.
	var pts := PackedVector2Array([
		Vector2(-0.9, -0.28), Vector2(0.15, -0.28), Vector2(0.15, -0.62),
		Vector2(0.95, 0.0), Vector2(0.15, 0.62), Vector2(0.15, 0.28), Vector2(-0.9, 0.28)])
	var ang: float = [PI, 0.0, -PI * 0.5, PI * 0.5, -PI * 0.75, -PI * 0.25, PI * 0.75, PI * 0.25][dir]
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
	var at := ship_shown()
	var s := project(Vector3(at.x, at.y, 0.0))
	var half: float = maxf(s.z * SHIP_WIDTH * 0.55, 20.0)
	return Rect2(Vector2(s.x, s.y) - Vector2(half, half * 0.7), Vector2(half * 2.0, half * 1.4))


## The progress gauge under the question box (draw_hud draws it here).
func gauge_rect(box: Rect2) -> Rect2:
	var gw: float = box.size.x * 0.9
	return Rect2(Vector2(box.get_center().x - gw * 0.5, box.end.y + 6.0), Vector2(gw, 16.0))


## The weapon readout, bottom right (draw_hud writes it here).
func weapon_label_rect() -> Rect2:
	return Rect2(Vector2(view_size.x - 238.0, view_size.y - 40.0), Vector2(230.0, 30.0))
